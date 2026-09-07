import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'dot_indicator_row.dart';
import 'placeholder_box.dart';

/// A flat, non-3D horizontal-scroll row of banner images sitting below the
/// coverflow — two cards fully visible at a time, scroll for the rest.
/// Cards are 16:9 (matching the source images' native 1280x720 size) so
/// `BoxFit.cover` never has to crop them.
class ServiceBannerRow extends StatefulWidget {
  const ServiceBannerRow({
    super.key,
    required this.imagePaths,
    required this.onTap,
  });

  final List<String> imagePaths;
  final ValueChanged<int> onTap;

  @override
  State<ServiceBannerRow> createState() => _ServiceBannerRowState();
}

class _ServiceBannerRowState extends State<ServiceBannerRow> {
  final ScrollController _controller = ScrollController();
  int _page = 0;

  static const double _aspectRatio = 16 / 9;
  static const double _gap = 12;
  static const double _sidePadding = 18;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onScroll(double cardExtent) {
    final raw = (_controller.offset / cardExtent).round();
    final page = raw.clamp(0, widget.imagePaths.length - 1).toInt();
    if (page != _page) setState(() => _page = page);
  }

  @override
  Widget build(BuildContext context) {
    final cardWidth = (MediaQuery.of(context).size.width - _sidePadding * 2 - _gap) / 2;
    final cardHeight = cardWidth / _aspectRatio;
    final cardExtent = cardWidth + _gap;

    return Column(
      children: [
        SizedBox(
          height: cardHeight,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              _onScroll(cardExtent);
              return false;
            },
            child: ListView.builder(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
              itemCount: widget.imagePaths.length,
              itemBuilder: (context, i) {
                return Padding(
                  padding: EdgeInsets.only(
                    right: i == widget.imagePaths.length - 1 ? 0 : _gap,
                  ),
                  child: GestureDetector(
                    onTap: () => widget.onTap(i),
                    child: Container(
                      width: cardWidth,
                      height: cardHeight,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: AppColors.surfaceRaised,
                        border: Border.all(color: AppColors.line),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        widget.imagePaths[i],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => PlaceholderBox(
                          label: widget.imagePaths[i].split('/').last,
                          borderRadius: 0,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.imagePaths.length > 1) ...[
          const SizedBox(height: 10),
          DotIndicatorRow(count: widget.imagePaths.length, activeIndex: _page),
        ],
      ],
    );
  }
}
