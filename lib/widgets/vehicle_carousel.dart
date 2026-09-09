import 'package:flutter/material.dart';

import '../models/vehicle.dart';
import 'dot_indicator_row.dart';
import 'vehicle_card.dart';

class VehicleCarousel extends StatefulWidget {
  const VehicleCarousel({
    super.key,
    required this.vehicles,
    required this.onTap,
    required this.onPhotoTap,
    this.onPageChanged,
  });

  final List<Vehicle> vehicles;
  final ValueChanged<Vehicle> onTap;
  final ValueChanged<Vehicle> onPhotoTap;

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
    final cardWidth = widget.vehicles.length > 1
        ? MediaQuery.of(context).size.width - _sidePadding * 2 - _peek
        : MediaQuery.of(context).size.width - _sidePadding * 2;
    final cardExtent = cardWidth + _gap;

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
              itemCount: widget.vehicles.length,
              itemBuilder: (context, i) {
                return Padding(
                  padding: EdgeInsets.only(
                    right: i == widget.vehicles.length - 1 ? 0 : _gap,
                  ),
                  child: VehicleCard(
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
