import 'package:flutter/material.dart';

class NeumorphicCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;

  const NeumorphicCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(borderRadius),

        /// NEUMORPHIC SHADOWS
        boxShadow: [
          /// DARK SHADOW
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            offset: const Offset(8, 8),
            blurRadius: 20,
          ),

          /// LIGHT SHADOW
          const BoxShadow(
            color: Colors.white,
            offset: Offset(-8, -8),
            blurRadius: 20,
          ),
        ],
      ),
      child: child,
    );
  }
}