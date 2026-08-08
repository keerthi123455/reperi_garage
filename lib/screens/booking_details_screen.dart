import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'booking_tracking_screen.dart'; // imports ChatSheet

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.black,
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
                    color: const Color(0xFF111111),
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
                    color: const Color(0xFF111111),
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
                  dropdownColor: const Color(0xFF111111),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF111111),
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
                    fillColor: const Color(0xFF111111),
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
                      color: const Color(0xFF111111),
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

                // ── CHAT BUTTON ──
                GestureDetector(
                  onTap: openChat,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFF111111),
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