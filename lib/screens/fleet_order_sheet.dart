import 'dart:io';

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

  File? _image;

  bool _loading = false;

  final _picker = ImagePicker();

  Future<void> _pickImage() async {

    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );

    if (picked == null) return;

    setState(() {
      _image = File(picked.path);
    });
  }

  Future<void> _submit() async {

    if (_vehicleModelController.text.isEmpty ||
        _carNumberController.text.isEmpty ||
        _image == null) {

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

      await Supabase.instance.client.storage
          .from('booking-images')
          .upload(
            'fleet/$fileName',
            _image!,
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
                    child: _image == null
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
                            child: Image.file(
                              _image!,
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