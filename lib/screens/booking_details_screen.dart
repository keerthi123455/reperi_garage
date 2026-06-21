import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'booking_tracking_screen.dart'; // imports ChatSheet

class BookingDetailsScreen extends StatefulWidget {
  final Map booking;

  const BookingDetailsScreen({
    super.key,
    required this.booking,
  });

  @override
  State<BookingDetailsScreen> createState() => _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends State<BookingDetailsScreen> {
  final descController = TextEditingController();

  String selectedStage = 'Car Picked Up';
  File? selectedImage;
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
    setState(() => selectedImage = File(image.path));
  }

  Future<void> uploadUpdate() async {
    if (selectedImage == null) {
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
          .upload(fileName, selectedImage!);

      final imageUrl = supabase.storage
          .from('booking-images')
          .getPublicUrl(fileName);

      await supabase.from('booking_updates').insert({
        'booking_id': widget.booking['id'],
        'stage': selectedStage,
        'description': descController.text,
        'image_url': imageUrl,
      });

      await supabase
          .from('bookings')
          .update({'booking_status': selectedStage}).eq(
              'id', widget.booking['id']);

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
                    child: selectedImage == null
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
                            child: Image.file(
                              selectedImage!,
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