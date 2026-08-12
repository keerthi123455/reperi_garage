import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InspectionViewWidget extends StatefulWidget {
  final String bookingId;

  const InspectionViewWidget({
    super.key,
    required this.bookingId,
  });

  @override
  State<InspectionViewWidget> createState() => _InspectionViewWidgetState();
}

class _InspectionViewWidgetState extends State<InspectionViewWidget> {
  Map? inspection;
  List<Map> inspectionPhotos = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchInspection();
  }

  Future<void> fetchInspection() async {
    final supabase = Supabase.instance.client;

    try {
      // Fetch inspection data
      final inspectionData = await supabase
          .from('car_inspections')
          .select()
          .eq('booking_id', widget.bookingId)
          .maybeSingle();

      if (inspectionData == null) {
        if (!mounted) return;
        setState(() => loading = false);
        return;
      }

      // Fetch inspection photos
      final photos = await supabase
          .from('inspection_photos')
          .select()
          .eq('inspection_id', inspectionData['id'])
          .order('photo_order', ascending: true);

      if (!mounted) return;

      setState(() {
        inspection = inspectionData;
        inspectionPhotos = List<Map>.from(photos);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  void openFullscreenImage(String imageUrl, int index) {
    showDialog(
      context: context,
      builder: (_) => FullscreenImageGallery(
        imageUrl: imageUrl,
        allImages: inspectionPhotos.map((p) => p['photo_url'] as String).toList(),
        initialIndex: index,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFD4A017)),
      );
    }

    if (inspection == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
          child: Text(
            'No inspection data yet',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── DESCRIPTION SECTION ──
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFD4A017).withOpacity(0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.description_rounded,
                    color: Color(0xFFD4A017),
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Inspection Notes',
                    style: TextStyle(
                      color: Color(0xFFD4A017),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                inspection!['description'] ?? '',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── PHOTOS SECTION ──
        if (inspectionPhotos.isNotEmpty) ...[
          Row(
            children: [
              const Icon(
                Icons.photo_library_rounded,
                color: Color(0xFFD4A017),
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'Inspection Photos (${inspectionPhotos.length})',
                style: const TextStyle(
                  color: Color(0xFFD4A017),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: inspectionPhotos.length,
            itemBuilder: (context, index) {
              final photo = inspectionPhotos[index];
              return GestureDetector(
                onTap: () =>
                    openFullscreenImage(photo['photo_url'], index),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0xFF1A1A1A),
                    border: Border.all(
                      color: const Color(0xFF2A2A2A),
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          photo['photo_url'],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: const Color(0xFF111111),
                              child: const Icon(
                                Icons.broken_image_rounded,
                                color: Colors.white38,
                              ),
                            );
                          },
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4A017)
                                .withOpacity(0.9),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(8),
                            ),
                          ),
                          child: const Icon(
                            Icons.zoom_in_rounded,
                            color: Colors.black,
                            size: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

// ── FULLSCREEN IMAGE GALLERY ──
class FullscreenImageGallery extends StatefulWidget {
  final String imageUrl;
  final List<String> allImages;
  final int initialIndex;

  const FullscreenImageGallery({
    super.key,
    required this.imageUrl,
    required this.allImages,
    required this.initialIndex,
  });

  @override
  State<FullscreenImageGallery> createState() =>
      _FullscreenImageGalleryState();
}

class _FullscreenImageGalleryState extends State<FullscreenImageGallery> {
  late PageController pageController;
  late int currentIndex;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(0),
      child: Column(
        children: [
          // ── TOP BAR ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Photo ${currentIndex + 1} of ${widget.allImages.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                GestureDetector(
                  onTap: Navigator.of(context).pop,
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
          // ── IMAGE VIEWER ──
          Expanded(
            child: PageView.builder(
              controller: pageController,
              onPageChanged: (index) {
                setState(() => currentIndex = index);
              },
              itemCount: widget.allImages.length,
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  child: Image.network(
                    widget.allImages[index],
                    fit: BoxFit.contain,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
