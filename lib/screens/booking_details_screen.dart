import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'booking_tracking_screen.dart'; // imports ChatSheet
import 'inspection_upload_screen.dart';

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

  /// This 'bookings' row has no delivery-partner trip — the customer comes
  /// to collect the vehicle in person, so MARK AS DONE below is what
  /// generates the return code (rather than a delivery partner doing it
  /// from web/deliverydashboard.html at the out_for_delivery leg).
  bool get hasPickupDrop =>
      (widget.booking['pickupdrop'] ?? '').toString().toLowerCase() == 'yes';

  final stages = [
    'Car Picked Up',
    'Inspection In Progress',
    'Inspection Completed',
    'Service In Progress',
    'Billing Process',
    'Delivered',
  ];

  @override
  void initState() {
    super.initState();
    checkUnreadMessages();
    if (widget.autoOpenChat) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openChat());
    }
  }

  @override
  void dispose() {
    descController.dispose();
    super.dispose();
  }

  Future<void> checkUnreadMessages() async {
    final supabase = Supabase.instance.client;

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
          DateTime.now().millisecondsSinceEpoch.toString();

      await supabase.storage
          .from('booking-images')
          .uploadBinary(fileName, selectedImageBytes!);

      final imageUrl = supabase.storage
          .from('booking-images')
          .getPublicUrl(fileName);

      await supabase.from('booking_updates').insert({
        'booking_id': widget.booking['id'],
        'stage': selectedStage,
        'description': descController.text,
        'image_url': imageUrl,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }

    setState(() => loading = false);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not mark as done: $e')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not check status: $e')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate code: $e')),
      );
    }

    if (mounted) setState(() => generatingReturnOtp = false);
  }

  /// Shown in place of the plain "MARKED DONE" pill once this booking has
  /// no pickup/drop trip — displays the return code for staff to read to
  /// the customer, then a "customer confirmed" state once they've entered
  /// it correctly in their app.
  Widget _buildReturnOtpBox() {
    final verified = widget.booking['return_otp_verified_at'] != null;
    final code = widget.booking['return_otp_code'] as String?;

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
              'CUSTOMER CONFIRMED PICKUP',
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
                        widget.booking['package_name'],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.booking['package_price'],
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
                      
                      // ── PICKUP ADDRESS ──
                      const Text(
                        'Pickup Address:',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.booking['pickup_address'] ?? 'Not specified',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                        ),
                      ),
                      
                      // ── GPS COORDINATES ──
                      if (widget.booking['pickup_latitude'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.gps_fixed_rounded,
                                color: Color(0xFFD4A017),
                                size: 14,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${widget.booking['pickup_latitude']?.toStringAsFixed(4)}, ${widget.booking['pickup_longitude']?.toStringAsFixed(4)}',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      
                      // ── DROPOFF ADDRESS (if different) ──
                      if (widget.booking['dropoff_address'] != null &&
                          widget.booking['dropoff_address'] !=
                              widget.booking['pickup_address'])
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 18),
                            const Text(
                              'Dropoff Address:',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.booking['dropoff_address'] ??
                                  'Not specified',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                height: 1.5,
                              ),
                            ),
                            if (widget.booking['dropoff_latitude'] !=
                                null)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.gps_fixed_rounded,
                                      color: Color(0xFFD4A017),
                                      size: 14,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${widget.booking['dropoff_latitude']?.toStringAsFixed(4)}, ${widget.booking['dropoff_longitude']?.toStringAsFixed(4)}',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      
                      // ── CUSTOMER CONTACT ──
                      if (widget.booking['customer_name'] != null ||
                          widget.booking['customer_phone'] != null)
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
                            if (widget.booking['customer_phone'] != null)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 10),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Phone:',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    GestureDetector(
                                      onTap: () {
                                        // Optional: Launch dialer
                                        // final phone = widget.booking['customer_phone'];
                                        // launchUrl(Uri(scheme: 'tel', path: phone));
                                      },
                                      child: Text(
                                        widget.booking['customer_phone'] ??
                                            '',
                                        style: const TextStyle(
                                          color: Color(0xFFD4A017),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          decoration:
                                              TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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