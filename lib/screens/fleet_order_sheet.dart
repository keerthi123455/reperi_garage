import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FleetOrderSheet extends StatefulWidget {
  final Map<String, dynamic> fleetUser;

  const FleetOrderSheet({
    super.key,
    required this.fleetUser,
  });

  @override
  State<FleetOrderSheet> createState() =>
      _FleetOrderSheetState();
}

class _FleetOrderSheetState
    extends State<FleetOrderSheet> {

  final _vehicleModelController =
      TextEditingController();

  final _carNumberController =
      TextEditingController();

  // ── Web-safe image state ──
  // dart:io File does NOT work on Flutter Web.
  // We store raw bytes instead, which works on every platform.
  Uint8List? _imageBytes;

  bool _loading = false;

  final _picker = ImagePicker();

  Future<void> _pickImage() async {
    final source = await _showImageSourceSheet();
    if (source == null) return;

    // Note: on web, ImageSource.camera opens the browser's webcam capture
    // UI if a camera is available and permission is granted — it does NOT
    // crash, but it may not be available on desktop browsers without a
    // webcam. ImageSource.gallery always works everywhere as a fallback.
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 70,
    );

    if (picked == null) return;

    // readAsBytes() works identically on web, mobile, and desktop.
    final bytes = await picked.readAsBytes();

    setState(() {
      _imageBytes = bytes;
    });
  }

  Future<ImageSource?> _showImageSourceSheet() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Add Vehicle Photo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded,
                    color: Color(0xFFD4A017)),
                title: const Text('Take Photo',
                    style: TextStyle(color: Colors.white)),
                onTap: () =>
                    Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded,
                    color: Color(0xFFD4A017)),
                title: const Text('Choose from Gallery',
                    style: TextStyle(color: Colors.white)),
                onTap: () =>
                    Navigator.pop(sheetContext, ImageSource.gallery),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submit() async {

    if (_vehicleModelController.text.isEmpty ||
        _carNumberController.text.isEmpty ||
        _imageBytes == null) {

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill all fields',
          ),
        ),
      );

      return;
    }

    setState(() {
      _loading = true;
    });

    try {

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}.jpg';

      // uploadBinary works with raw bytes on every platform,
      // unlike upload() which expects a dart:io File (web-incompatible).
      await Supabase.instance.client.storage
          .from('booking-images')
          .uploadBinary(
            'fleet/$fileName',
            _imageBytes!,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
            ),
          );

      final imageUrl =
          Supabase.instance.client.storage
              .from('booking-images')
              .getPublicUrl(
                'fleet/$fileName',
              );

      await Supabase.instance.client
          .from('fleet_pickup_requests')
          .insert({

        'fleet_user_id':
            widget.fleetUser['id'],

        'company_name':
            widget.fleetUser['company_name'],

        'username':
            widget.fleetUser['username'],

        'vehicle_model':
            _vehicleModelController.text.trim(),

        'car_number':
            _carNumberController.text.trim(),

        'vehicle_photo_url':
            imageUrl,

        'status':
            'Pending',
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Pickup request submitted'),
        ),
      );

      Navigator.pop(context);

    } catch (e) {

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
        ),
      );

    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: const Color(0xFF111111),

      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text(
          'Fleet Pickup Request',
        ),
      ),

      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),

            child: Column(
              children: [

                TextField(
                  controller:
                      _vehicleModelController,
                  style:
                      const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Vehicle Model',
                    labelStyle:
                        TextStyle(color: Colors.white),
                  ),
                ),

                const SizedBox(height: 20),

                TextField(
                  controller:
                      _carNumberController,
                  style:
                      const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Car Number',
                    labelStyle:
                        TextStyle(color: Colors.white),
                  ),
                ),

                const SizedBox(height: 25),

                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 220,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFFD4A017),
                      ),
                    ),
                    child: _imageBytes == null
                        ? const Center(
                            child: Text(
                              'Click To Upload Vehicle Photo',
                              style: TextStyle(
                                color: Colors.white,
                              ),
                            ),
                          )
                        : ClipRRect(
                            borderRadius:
                                BorderRadius.circular(18),
                            child: Image.memory(
                              _imageBytes!,
                              fit: BoxFit.cover,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFFD4A017),
                    ),
                    onPressed:
                        _loading ? null : _submit,
                    child: _loading
                        ? const CircularProgressIndicator(
                            color: Colors.black,
                          )
                        : const Text(
                            'REQUEST PICKUP',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight:
                                  FontWeight.w900,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}