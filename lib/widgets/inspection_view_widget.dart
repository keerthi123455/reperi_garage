import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InspectionViewWidget extends StatefulWidget {
  final String bookingId;
  final bool showBothTypes;

  const InspectionViewWidget({
    super.key,
    required this.bookingId,
    this.showBothTypes = true,
  });

  @override
  State<InspectionViewWidget> createState() => _InspectionViewWidgetState();
}

class _InspectionViewWidgetState extends State<InspectionViewWidget> {
  Map? pickupInspection;
  Map? deliveryInspection;
  List<Map> pickupPhotos = [];
  List<Map> deliveryPhotos = [];
  bool loading = true;

  // Collapse/expand states
  bool mainSectionExpanded = false;
  bool pickupExpanded = false;
  bool deliveryExpanded = false;

  @override
  void initState() {
    super.initState();
    fetchInspections();
  }

  Future<void> fetchInspections() async {
    final supabase = Supabase.instance.client;

    try {
      // Fetch pickup inspection
      final pickupData = await supabase
          .from('car_inspections')
          .select()
          .eq('booking_id', widget.bookingId)
          .eq('type', 'pickup')
          .maybeSingle();

      // Fetch delivery inspection
      final deliveryData = await supabase
          .from('car_inspections')
          .select()
          .eq('booking_id', widget.bookingId)
          .eq('type', 'delivery')
          .maybeSingle();

      List<Map> pickupPhotosList = [];
      List<Map> deliveryPhotosList = [];

      // Fetch pickup photos if inspection exists
      if (pickupData != null) {
        final photos = await supabase
            .from('inspection_photos')
            .select()
            .eq('inspection_id', pickupData['id'])
            .order('photo_order', ascending: true);
        pickupPhotosList = List<Map>.from(photos);
      }

      // Fetch delivery photos if inspection exists
      if (deliveryData != null) {
        final photos = await supabase
            .from('inspection_photos')
            .select()
            .eq('inspection_id', deliveryData['id'])
            .order('photo_order', ascending: true);
        deliveryPhotosList = List<Map>.from(photos);
      }

      if (!mounted) return;

      setState(() {
        pickupInspection = pickupData;
        deliveryInspection = deliveryData;
        pickupPhotos = pickupPhotosList;
        deliveryPhotos = deliveryPhotosList;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  void openFullscreenImage(String imageUrl, int index, List<Map> photos) {
    showDialog(
      context: context,
      builder: (_) => FullscreenImageGallery(
        imageUrl: imageUrl,
        allImages: photos.map((p) => p['photo_url'] as String).toList(),
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

    final hasPickup = pickupInspection != null;
    final hasDelivery = deliveryInspection != null;

    if (!hasPickup && !hasDelivery) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
          child: Text(
            'No inspection reports yet',
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
        // ── MAIN HEADER: VIEW INSPECTION REPORTS ──
        GestureDetector(
          onTap: () {
            setState(() {
              mainSectionExpanded = !mainSectionExpanded;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1C),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFD4A017).withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.document_scanner_rounded,
                      color: const Color(0xFFD4A017),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'View Inspection Reports',
                      style: TextStyle(
                        color: Color(0xFFD4A017),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Icon(
                  mainSectionExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: const Color(0xFFD4A017),
                  size: 24,
                ),
              ],
            ),
          ),
        ),

        // ── INSPECTION CONTENT (EXPANDED ONLY) ──
        if (mainSectionExpanded) ...[
          const SizedBox(height: 16),

        // ── AFTER PICKUP DROPDOWN ──
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  pickupExpanded = !pickupExpanded;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F0F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF2A2A2A),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.directions_car_rounded,
                          color: const Color(0xFFD4A017),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'After Pickup',
                          style: TextStyle(
                            color: Color(0xFFD4A017),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      pickupExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: const Color(0xFFD4A017),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

            // Pickup inspection content
            if (pickupExpanded)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: hasPickup
                    ? _buildInspectionSection(
                        pickupInspection!,
                        pickupPhotos,
                        'After Pickup Inspection',
                        Icons.directions_car_rounded,
                      )
                    : Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111111),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF2A2A2A),
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'No updates here',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
              ),

            const SizedBox(height: 12),
          ],
        ),

        // ── BEFORE DELIVERY DROPDOWN ──
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  deliveryExpanded = !deliveryExpanded;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F0F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF2A2A2A),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.local_shipping_rounded,
                          color: const Color(0xFFD4A017),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Before Delivery',
                          style: TextStyle(
                            color: Color(0xFFD4A017),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      deliveryExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: const Color(0xFFD4A017),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

            // Delivery inspection content
            if (deliveryExpanded)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: hasDelivery
                    ? _buildInspectionSection(
                        deliveryInspection!,
                        deliveryPhotos,
                        'Before Delivery Inspection',
                        Icons.local_shipping_rounded,
                      )
                    : Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111111),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF2A2A2A),
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'No updates here',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
              ),
          ],
        ),
        ],
      ],
    );
  }

  Widget _buildInspectionSection(
    Map inspection,
    List<Map> photos,
    String title,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFD4A017).withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── INSPECTION NOTES ──
          Row(
            children: [
              Icon(
                Icons.description_rounded,
                color: const Color(0xFFD4A017),
                size: 20,
              ),
              const SizedBox(width: 10),
              const Text(
                'Inspection Notes',
                style: TextStyle(
                  color: Color(0xFFD4A017),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            inspection['description'] ?? 'No notes added',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.6,
            ),
          ),

          const SizedBox(height: 20),

          // ── PHOTOS SECTION ──
          if (photos.isNotEmpty) ...[
            Row(
              children: [
                Icon(
                  Icons.photo_library_rounded,
                  color: const Color(0xFFD4A017),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  'Photos (${photos.length})',
                  style: const TextStyle(
                    color: Color(0xFFD4A017),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: photos.length,
              itemBuilder: (context, index) {
                final photo = photos[index];
                return GestureDetector(
                  onTap: () => openFullscreenImage(
                    photo['photo_url'],
                    index,
                    photos,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: const Color(0xFF1A1A1A),
                      border: Border.all(
                        color: const Color(0xFF2A2A2A),
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RepaintBoundary(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: photo['photo_url'],
                              fit: BoxFit.cover,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              useOldImageOnUrlChange: false,
                              placeholder: (context, url) => Container(
                                color: const Color(0xFF111111),
                                child: const Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      color: Color(0xFFD4A017),
                                      strokeWidth: 1,
                                    ),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) =>
                                  Container(
                                color: const Color(0xFF111111),
                                child: const Icon(
                                  Icons.broken_image_rounded,
                                  color: Colors.white38,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
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
                              size: 12,
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
      ),
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
                  child: RepaintBoundary(
                    child: CachedNetworkImage(
                      imageUrl: widget.allImages[index],
                      fit: BoxFit.contain,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      useOldImageOnUrlChange: false,
                      placeholder: (context, url) => Center(
                        child: CircularProgressIndicator(
                          color: const Color(0xFFD4A017),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.black,
                        child: const Icon(
                          Icons.broken_image_rounded,
                          color: Colors.white38,
                        ),
                      ),
                    ),
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