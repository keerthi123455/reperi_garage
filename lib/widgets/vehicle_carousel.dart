import 'package:flutter/material.dart';

import '../models/vehicle.dart';
import 'dot_indicator_row.dart';
import 'vehicle_card.dart';

class VehicleCarousel extends StatefulWidget {
  const VehicleCarousel({
    super.key,
    required this.vehicles,
    required this.onMore,
  });

  final List<Vehicle> vehicles;
  final VoidCallback onMore;

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
    if (page != _page) setState(() => _page = page);
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
          height: 132,
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
                    onMore: widget.onMore,
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
