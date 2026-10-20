import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'booking_tracking_screen.dart'; // imports ChatSheet
import 'inspection_upload_screen.dart';
import '../utils/secure_storage_path.dart';
import '../widgets/error_display.dart';
import '../widgets/garage_addons.dart';

class BookingDetailsScreen extends StatefulWidget {
  final Map booking;
  final bool autoOpenChat;

  const BookingDetailsScreen({
    super.key,
    required this.booking,
    this.autoOpenChat = false,
  });

  @override
  State<BookingDetailsScreen> createState() => _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends State<BookingDetailsScreen> {
  final descController = TextEditingController();

  String selectedStage = 'Car Picked Up';
  Uint8List? selectedImageBytes;
  bool loading = false;
  bool hasUnreadMessages = false;
  bool markingDone = false;
  bool checkingReturnOtp = false;
  bool generatingReturnOtp = false;
  bool confirmingPayment = false;
  bool checkingPickupOtp = false;
  bool generatingPickupOtp = false;

  /// Stage picked by hand from "Any stage" (null = use the suggested next
  /// stage).
  String? _stageOverride;

  /// Updates already sent to the customer (newest first).
  List<Map<String, dynamic>> _updates = const [];

  /// Short-lived photo links, made once per photo (not on every rebuild).
  final Map<String, Future<String?>> _photoLinks = {};

  /// This 'bookings' row has no delivery-partner trip — the customer comes
  /// to collect the vehicle in person, so MARK AS DONE below is what
  /// generates the return code (rather than a delivery partner doing it
  /// from web/deliverydashboard.html at the out_for_delivery leg).
  bool get hasPickupDrop =>
      (widget.booking['pickupdrop'] ?? '').toString().toLowerCase() == 'yes';

  /// Cash on Pickup — for a no-pickup-drop booking, this is what gates the
  /// COLLECT PAYMENT step below on the return OTP being confirmed, instead
  /// of closing the booking out immediately the way a prepaid one does.
  bool get isCod =>
      (widget.booking['payment_status'] ?? '').toString().toLowerCase() == 'cod';

  final stages = [
    'Car Picked Up',
    'Inspection In Progress',
    'Inspection Completed',
    'Service In Progress',
    'Billing Process',
    'Delivered',
  ];

  // Neither the drop-off/return OTP boxes nor the MARK AS DONE/COLLECT
  // PAYMENT buttons above have any way to hear about a change the
  // *customer* makes (entering a code, say) while this screen is already
  // open — there's no Realtime subscription wired up here, just the
  // manual CHECK AGAIN buttons. Polling picks those up automatically
  // instead of leaving staff to keep tapping CHECK AGAIN themselves.
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    checkUnreadMessages();
    _loadUpdates();
    if (widget.autoOpenChat) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openChat());
    }
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      _autoRefreshBooking();
      checkUnreadMessages();
    });
  }

  /// Silently re-pulls this booking's own live status/OTP columns —
  /// unlike _refreshReturnOtpStatus/_refreshPickupOtpStatus (kept as-is
  /// for the manual CHECK AGAIN buttons), this doesn't toggle their
  /// loading flags, so the periodic poll above doesn't flicker those
  /// buttons' spinners every 15 seconds.
  Future<void> _autoRefreshBooking() async {
    try {
      final row = await Supabase.instance.client
          .from('bookings')
          .select(
            'booking_status, marked_done_at, pickup_otp_code, pickup_otp_verified_at, return_otp_code, return_otp_verified_at',
          )
          .eq('id', widget.booking['id'])
          .single();

      if (!mounted) return;
      setState(() {
        widget.booking['booking_status'] = row['booking_status'];
        widget.booking['marked_done_at'] = row['marked_done_at'];
        widget.booking['pickup_otp_code'] = row['pickup_otp_code'];
        widget.booking['pickup_otp_verified_at'] = row['pickup_otp_verified_at'];
        widget.booking['return_otp_code'] = row['return_otp_code'];
        widget.booking['return_otp_verified_at'] = row['return_otp_verified_at'];
      });
    } catch (e) {
      // Silent — this is a background poll, not a user-initiated action;
      // the manual CHECK AGAIN buttons still surface errors if staff
      // explicitly ask for a refresh.
    }
  }

  @override
  void dispose() {
    descController.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> checkUnreadMessages() async {
    final supabase = Supabase.instance.client;

    try {
      final response = await supabase
          .from('booking_chats')
          .select()
          .eq('booking_id', widget.booking['id'])
          .eq('sender', 'consumer')
          .eq('is_read_by_admin', false);

      if (!mounted) return;

      setState(() {
        hasUnreadMessages = (response as List).isNotEmpty;
      });
    } catch (e) {
      // Non-fatal — the unread badge just won't show if this fails.
    }
  }

  void openChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChatSheet(
        bookingId: widget.booking['id'],
        sender: 'admin',
        onMessagesRead: () {
          setState(() => hasUnreadMessages = false);
        },
      ),
    );
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() => selectedImageBytes = bytes);
  }

  Future<void> uploadUpdate() async {
    if (selectedImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload image')),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final supabase = Supabase.instance.client;

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}-${secureStorageToken()}';

      await supabase.storage
          .from('booking-images')
          .uploadBinary(fileName, selectedImageBytes!);

      // Store the storage PATH, not a permanent public URL — the
      // booking-images bucket is private, so the display side mints a
      // short-lived signed URL on demand (see booking_tracking_screen.dart).
      await supabase.from('booking_updates').insert({
        'booking_id': widget.booking['id'],
        'stage': selectedStage,
        'description': descController.text,
        'image_url': fileName,
      });

      await supabase.from('bookings').update({
        'booking_status': selectedStage,
        'has_unread_update': true,
      }).eq('id', widget.booking['id']);

      if (!mounted) return;

      // Stay here and move on to the next step.
      setState(() {
        widget.booking['booking_status'] = selectedStage;
        selectedImageBytes = null;
        descController.clear();
        _stageOverride = null;
      });
      _loadUpdates();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update sent — customer notified ($selectedStage)')),
      );
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not upload this update. Please try again.',
      );
    }

    if (mounted) setState(() => loading = false);
  }

  /// One-tap "service work is physically finished" signal — separate from
  /// the stage dropdown above (which requires a photo) since this just
  /// needs to fire notifications, not document progress. Setting
  /// `booking_status` here is what the notify-on-db-change Edge Function
  /// watches for (on `bookings` UPDATE) to notify the customer always, and
  /// the assigned delivery partner too when this booking actually has a
  /// pickup/drop trip for them to make.
  ///
  /// When there's no pickup/drop trip, this also generates the return
  /// OTP — there's no delivery partner to do it later, so the customer's
  /// in-person collection needs to be confirmed right here instead. The
  /// customer verifies it from vehicle_bookings_screen.dart's
  /// _ReturnOtpVerification before this booking counts as truly closed.
  Future<void> _markAsDone() async {
    setState(() => markingDone = true);

    try {
      final supabase = Supabase.instance.client;
      final nowIso = DateTime.now().toIso8601String();

      final update = <String, dynamic>{
        'booking_status': 'Ready for Pickup',
        'marked_done_at': nowIso,
      };

      String? returnOtpCode;
      if (!hasPickupDrop) {
        returnOtpCode = (1000 + math.Random().nextInt(9000)).toString();
        update['return_otp_code'] = returnOtpCode;
        update['return_otp_generated_at'] = nowIso;
      }

      await supabase
          .from('bookings')
          .update(update)
          .eq('id', widget.booking['id']);

      if (!mounted) return;

      // Mutating the passed-in booking map in place is what flips the
      // button below into its "already marked" state without needing to
      // leave this screen and re-fetch.
      widget.booking['booking_status'] = 'Ready for Pickup';
      widget.booking['marked_done_at'] = nowIso;
      if (returnOtpCode != null) {
        widget.booking['return_otp_code'] = returnOtpCode;
        widget.booking['return_otp_generated_at'] = nowIso;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked done — customer notified')),
      );
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not mark this booking as done. Please try again.',
      );
    }

    if (mounted) setState(() => markingDone = false);
  }

  /// Re-pulls just the verification timestamp so the OTP box below can
  /// flip to its "customer confirmed" state without leaving this screen —
  /// mirrors web/deliverydashboard.html's own "Check Again" button.
  Future<void> _refreshReturnOtpStatus() async {
    setState(() => checkingReturnOtp = true);

    try {
      final row = await Supabase.instance.client
          .from('bookings')
          .select('return_otp_verified_at')
          .eq('id', widget.booking['id'])
          .single();

      if (!mounted) return;
      widget.booking['return_otp_verified_at'] = row['return_otp_verified_at'];
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not check the pickup confirmation status. Please try again.',
      );
    }

    if (mounted) setState(() => checkingReturnOtp = false);
  }

  /// Generates the return code on demand — covers bookings that were
  /// already marked done *before* this feature existed (so _markAsDone's
  /// own generation never ran for them) as well as a first attempt that
  /// failed partway through. Without this, a booking stuck with
  /// marked_done_at set but no return_otp_code had no way to ever get one.
  Future<void> _generateReturnOtpNow() async {
    setState(() => generatingReturnOtp = true);

    try {
      final code = (1000 + math.Random().nextInt(9000)).toString();
      final nowIso = DateTime.now().toIso8601String();

      await Supabase.instance.client
          .from('bookings')
          .update({'return_otp_code': code, 'return_otp_generated_at': nowIso})
          .eq('id', widget.booking['id']);

      if (!mounted) return;
      widget.booking['return_otp_code'] = code;
      widget.booking['return_otp_generated_at'] = nowIso;
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not generate the return code. Please try again.',
      );
    }

    if (mounted) setState(() => generatingReturnOtp = false);
  }

  /// The "COLLECT PAYMENT" pop-up — shown once the customer has confirmed
  /// the return OTP on a Cash on Pickup booking with no delivery partner
  /// (see _buildReturnOtpBox's isCod branch below). Confirming here is
  /// what finally flips booking_status to 'Delivered', closing the
  /// booking out — notify-on-db-change/index.ts's justDelivered case
  /// notifies the customer once this write lands.
  Future<void> _confirmPaymentReceived() async {
    final price = widget.booking['package_price']?.toString();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text(
          'COLLECT PAYMENT',
          style: TextStyle(color: Color(0xFFD4A017), fontWeight: FontWeight.w900),
        ),
        content: Text(
          'This is a Cash on Pickup booking${price != null ? ' — $price' : ''}. '
          'Confirm you have collected payment from the customer before closing this booking out.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4A017)),
            child: const Text(
              'PAYMENT RECEIVED',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => confirmingPayment = true);

    try {
      await Supabase.instance.client
          .from('bookings')
          .update({'booking_status': 'Delivered'})
          .eq('id', widget.booking['id']);

      if (!mounted) return;
      widget.booking['booking_status'] = 'Delivered';

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment confirmed — booking closed out')),
      );
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not confirm payment. Please try again.',
      );
    }

    if (mounted) setState(() => confirmingPayment = false);
  }

  /// Generates a drop-off code for a no-pickup-drop booking — the customer
  /// is driving themselves to the garage, so this is the garage-side half
  /// of the same OTP exchange a delivery partner would otherwise do from
  /// web/deliverydashboard.html at pickup. Reuses the pickup_otp_* columns,
  /// which otherwise sit unused for a booking with no delivery trip.
  Future<void> _generatePickupOtpNow() async {
    setState(() => generatingPickupOtp = true);

    try {
      final code = (1000 + math.Random().nextInt(9000)).toString();
      final nowIso = DateTime.now().toIso8601String();

      await Supabase.instance.client
          .from('bookings')
          .update({'pickup_otp_code': code, 'pickup_otp_generated_at': nowIso})
          .eq('id', widget.booking['id']);

      if (!mounted) return;
      widget.booking['pickup_otp_code'] = code;
      widget.booking['pickup_otp_generated_at'] = nowIso;
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not generate the drop-off code. Please try again.',
      );
    }

    if (mounted) setState(() => generatingPickupOtp = false);
  }

  /// Re-pulls just the verification timestamp so the drop-off box below can
  /// flip to its "customer checked in" state without leaving this screen —
  /// mirrors _refreshReturnOtpStatus for the return leg.
  Future<void> _refreshPickupOtpStatus() async {
    setState(() => checkingPickupOtp = true);

    try {
      final row = await Supabase.instance.client
          .from('bookings')
          .select('pickup_otp_verified_at')
          .eq('id', widget.booking['id'])
          .single();

      if (!mounted) return;
      widget.booking['pickup_otp_verified_at'] = row['pickup_otp_verified_at'];
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not check the drop-off confirmation status. Please try again.',
      );
    }

    if (mounted) setState(() => checkingPickupOtp = false);
  }

  /// Shown for a no-pickup-drop booking, above the stage dropdown — lets
  /// staff generate a drop-off code and confirm the customer checked in
  /// with their vehicle before any service work is logged. Mirrors
  /// _buildReturnOtpBox's code-display/waiting/verified states.
  Widget _buildDropOffOtpBox() {
    final verified = widget.booking['pickup_otp_verified_at'] != null;
    final code = widget.booking['pickup_otp_code'] as String?;

    if (verified) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.12),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.green.withOpacity(0.4)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 22),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'VEHICLE CHECKED IN',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (code == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFD4A017).withOpacity(0.4)),
        ),
        child: Column(
          children: [
            const Text(
              'Customer at the counter? Generate a code and read it to them before checking their vehicle in.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: generatingPickupOtp ? null : _generatePickupOtpNow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4A017),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: generatingPickupOtp
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'GENERATE DROP-OFF CODE',
                          maxLines: 1,
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.6),
                        ),
                      ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFD4A017).withOpacity(0.4)),
      ),
      child: Column(
        children: [
          const Text(
            'Read this code to the customer before checking their vehicle in:',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          Text(
            code,
            style: const TextStyle(
              color: Color(0xFFD4A017),
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: 10,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Waiting for the customer to enter it in their app…',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: checkingPickupOtp ? null : _refreshPickupOtpStatus,
            child: checkingPickupOtp
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFFD4A017)),
                  )
                : const Text(
                    'CHECK AGAIN',
                    style: TextStyle(
                      color: Color(0xFFD4A017),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Shown in place of the plain "MARKED DONE" pill once this booking has
  /// no pickup/drop trip — displays the return code for staff to read to
  /// the customer, then a "customer confirmed" state once they've entered
  /// it correctly in their app.
  Widget _buildReturnOtpBox() {
    final verified = widget.booking['return_otp_verified_at'] != null;
    final code = widget.booking['return_otp_code'] as String?;

    if (verified) {
      final paymentDone = widget.booking['booking_status'] == 'Delivered';

      // Cash on Pickup and payment not yet confirmed — the booking isn't
      // actually finished (vehicle_bookings_screen.dart's
      // _ReturnOtpVerification deliberately withheld booking_status:
      // 'Delivered' for this exact case), so this is where staff collect
      // cash and close it out themselves instead of the usual pill.
      if (isCod && !paymentDone) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.12),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.orange.withOpacity(0.4)),
          ),
          child: Column(
            children: [
              const Icon(Icons.currency_rupee_rounded, color: Colors.orange, size: 28),
              const SizedBox(height: 8),
              const Text(
                'COLLECT PAYMENT',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Customer confirmed pickup — collect '
                '${widget.booking['package_price'] ?? 'the cash payment'} before closing this booking out.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: confirmingPayment ? null : _confirmPaymentReceived,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: confirmingPayment
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'PAYMENT RECEIVED',
                            maxLines: 1,
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.6),
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.12),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.green.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                isCod ? 'PAYMENT RECEIVED — BOOKING COMPLETE' : 'CUSTOMER CONFIRMED PICKUP',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (code == null) {
      // marked_done_at is set but no code was ever written — either this
      // booking was marked done before this feature shipped, or the first
      // generation attempt failed partway through. Either way, give staff
      // a way to generate one now instead of leaving them stuck.
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFD4A017).withOpacity(0.4)),
        ),
        child: Column(
          children: [
            const Text(
              'No return code has been generated for this booking yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: generatingReturnOtp ? null : _generateReturnOtpNow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4A017),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: generatingReturnOtp
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'GENERATE RETURN CODE',
                          maxLines: 1,
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.6),
                        ),
                      ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFD4A017).withOpacity(0.4)),
      ),
      child: Column(
        children: [
          const Text(
            'Read this code to the customer before handing over the vehicle:',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          Text(
            code,
            style: const TextStyle(
              color: Color(0xFFD4A017),
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: 10,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Waiting for the customer to enter it in their app…',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: checkingReturnOtp ? null : _refreshReturnOtpStatus,
            child: checkingReturnOtp
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFFD4A017)),
                  )
                : const Text(
                    'CHECK AGAIN',
                    style: TextStyle(
                      color: Color(0xFFD4A017),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  Simple "one next step" layout
  // ════════════════════════════════════════════════════════════════════

  static const Color _gold = Color(0xFFD4A017);
  static const Color _card = Color(0xFF1C1C1C);
  static const Color _bg = Color(0xFF141414);
  static const Color _green = Color(0xFF2FB36A);

  String get _status => (widget.booking['booking_status'] ?? '').toString();
  bool get _markedDone => widget.booking['marked_done_at'] != null;
  bool get _delivered => _status == 'Delivered';
  bool get _droppedOff => widget.booking['pickup_otp_verified_at'] != null;

  /// Customer-friendly progress steps shown at the top.
  static const List<String> _trackerSteps = ['Checked in', 'Inspected', 'Servicing', 'Billing', 'Ready'];

  /// How many tracker steps are finished (0–5).
  int get _doneSteps {
    if (_delivered) return 5;
    if (_markedDone || _status == 'Ready for Pickup') return 4;
    switch (_status) {
      case 'Billing Process':
        return 3;
      case 'Service In Progress':
      case 'Inspection Completed':
        return 2;
      case 'Inspection In Progress':
      case 'Car Picked Up':
        return 1;
    }
    // Not started: a self drop-off counts as checked in once the code is confirmed.
    return (!hasPickupDrop && _droppedOff) ? 1 : 0;
  }

  /// The stage the next update should move the booking to.
  String? get _suggestedStage {
    final i = stages.indexOf(_status);
    if (i < 0) return 'Car Picked Up';
    if (i + 1 >= stages.length - 1) return null; // after Billing → mark done
    return stages[i + 1];
  }

  String get _statusPill {
    if (_delivered) return 'COMPLETED';
    if (_markedDone || _status == 'Ready for Pickup') return 'READY';
    if (_status.isEmpty || _status.toLowerCase() == 'pending') {
      return hasPickupDrop ? 'NEW' : (_droppedOff ? 'CHECKED IN' : 'WAITING FOR CAR');
    }
    return 'IN GARAGE';
  }

  Future<void> _loadUpdates() async {
    try {
      final rows = await Supabase.instance.client
          .from('booking_updates')
          .select('stage, description, image_url, created_at')
          .eq('booking_id', widget.booking['id'])
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() => _updates = List<Map<String, dynamic>>.from(rows as List));
    } catch (_) {
      // Optional section — just stays empty.
    }
  }

  Future<String?> _signedPhoto(String? stored) async {
    if (stored == null || stored.isEmpty) return null;
    final path = stored.contains('/booking-images/') ? stored.split('/booking-images/').last : stored;
    try {
      return await Supabase.instance.client.storage.from('booking-images').createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  void _openInspection(String type) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InspectionUploadScreen(booking: widget.booking, type: type)),
    );
  }

  Future<void> _pickInspection() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _sheet(
        title: 'Which inspection?',
        children: [
          _sheetOption(ctx, Icons.directions_car_rounded, 'Pickup inspection', 'When the car arrives', 'pickup'),
          _sheetOption(ctx, Icons.local_shipping_rounded, 'Delivery inspection', 'Before the car goes back', 'delivery'),
        ],
      ),
    );
    if (type != null && mounted) _openInspection(type);
  }

  Future<void> _pickStage() async {
    final stage = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _sheet(
        title: 'Send an update for…',
        children: [
          for (final st in stages.where((x) => x != 'Delivered'))
            _sheetOption(ctx, st == _status ? Icons.radio_button_checked : Icons.radio_button_unchecked, st,
                st == _status ? 'Current stage' : null, st),
        ],
      ),
    );
    if (stage != null && mounted) setState(() => _stageOverride = stage);
  }

  Future<void> _confirmMarkDone() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Work finished?', style: TextStyle(color: _gold, fontWeight: FontWeight.w900)),
        content: Text(
          hasPickupDrop
              ? 'The customer and the delivery partner will be told the car is ready.'
              : "The customer will be told the car is ready, and you'll get a code to read them when they collect it.",
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('NOT YET', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('YES, WORK DONE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
    if (ok == true) await _markAsDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Booking', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: RefreshIndicator(
            color: _gold,
            onRefresh: () async {
              await _autoRefreshBooking();
              await _loadUpdates();
              await checkUnreadMessages();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              // Extra room at the bottom so the last buttons sit clear of
              // the gesture bar / screen edge.
              padding: EdgeInsets.fromLTRB(16, 8, 16, 96 + MediaQuery.viewPaddingOf(context).bottom),
              children: [
                _summaryCard(),
                const SizedBox(height: 14),
                // Blue "ADD-ON SERVICE" button + add-ons sent (not for roadside).
                GarageAddonsSection(booking: widget.booking),
                const SizedBox(height: 18),
                _tracker(),
                const SizedBox(height: 18),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(a),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(key: ValueKey('$_status|$_markedDone|$_droppedOff'), child: _nextStepCard()),
                ),
                const SizedBox(height: 22),
                _label('OTHER ACTIONS'),
                const SizedBox(height: 10),
                _actionsRow(),
                if (_updates.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _label('UPDATES SENT TO CUSTOMER'),
                  const SizedBox(height: 10),
                  _updatesList(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2));

  // ── 1. Summary ──────────────────────────────────────────────────────
  Widget _summaryCard() {
    final b = widget.booking;
    final name = (b['customer_name'] ?? '').toString();
    final price = (b['package_price'] ?? '').toString();
    final cod = isCod;
    final slotDate = (b['slot_date'] ?? '').toString();
    final slotTime = (b['slot_time'] ?? '').toString();
    final notes = (b['service_location_notes'] ?? '').toString();

    Widget chip(IconData icon, String text, {Color color = Colors.white70}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(text,
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((b['package_name'] ?? 'Service').toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, height: 1.2)),
                    if (price.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(price, style: const TextStyle(color: _gold, fontSize: 16, fontWeight: FontWeight.w800)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (_delivered ? _green : _gold).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_statusPill,
                    style: TextStyle(
                        color: _delivered ? _green : _gold, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (name.isNotEmpty) chip(Icons.person_rounded, name),
              if (slotDate.isNotEmpty) chip(Icons.schedule_rounded, slotTime.isEmpty ? slotDate : '$slotDate · $slotTime'),
              chip(hasPickupDrop ? Icons.local_shipping_rounded : Icons.storefront_rounded,
                  hasPickupDrop ? 'Pickup & drop' : 'Customer drops at garage'),
              chip(cod ? Icons.payments_rounded : Icons.verified_rounded, cod ? 'Collect cash' : 'Paid online',
                  color: cod ? Colors.orange : _green),
            ],
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(10)),
              child: Text('📝 $notes', style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4)),
            ),
          ],
        ],
      ),
    );
  }

  // ── 2. Progress tracker ─────────────────────────────────────────────
  Widget _tracker() {
    final done = _doneSteps;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _trackerSteps.length; i++)
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: Container(height: 2, color: i == 0 ? Colors.transparent : (i <= done ? _green : Colors.white12))),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < done ? _green : (i == done ? _gold : const Color(0xFF2A2A2A)),
                        boxShadow: i == done && done < 5 ? [BoxShadow(color: _gold.withOpacity(0.35), blurRadius: 10)] : null,
                      ),
                      alignment: Alignment.center,
                      child: i < done
                          ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                          : Text('${i + 1}',
                              style: TextStyle(
                                  color: i == done ? Colors.black : Colors.white54, fontSize: 12, fontWeight: FontWeight.w900)),
                    ),
                    Expanded(
                        child: Container(
                            height: 2,
                            color: i == _trackerSteps.length - 1 ? Colors.transparent : (i < done ? _green : Colors.white12))),
                  ],
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_trackerSteps[i],
                        maxLines: 1,
                        style: TextStyle(
                            color: i < done ? _green : (i == done ? _gold : Colors.white38),
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── 3. Next step ────────────────────────────────────────────────────
  Widget _nextStepCard() {
    // Finished.
    if (_delivered) {
      return _stepShell(
        color: _green,
        eyebrow: 'ALL DONE',
        title: 'Booking complete',
        body: 'The car is back with the customer. Nothing more to do here.',
        child: const SizedBox.shrink(),
      );
    }

    // Work marked done.
    if (_markedDone) {
      if (!hasPickupDrop) {
        return _stepShell(
          eyebrow: 'NEXT STEP',
          title: 'Hand over the car',
          body: 'When the customer comes to collect it, read them this code.',
          child: _buildReturnOtpBox(),
        );
      }
      return _stepShell(
        color: _green,
        eyebrow: 'WORK DONE',
        title: 'Waiting for the delivery partner',
        body: 'The customer has been told. The delivery partner will take the car back.',
        child: const SizedBox.shrink(),
      );
    }

    // Customer is driving in themselves and hasn't checked in yet.
    final notStarted = _status.isEmpty || _status.toLowerCase() == 'pending';
    if (!hasPickupDrop && !_droppedOff && notStarted && _stageOverride == null) {
      return _stepShell(
        eyebrow: 'NEXT STEP',
        title: 'Check in the car',
        body: 'When the customer arrives, give them this code to confirm the drop-off.',
        child: _buildDropOffOtpBox(),
      );
    }

    final suggested = _suggestedStage;
    // After billing → work done.
    if (suggested == null && _stageOverride == null) {
      return _stepShell(
        eyebrow: 'NEXT STEP',
        title: 'Mark the work as done',
        body: 'Finished servicing and billing? Let the customer know the car is ready.',
        child: _bigButton(
          label: 'WORK DONE — NOTIFY CUSTOMER',
          color: _green,
          fg: Colors.white,
          busy: markingDone,
          onTap: _confirmMarkDone,
        ),
      );
    }

    // Send a stage update with a photo.
    final stage = _stageOverride ?? suggested!;
    if (selectedStage != stage) selectedStage = stage;
    return _stepShell(
      eyebrow: _stageOverride != null ? 'SEND UPDATE' : 'NEXT STEP',
      title: stage,
      body: 'Take a photo and send it. The customer sees it in their app right away.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: pickImage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: selectedImageBytes == null ? 110 : 190,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _gold.withOpacity(0.5), width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: selectedImageBytes == null
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_camera_rounded, color: _gold, size: 32),
                        SizedBox(height: 6),
                        Text('Tap to take photo', style: TextStyle(color: _gold, fontWeight: FontWeight.w800)),
                      ],
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(selectedImageBytes!, fit: BoxFit.cover),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                            child: const Text('Retake', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: descController,
            maxLines: 2,
            minLines: 1,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Short note for the customer (optional)',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.black.withOpacity(0.25),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          _bigButton(label: 'SEND UPDATE', busy: loading, onTap: uploadUpdate),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: TextButton(
                  onPressed: _pickStage,
                  child: const Text('Different stage?', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700)),
                ),
              ),
              if (_stageOverride != null)
                Flexible(
                  child: TextButton(
                    onPressed: () => setState(() => _stageOverride = null),
                    child: const Text('Back to suggested', style: TextStyle(color: _gold, fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepShell({
    Color color = _gold,
    required String eyebrow,
    required String title,
    required String body,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.16), _card],
        ),
        border: Border.all(color: color.withOpacity(0.55), width: 1.5),
        boxShadow: [BoxShadow(color: color.withOpacity(0.10), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(eyebrow, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900, height: 1.2)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _bigButton({
    required String label,
    required bool busy,
    required VoidCallback onTap,
    Color color = _gold,
    Color fg = Colors.black,
  }) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: busy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withOpacity(0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: busy
            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    maxLines: 1, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5)),
              ),
      ),
    );
  }

  /// Reperi support line for garages.
  static const String _garageSupportPhone = '7022149521';

  Future<void> _callSupport() async {
    final uri = Uri.parse('tel:$_garageSupportPhone');
    try {
      if (!await launchUrl(uri)) throw 'no dialer';
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Call Reperi on $_garageSupportPhone')),
      );
    }
  }

  // ── 4. Other actions ────────────────────────────────────────────────
  Widget _actionsRow() {
    final tiles = <Widget>[
      _actionTile(Icons.call_rounded, 'Call Reperi', _callSupport),
      _actionTile(Icons.chat_bubble_rounded, 'Chat', openChat, badge: hasUnreadMessages),
      _actionTile(Icons.fact_check_rounded, 'Inspection', _pickInspection),
      if (!_markedDone && !_delivered) _actionTile(Icons.swap_vert_rounded, 'Any stage', _pickStage),
      if (!_markedDone && !_delivered) _actionTile(Icons.check_circle_rounded, 'Work done', _confirmMarkDone),
    ];
    // Up to 3 per row, so labels stay readable on small phones.
    Widget row(List<Widget> items) => Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: items[i]),
            ],
          ],
        );
    if (tiles.length <= 3) return row(tiles);
    final split = (tiles.length + 1) ~/ 2;
    return Column(
      children: [
        row(tiles.sublist(0, split)),
        const SizedBox(height: 10),
        row(tiles.sublist(split)),
      ],
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap, {bool badge = false}) {
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: _gold, size: 22),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label,
                        maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              if (badge)
                Positioned(
                  top: -4,
                  right: 6,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 5. Updates sent ─────────────────────────────────────────────────
  Widget _updatesList() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _updates.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Colors.white10),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: FutureBuilder<String?>(
                        future: _photoLinks.putIfAbsent(
                            '${_updates[i]['image_url']}', () => _signedPhoto(_updates[i]['image_url']?.toString())),
                        builder: (context, snap) => snap.data == null
                            ? Container(color: Colors.white10, child: const Icon(Icons.image_rounded, color: Colors.white24))
                            : Image.network(snap.data!, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(color: Colors.white10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((_updates[i]['stage'] ?? '').toString(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                        if ((_updates[i]['description'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(_updates[i]['description'].toString(),
                              style: const TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.3)),
                        ],
                        const SizedBox(height: 2),
                        Text(_when(_updates[i]['created_at']), style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _when(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return '';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${d.day} ${m[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  // ── Bottom-sheet helpers ────────────────────────────────────────────
  Widget _sheet({required String title, required List<Widget> children}) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      decoration: const BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetOption(BuildContext ctx, IconData icon, String title, String? sub, String value) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      leading: Icon(icon, color: _gold),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      subtitle: sub == null ? null : Text(sub, style: const TextStyle(color: Colors.white54)),
      onTap: () => Navigator.pop(ctx, value),
    );
  }
}
