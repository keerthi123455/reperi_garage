import 'package:flutter/material.dart';

import 'placeholder_box.dart';

/// A single full-width promotional banner image with rounded corners.
class PromoBanner extends StatelessWidget {
  const PromoBanner({
    super.key,
    required this.assetPath,
    this.aspectRatio = 16 / 9,
  });

  final String assetPath;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
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
  }
}
