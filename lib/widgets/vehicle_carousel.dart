import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import 'dot_indicator_row.dart';
import 'vehicle_card.dart';

class VehicleCarousel extends StatefulWidget {
  const VehicleCarousel({
    super.key,
    required this.vehicles,
    required this.onTap,
    required this.onPhotoTap,
    required this.onAddVehicle,
    this.onPageChanged,
  });

  final List<Vehicle> vehicles;
  final ValueChanged<Vehicle> onTap;
  final ValueChanged<Vehicle> onPhotoTap;

  /// Opens the add-vehicle flow — bound to the "+" tile that always sits
  /// after the last vehicle, hinting that more vehicles can be added
  /// instead of just trailing off into empty space.
  final VoidCallback onAddVehicle;

  /// Reports which vehicle is currently centered/in view — that tile is
  /// the "active vehicle" for anything booked from elsewhere on the home
  /// screen (Book Service, Book Washing, the coverflow/2D banners, the
  /// drawer, ...), not just whichever one happens to be first.
  final ValueChanged<int>? onPageChanged;

  @override
  State<VehicleCarousel> createState() => _VehicleCarouselState();
}

class _VehicleCarouselState extends State<VehicleCarousel> {
  final ScrollController _controller = ScrollController();
  int _page = 0;

  static const double _gap = 14;
  static const double _sidePadding = 18;
  // How much of the next card peeks in from the right, hinting that the
  // tile is scrollable.
  static const double _peek = 28;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onScroll(double cardExtent) {
    final raw = (_controller.offset / cardExtent).round();
    final page = raw.clamp(0, widget.vehicles.length - 1).toInt();
    if (page != _page) {
      setState(() => _page = page);
      widget.onPageChanged?.call(page);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The trailing "+" tile means there's always at least one more item
    // after any vehicle card, so the peek amount always applies.
    final cardWidth = MediaQuery.of(context).size.width - _sidePadding * 2 - _peek;
    final cardExtent = cardWidth + _gap;
    final itemCount = widget.vehicles.length + 1;

    return Column(
      children: [
        SizedBox(
          height: 158,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              _onScroll(cardExtent);
              return false;
            },
            child: ListView.builder(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
              itemCount: itemCount,
              itemBuilder: (context, i) {
                final isLast = i == itemCount - 1;
                return Padding(
                  padding: EdgeInsets.only(right: isLast ? 0 : _gap),
                  child: i == widget.vehicles.length
                      ? _AddVehicleTile(width: cardWidth, onTap: widget.onAddVehicle)
                      : VehicleCard(
                          vehicle: widget.vehicles[i],
                          width: cardWidth,
                          onTap: () => widget.onTap(widget.vehicles[i]),
                          onPhotoTap: () => widget.onPhotoTap(widget.vehicles[i]),
                        ),
                );
              },
            ),
          ),
        ),
        if (widget.vehicles.length > 1) ...[
          const SizedBox(height: 8),
          DotIndicatorRow(count: widget.vehicles.length, activeIndex: _page),
        ] else
          const SizedBox(height: 8),
      ],
    );
  }
}

/// The "+" tile that always trails the last vehicle card — a standing hint
/// that another vehicle can be added, instead of the carousel just ending
/// in empty space.
class _AddVehicleTile extends StatelessWidget {
  const _AddVehicleTile({required this.width, required this.onTap});

  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
          color: AppColors.surfaceRaised,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withOpacity(0.12),
                ),
                child: Icon(Symbols.add, color: AppColors.accent, size: 24, weight: 700),
              ),
              const SizedBox(height: 10),
              Text(
                'Add Vehicle',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.mut,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
