import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InspectionUploadScreen extends StatefulWidget {
  final Map booking;
  final String type; // 'pickup' or 'delivery'

  const InspectionUploadScreen({
    super.key,
    required this.booking,
    required this.type,
  });

  @override
  State<InspectionUploadScreen> createState() =>
      _InspectionUploadScreenState();
}

class _InspectionUploadScreenState extends State<InspectionUploadScreen> {
  final descController = TextEditingController();
  final List<Uint8List> selectedImages = [];
  final List<String> imageNames = [];
  
  bool loading = false;
  int uploadProgress = 0;

  @override
  void dispose() {
    descController.dispose();
    super.dispose();
  }

  String get inspectionTitle {
    return widget.type == 'pickup' 
        ? 'Pickup Inspection Report' 
        : 'Delivery Inspection Report';
  }

  String get inspectionSubtitle {
    return widget.type == 'pickup'
        ? 'Document the car condition when received'
        : 'Document the car condition before delivery';
  }

  Future<void> pickImages() async {
    final picker = ImagePicker();
    
    // Check if we've already hit the limit
    if (selectedImages.length >= 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 30 photos allowed')),
      );
      return;
    }

    // Calculate how many more photos we can add
    final remaining = 30 - selectedImages.length;

    final images = await picker.pickMultiImage(
      imageQuality: 75,
      limit: remaining,
    );

    if (images.isEmpty) return;

    for (var image in images) {
      final bytes = await image.readAsBytes();
      setState(() {
        selectedImages.add(bytes);
        imageNames.add(image.name);
      });
    }
  }

  Future<void> pickSingleImage() async {
    final picker = ImagePicker();
    
    if (selectedImages.length >= 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 30 photos allowed')),
      );
      return;
    }

    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
    );

    if (image == null) return;
    
    final bytes = await image.readAsBytes();
    setState(() {
      selectedImages.add(bytes);
      imageNames.add(image.name);
    });
  }

  void removeImage(int index) {
    setState(() {
      selectedImages.removeAt(index);
      imageNames.removeAt(index);
    });
  }

  Future<void> uploadInspection() async {
    if (selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload at least 1 photo')),
      );
      return;
    }

    if (descController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a description')),
      );
      return;
    }

    setState(() => loading = true);
    uploadProgress = 0;

    try {
      final supabase = Supabase.instance.client;

      // Create inspection record with type field
      final inspectionData = await supabase
          .from('car_inspections')
          .insert({
            'booking_id': widget.booking['id'],
            'type': widget.type, // ← NEW: 'pickup' or 'delivery'
            'description': descController.text.trim(),
          })
          .select()
          .single();

      final inspectionId = inspectionData['id'];

      // Upload all images
      for (int i = 0; i < selectedImages.length; i++) {
        final fileName =
            'inspection_${widget.type}_${widget.booking['id']}_${DateTime.now().millisecondsSinceEpoch}_$i';

        await supabase.storage
            .from('inspection-images')
            .uploadBinary(fileName, selectedImages[i]);

        final imageUrl = supabase.storage
            .from('inspection-images')
            .getPublicUrl(fileName);

        // Save photo reference in DB
        await supabase.from('inspection_photos').insert({
          'inspection_id': inspectionId,
          'photo_url': imageUrl,
          'photo_order': i,
        });

        setState(() {
          uploadProgress = ((i + 1) / selectedImages.length * 100).toInt();
        });
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${inspectionTitle} uploaded successfully!'),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }

    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF262626),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1C),
        title: Text(
          inspectionTitle,
          style: const TextStyle(color: Color(0xFFD4A017)),
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
                // ── INSPECTION TYPE HEADER ──
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1C),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFD4A017).withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            widget.type == 'pickup'
                                ? Icons.directions_car_rounded
                                : Icons.local_shipping_rounded,
                            color: const Color(0xFFD4A017),
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  inspectionTitle,
                                  style: const TextStyle(
                                    color: Color(0xFFD4A017),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  inspectionSubtitle,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.booking['package_name'] ?? 'Inspection',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${widget.booking['vehicles']['car_number']}',
                        style: const TextStyle(
                          color: Color(0xFFD4A017),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── PHOTO COUNTER ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Upload Photos',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4A017).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFD4A017).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        '${selectedImages.length}/30',
                        style: const TextStyle(
                          color: Color(0xFFD4A017),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ── UPLOAD BUTTONS ──
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: loading ? null : pickImages,
                        child: Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: loading
                                ? Colors.grey.withOpacity(0.3)
                                : const Color(0xFFD4A017),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.image_rounded,
                                    color: Colors.black, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Gallery',
                                  style: TextStyle(
                                    color: loading
                                        ? Colors.white38
                                        : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: loading ? null : pickSingleImage,
                        child: Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: loading
                                ? Colors.grey.withOpacity(0.3)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFD4A017).withOpacity(0.5),
                            ),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.camera_alt_outlined,
                                    color: loading
                                        ? Colors.white38
                                        : const Color(0xFFD4A017)),
                                const SizedBox(width: 8),
                                Text(
                                  'Camera',
                                  style: TextStyle(
                                    color: loading
                                        ? Colors.white38
                                        : const Color(0xFFD4A017),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── PROGRESS INDICATOR ──
                if (loading)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Uploading...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '$uploadProgress%',
                            style: const TextStyle(
                              color: Color(0xFFD4A017),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: uploadProgress / 100,
                          minHeight: 6,
                          backgroundColor: const Color(0xFF333333),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFD4A017),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),

                // ── PHOTO GRID ──
                if (selectedImages.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selected Photos',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: selectedImages.length,
                        itemBuilder: (context, index) {
                          return Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  image: DecorationImage(
                                    image: MemoryImage(selectedImages[index]),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => removeImage(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),

                // ── DESCRIPTION SECTION ──
                const Text(
                  'Inspection Description',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 6,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: widget.type == 'pickup'
                        ? 'Describe the car condition upon pickup, any pre-existing damages, etc.'
                        : 'Describe the car condition after service completion, work done, etc.',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1C1C1C),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFF333333)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFF333333)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFFD4A017),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── SUBMIT BUTTON ──
                GestureDetector(
                  onTap: loading ? null : uploadInspection,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: loading
                          ? LinearGradient(
                              colors: [
                                Colors.grey.withOpacity(0.5),
                                Colors.grey.withOpacity(0.5),
                              ],
                            )
                          : const LinearGradient(
                              colors: [
                                Color(0xFFD4A017),
                                Color(0xFFF5C842),
                              ],
                            ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              'UPLOAD ${inspectionTitle.toUpperCase()}',
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}