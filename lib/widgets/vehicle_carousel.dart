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
  // Only updated once scrolling actually settles on a real vehicle card
  // (see _snapToNearest) — drives VehicleCard.isActive, so the glow/pop
  // lands on the card that's truly centered, not wherever a fast fling
  // happens to be mid-flight. _page above still tracks live for the dot
  // row, which is fine flickering through intermediate values.
  int _settledPage = 0;
  bool _isSnapping = false;

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
    // Only the dot row (a purely visual, already-continuous indicator)
    // tracks this live value — widget.onPageChanged fires from
    // _snapToNearest's settle() instead, once scrolling actually stops, so
    // "the active vehicle for booking" doesn't flicker mid-drag and always
    // matches whichever card is showing the settled glow.
    if (page != _page) {
      setState(() => _page = page);
    }
  }

  /// Called once a scroll gesture (drag release or fling) actually stops —
  /// snaps the nearest card fully into view, then marks it as the settled
  /// "active" vehicle. Guarded by [_isSnapping] so the corrective
  /// [ScrollController.animateTo] call below doesn't re-trigger itself via
  /// the ScrollEndNotification it generates on completion.
  void _snapToNearest(double cardExtent) {
    if (_isSnapping || !_controller.hasClients) return;

    final itemCount = widget.vehicles.length + 1; // + the trailing "+" tile
    final raw = (_controller.offset / cardExtent).round();
    final target = raw.clamp(0, itemCount - 1);
    final targetOffset = (target * cardExtent).clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );

    void settle() {
      // The trailing "+" tile has no "active vehicle" of its own — leave
      // whichever real vehicle was last settled as still active while
      // it's centered.
      if (target < widget.vehicles.length && _settledPage != target) {
        setState(() => _settledPage = target);
        widget.onPageChanged?.call(target);
      }
    }

    if ((targetOffset - _controller.offset).abs() < 0.5) {
      settle();
      return;
    }

    _isSnapping = true;
    _controller
        .animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        )
        .then((_) {
      _isSnapping = false;
      settle();
    });
  }

  static const double _tileHeight = 158;

  @override
  Widget build(BuildContext context) {
    final isEmpty = widget.vehicles.isEmpty;
    // The trailing "+" tile means there's always at least one more item
    // after any vehicle card, so the peek amount always applies.
    final fullCardWidth = MediaQuery.of(context).size.width - _sidePadding * 2 - _peek;
    // With zero vehicles, the "+" tile is the only thing on screen here —
    // showing it at full vehicle-card size made it dominate the layout.
    // Half-size still reads clearly as "tap to add" without hogging the
    // space a real vehicle card would otherwise take. Once a vehicle
    // exists and this becomes the trailing tile after it, it goes back
    // to full size to match the cards next to it.
    final cardWidth = isEmpty ? fullCardWidth * 0.5 : fullCardWidth;
    final cardExtent = cardWidth + _gap;
    final itemCount = widget.vehicles.length + 1;
    final tileHeight = isEmpty ? _tileHeight * 0.5 : _tileHeight;

    return Column(
      children: [
        SizedBox(
          height: tileHeight,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollEndNotification) {
                _snapToNearest(cardExtent);
              } else {
                _onScroll(cardExtent);
              }
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
                      ? _AddVehicleTile(width: cardWidth, compact: isEmpty, onTap: widget.onAddVehicle)
                      : VehicleCard(
                          vehicle: widget.vehicles[i],
                          width: cardWidth,
                          isActive: i == _settledPage,
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
  const _AddVehicleTile({required this.width, required this.onTap, this.compact = false});

  final double width;
  final VoidCallback onTap;

  /// True in the zero-vehicle empty state, where this tile is the only
  /// thing shown and sized down — scales the icon/text down to match
  /// instead of leaving full-size content crammed into a smaller box.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconBoxSize = compact ? 32.0 : 44.0;
    final iconSize = compact ? 18.0 : 24.0;
    final labelSize = compact ? 11.0 : 13.0;
    final spacing = compact ? 6.0 : 10.0;
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
                width: iconBoxSize,
                height: iconBoxSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withOpacity(0.12),
                ),
                child: Icon(Symbols.add, color: AppColors.accent, size: iconSize, weight: 700),
              ),
              SizedBox(height: spacing),
              Text(
                'Add Vehicle',
                style: GoogleFonts.manrope(
                  fontSize: labelSize,
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
