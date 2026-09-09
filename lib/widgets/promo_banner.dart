import 'package:flutter/material.dart';

import 'placeholder_box.dart';

/// A single full-width promotional banner image with rounded corners.
class PromoBanner extends StatelessWidget {
  const PromoBanner({
    super.key,
    required this.assetPath,
    this.aspectRatio = 16 / 9,
    this.onTap,
  });

  final String assetPath;
  final double aspectRatio;

  /// When set, the whole banner becomes tappable — used to open the
  /// screen it's advertising.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final banner = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => PlaceholderBox(
            label: assetPath.split('/').last,
            borderRadius: 0,
          ),
        ),
      ),
    );

    if (onTap == null) return banner;
    return GestureDetector(onTap: onTap, child: banner);
  }
}
