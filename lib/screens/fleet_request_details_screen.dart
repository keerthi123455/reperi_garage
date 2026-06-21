import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class FleetRequestDetailsScreen extends StatefulWidget {
  final Map fleetRequest;

  const FleetRequestDetailsScreen({
    super.key,
    required this.fleetRequest,
  });

  @override
  State<FleetRequestDetailsScreen> createState() =>
      _FleetRequestDetailsScreenState();
}

class _FleetRequestDetailsScreenState
    extends State<FleetRequestDetailsScreen> {
  late String _currentStatus;
  File? _adminImage;

  final _picker = ImagePicker();
  bool _updating = false;
  final _commentController = TextEditingController();

  final List<String> _statusOptions = [
    'Pending',
    'Picked Up',
    'In Garage',
    'Completed',
  ];

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.fleetRequest['status'] ?? 'Pending';
    Future.microtask(() async {
      await Supabase.instance.client
          .from('fleet_pickup_requests')
          .update({
            'has_unread_update': false,
          })
          .eq(
            'id',
            widget.fleetRequest['id'],
          );
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _updating = true);

    try {
      // Fetch existing status history before updating
      final currentRequest = await Supabase.instance.client
          .from('fleet_pickup_requests')
          .select()
          .eq('id', widget.fleetRequest['id'])
          .single();

      final existingStatusHistory =
          currentRequest['status_history'] ?? '';

      await Supabase.instance.client
          .from('fleet_pickup_requests')
          .update({
            'status': newStatus,
            'status_history': '$existingStatusHistory|$newStatus',
            'has_unread_update':false,
          })
          .eq('id', widget.fleetRequest['id']);

      if (!mounted) return;

      setState(() {
        _currentStatus = newStatus;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status updated to $newStatus'),
          backgroundColor: const Color(0xFFD4A017),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _saveComment() async {
    final comment = _commentController.text.trim();
    if (comment.isEmpty) return;

    setState(() => _updating = true);

    try {
      // Fetch existing comment history before updating
      final currentRequest = await Supabase.instance.client
          .from('fleet_pickup_requests')
          .select()
          .eq('id', widget.fleetRequest['id'])
          .single();

      final existingComments =
          currentRequest['comment_history'] ?? '';

      await Supabase.instance.client
          .from('fleet_pickup_requests')
          .update({
            'admin_comment': comment,
            'comment_history': '$existingComments|$comment',
            'has_unread_update': false,
          })
          .eq('id', widget.fleetRequest['id']);

      if (!mounted) return;

      _commentController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Comment saved'),
          backgroundColor: Color(0xFFD4A017),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _pickAdminImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );

    if (picked == null) return;

    setState(() {
      _adminImage = File(picked.path);
    });
  }

  Future<void> _uploadAdminPhoto() async {
    if (_adminImage == null) return;
    
    setState(() => _updating = true);

    try {
      final fileName =
          'garage_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await Supabase.instance.client.storage
          .from('booking-images')
          .upload(
            'garage/$fileName',
            _adminImage!,
          );

      final imageUrl =
          Supabase.instance.client.storage
              .from('booking-images')
              .getPublicUrl('garage/$fileName');

      // Fetch existing photo history before updating
      final currentRequest = await Supabase.instance.client
          .from('fleet_pickup_requests')
          .select()
          .eq('id', widget.fleetRequest['id'])
          .single();

      final existingHistory =
          currentRequest['photo_history'] ?? '';

      await Supabase.instance.client
          .from('fleet_pickup_requests')
          .update({
            'admin_photo_url': imageUrl,
            'photo_history': '$existingHistory|$imageUrl',
            'customer_approval': null,
            
          })
          .eq(
            'id',
            widget.fleetRequest['id'],
          );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Garage photo uploaded'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
        ),
      );
    }

    if (mounted) {
      setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fleet = widget.fleetRequest;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Color(0xFFD4A017)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'FLEET REQUEST',
          style: TextStyle(
            color: Color(0xFFD4A017),
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Info Card ──────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD4A017).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.local_shipping_rounded,
                              color: Color(0xFFD4A017),
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fleet['company_name'] ?? '',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  fleet['vehicle_model'] ?? '',
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _infoRow('Car Number', fleet['car_number'] ?? ''),
                      _infoRow('Driver Name', fleet['driver_name'] ?? ''),
                      _infoRow('Phone', fleet['phone'] ?? ''),
                      _infoRow('Pickup Address', fleet['pickup_address'] ?? ''),
                      const SizedBox(height: 20),

                      if (fleet['vehicle_photo_url'] != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'VEHICLE PHOTO UPLOADED BY FLEET',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(
                                fleet['vehicle_photo_url'],
                                height: 220,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 20),

                      const Text(
                        'CUSTOMER RESPONSE',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          fleet['customer_approval'] ??
                              'Awaiting Response',
                          style: TextStyle(
                            color:
                                fleet['customer_approval'] ==
                                        'Approved'
                                    ? Colors.green
                                    : fleet['customer_approval'] ==
                                            'Rejected'
                                        ? Colors.red
                                        : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── Status Update ──────────────────────────────────────
                const Text(
                  'UPDATE STATUS',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 14),

                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _statusOptions.map((status) {
                    final isSelected = _currentStatus == status;
                    return GestureDetector(
                      onTap: _updating ? null : () => _updateStatus(status),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFD4A017)
                              : const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFD4A017)
                                : const Color(0xFF2A2A2A),
                          ),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white54,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 32),

                // ── Admin Comment ──────────────────────────────────────
                const Text(
                  'ADMIN COMMENT',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 14),

                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: TextField(
                    controller: _commentController,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Add a comment or note…',
                      hintStyle: TextStyle(color: Color(0xFF444444)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4A017),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _updating ? null : _saveComment,
                    child: _updating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'SAVE COMMENT',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Garage Photo Upload ────────────────────────────────
                const Text(
                  'GARAGE PHOTO UPDATE',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),

                const SizedBox(height: 14),

                GestureDetector(
                  onTap: _pickAdminImage,
                  child: Container(
                    height: 220,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFF2A2A2A),
                      ),
                    ),
                    child: _adminImage == null
                        ? const Center(
                            child: Text(
                              'UPLOAD GARAGE PHOTO',
                              style: TextStyle(
                                color: Colors.white54,
                              ),
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.file(
                              _adminImage!,
                              fit: BoxFit.cover,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4A017),
                    ),
                    onPressed: _updating ? null : _uploadAdminPhoto,
                    child: const Text(
                      'UPLOAD PHOTO',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}