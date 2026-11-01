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
    // Empty assetPath = the home_content CMS row for this banner is set
    // offline. Render nothing (and nothing around it either — the parent
    // Padding/SizedBox stays, but a zero-size widget means no gap).
    if (assetPath.isEmpty) return const SizedBox.shrink();

    final image = assetPath.startsWith('http://') || assetPath.startsWith('https://')
        ? Image.network(
            assetPath,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => PlaceholderBox(
              label: Uri.tryParse(assetPath)?.pathSegments.last ?? 'banner',
              borderRadius: 0,
            ),
          )
        : Image.asset(
            assetPath,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => PlaceholderBox(
              label: assetPath.split('/').last,
              borderRadius: 0,
            ),
          );

    final banner = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(aspectRatio: aspectRatio, child: image),
    );

    if (onTap == null) return banner;
    return GestureDetector(onTap: onTap, child: banner);
  }
}
