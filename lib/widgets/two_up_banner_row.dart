import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'placeholder_box.dart';

/// One tile of [TwoUpBannerRow].
class TwoUpBannerItem {
  const TwoUpBannerItem({required this.assetPath, this.onTap});

  final String assetPath;
  final VoidCallback? onTap;
}

/// A fixed 2-column, single-row pair of image tiles. Unlike
/// [ServiceBannerRow] this never scrolls — both tiles are always fully
/// visible, splitting the available width evenly. Styled to match that
/// row's cards (rounded, bordered, drop shadow).
class TwoUpBannerRow extends StatelessWidget {
  const TwoUpBannerRow({
    super.key,
    required this.left,
    required this.right,
    this.aspectRatio = 16 / 9,
    this.gap = 12,
  });

  final TwoUpBannerItem left;
  final TwoUpBannerItem right;
  final double aspectRatio;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _tile(left)),
        SizedBox(width: gap),
        Expanded(child: _tile(right)),
      ],
    );
  }

  Widget _tile(TwoUpBannerItem item) {
    final card = AspectRatio(
      aspectRatio: aspectRatio,
      child: Container(
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
          item.assetPath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => PlaceholderBox(
            label: item.assetPath.split('/').last,
            borderRadius: 0,
          ),
        ),
      ),
    );

    if (item.onTap == null) return card;
    return GestureDetector(onTap: item.onTap, child: card);
  }
}
