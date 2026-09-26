import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'booking_tracking_screen.dart'; // imports ChatSheet
import 'inspection_upload_screen.dart';
import '../utils/secure_storage_path.dart';
import '../widgets/error_display.dart';

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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update uploaded')),
      );

      Navigator.pop(context);
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
        height: 72,
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
            Text(
              'VEHICLE CHECKED IN',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
                fontSize: 15,
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
                    : const Text(
                        'GENERATE DROP-OFF CODE',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.6),
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
                      : const Text(
                          'PAYMENT RECEIVED',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.6),
                        ),
                ),
              ),
            ],
          ),
        );
      }

      return Container(
        height: 72,
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
            Text(
              isCod ? 'PAYMENT RECEIVED — BOOKING COMPLETE' : 'CUSTOMER CONFIRMED PICKUP',
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
                fontSize: 15,
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
                    : const Text(
                        'GENERATE RETURN CODE',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 0.6),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF262626),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text(
          'Update Booking',
          style: TextStyle(color: Color(0xFFD4A017)),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── BOOKING CARD ──
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1C),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.booking['package_name']?.toString() ?? 'Service',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.booking['package_price']?.toString() ?? '',
                        style: const TextStyle(
                          color: Color(0xFFD4A017),
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),
                // ── LOCATION INFORMATION ──
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1C),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: const Color(0xFFD4A017).withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── SECTION TITLE ──
                      const Row(
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            color: Color(0xFFD4A017),
                            size: 22,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Service Location',
                            style: TextStyle(
                              color: Color(0xFFD4A017),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 20),

                      // Pickup/dropoff address and GPS coordinates are
                      // deliberately not shown here — garage staff only get
                      // customer chat, not the customer's home address or
                      // phone number. A delivery partner (assigned
                      // separately) handles the actual pickup/drop-off
                      // logistics and sees that address on their own screen.

                      // ── CUSTOMER CONTACT ──
                      if (widget.booking['customer_name'] != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 18),
                            const Divider(
                              color: Colors.white12,
                              height: 1,
                            ),
                            const SizedBox(height: 18),
                            const Row(
                              children: [
                                Icon(
                                  Icons.person_rounded,
                                  color: Color(0xFFD4A017),
                                  size: 18,
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Customer Details',
                                  style: TextStyle(
                                    color: Color(0xFFD4A017),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (widget.booking['customer_name'] != null)
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Name:',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.booking['customer_name'] ?? '',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            // No phone number shown here — garage staff
                            // reach the customer through in-app chat only.
                          ],
                        ),
                      
                      // ── SERVICE NOTES (if any) ──
                      if (widget.booking['service_location_notes'] !=
                          null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 18),
                            const Text(
                              'Special Instructions:',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.1),
                                ),
                              ),
                              child: Text(
                                widget.booking['service_location_notes'] ??
                                    '',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── DROP-OFF OTP (no pickup/drop trip only) ──
                if (!hasPickupDrop) ...[
                  _buildDropOffOtpBox(),
                  const SizedBox(height: 28),
                ],

                // ── STAGE TITLE ──
                const Text(
                  'Update Stage',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 18),

                // ── DROPDOWN ──
                DropdownButtonFormField(
                  value: selectedStage,
                  dropdownColor: const Color(0xFF1C1C1C),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1C1C1C),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  items: stages.map((s) {
                    return DropdownMenuItem(value: s, child: Text(s));
                  }).toList(),
                  onChanged: (v) => setState(() => selectedStage = v!),
                ),

                const SizedBox(height: 28),

                // ── DESCRIPTION ──
                TextField(
                  controller: descController,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Add progress description',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1C1C1C),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── IMAGE PICKER ──
                GestureDetector(
                  onTap: pickImage,
                  child: Container(
                    height: 220,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1C),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: selectedImageBytes == null
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt,
                                  color: Color(0xFFD4A017), size: 46),
                              SizedBox(height: 16),
                              Text(
                                'Upload Service Photo',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.memory(
                              selectedImageBytes!,
                              fit: BoxFit.cover,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── PICKUP INSPECTION BUTTON ──
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InspectionUploadScreen(
                          booking: widget.booking,
                          type: 'pickup',
                        ),
                      ),
                    ).then((_) {
                      // Optionally refresh data after inspection upload
                    });
                  },
                  child: Container(
                    height: 68,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1C),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: const Color(0xFFD4A017).withOpacity(0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.directions_car_rounded,
                            color: Color(0xFFD4A017), size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'PICKUP INSPECTION',
                          style: TextStyle(
                            color: const Color(0xFFD4A017),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            fontSize: selectedStage == 'Car Picked Up' ? 15 : 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // ── DELIVERY INSPECTION BUTTON ──
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InspectionUploadScreen(
                          booking: widget.booking,
                          type: 'delivery',
                        ),
                      ),
                    ).then((_) {
                      // Optionally refresh data after inspection upload
                    });
                  },
                  child: Container(
                    height: 68,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1C),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: const Color(0xFFD4A017).withOpacity(0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.local_shipping_rounded,
                            color: Color(0xFFD4A017), size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'DELIVERY INSPECTION',
                          style: TextStyle(
                            color: const Color(0xFFD4A017),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            fontSize: selectedStage == 'Delivered' ? 15 : 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // ── UPLOAD BUTTON ──
                GestureDetector(
                  onTap: loading ? null : uploadUpdate,
                  child: Container(
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFD4A017), Color(0xFFF5C842)],
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Center(
                      child: loading
                          ? const CircularProgressIndicator(
                              color: Colors.black)
                          : const Text(
                              'UPLOAD UPDATE',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // ── MARK AS DONE BUTTON ──
                // Notifies the customer either way; also notifies the
                // assigned delivery partner, but only when this booking
                // actually has a pickup/drop trip for them to make.
                if (widget.booking['marked_done_at'] != null)
                  (!hasPickupDrop
                      ? _buildReturnOtpBox()
                      : Container(
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(28),
                            border:
                                Border.all(color: Colors.green.withOpacity(0.4)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  color: Colors.green, size: 22),
                              SizedBox(width: 10),
                              Text(
                                'MARKED DONE',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ))
                else
                  GestureDetector(
                    onTap: markingDone ? null : _markAsDone,
                    child: Container(
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.green.shade600.withOpacity(markingDone ? 0.6 : 1),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Center(
                        child: markingDone
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text(
                                'MARK AS DONE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                    ),
                  ),

                const SizedBox(height: 18),

                // ── CHAT BUTTON ──
                GestureDetector(
                  onTap: openChat,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1C),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: const Color(0xFFD4A017).withOpacity(0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded,
                                color: Color(0xFFD4A017), size: 22),
                            SizedBox(width: 10),
                            Text(
                              'CHAT WITH CLIENT',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hasUnreadMessages)
                        Positioned(
                          top: -6,
                          right: -6,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withOpacity(0.6),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}