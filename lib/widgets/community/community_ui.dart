import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';
import '../reperi_logo.dart';

/// Shared look for the Community page (reels, Recent work, the viewer).

const Color kCommunityGold = Color(0xFFE3B23C);
const Color kCommunityGoldDeep = Color(0xFFD4A017);
const Color kCommunityPurple = Color(0xFF7B3FE4);

TextStyle communityText({
  double size = 14,
  FontWeight weight = FontWeight.w600,
  Color? color,
  double? height,
  double? letterSpacing,
  List<Shadow>? shadows,
}) =>
    GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      shadows: shadows,
    );

/// Shrinks a touch while pressed and springs back — every tappable thing on
/// the Community page uses it so taps feel the same everywhere.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.onTap, this.pressedScale = 0.92});

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1,
        duration: Duration(milliseconds: _down ? 90 : 260),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Round frosted-glass button (back, mute, close, share).
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.onDark = true,
    this.size = 42,
    this.iconSize = 21,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;

  /// White glass over video / photos; tinted glass on the light feed.
  final bool onDark;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : AppColors.txt;
    return Semantics(
      button: true,
      label: tooltip,
      child: PressScale(
        onTap: onTap,
        pressedScale: 0.86,
        child: ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onDark ? Colors.white.withValues(alpha: 0.16) : AppColors.txt.withValues(alpha: 0.06),
                border: Border.all(
                  color: onDark ? Colors.white.withValues(alpha: 0.24) : AppColors.line,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: iconSize, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Reperi mark inside a slowly turning gold ring.
class CommunityAvatar extends StatefulWidget {
  const CommunityAvatar({super.key, this.size = 40, this.spin = true});

  final double size;
  final bool spin;

  @override
  State<CommunityAvatar> createState() => _CommunityAvatarState();
}

class _CommunityAvatarState extends State<CommunityAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _turn =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    if (widget.spin) _turn.repeat();
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotationTransition(
            turns: reduceMotion ? const AlwaysStoppedAnimation<double>(0) : _turn,
            child: Container(
              width: s,
              height: s,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [kCommunityGold, Color(0xFFFDF003), kCommunityGoldDeep, Color(0xFFFFE89A), kCommunityGold],
                ),
              ),
            ),
          ),
          ReperiLogoMark(size: s - 5),
        ],
      ),
    );
  }
}

/// "Reperi ✓" — the account name with the gold verified tick.
class CommunityName extends StatelessWidget {
  const CommunityName({super.key, required this.color, this.size = 15, this.shadows});

  final Color color;
  final double size;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            'Reperi',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: communityText(size: size, weight: FontWeight.w800, color: color, shadows: shadows),
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.verified_rounded, size: size, color: kCommunityGold),
      ],
    );
  }
}

/// Fades + rises in the first time it's built (used for feed cards).
class EntranceFade extends StatelessWidget {
  const EntranceFade({super.key, required this.child, this.animate = true, this.delayIndex = 0});

  final Widget child;
  final bool animate;
  final int delayIndex;

  @override
  Widget build(BuildContext context) {
    if (!animate || MediaQuery.of(context).disableAnimations) return child;
    final ms = 420 + 70 * delayIndex.clamp(0, 4);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 26 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

/// Lets mouse / trackpad drag the reels and the viewer on the website.
class CommunityScrollBehavior extends MaterialScrollBehavior {
  const CommunityScrollBehavior();

  @override
  Set<ui.PointerDeviceKind> get dragDevices => {
        ui.PointerDeviceKind.touch,
        ui.PointerDeviceKind.mouse,
        ui.PointerDeviceKind.trackpad,
        ui.PointerDeviceKind.stylus,
      };
}

/// Centered message for empty / error states.
class CommunityMessage extends StatelessWidget {
  const CommunityMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.onDark,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool onDark;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : AppColors.txt;
    final mut = onDark ? Colors.white.withValues(alpha: 0.7) : AppColors.mut;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kCommunityGold.withValues(alpha: onDark ? 0.18 : 0.14),
              ),
              child: Icon(icon, color: kCommunityGold, size: 34),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: communityText(size: 19, weight: FontWeight.w800, color: fg)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: communityText(size: 14.5, weight: FontWeight.w500, color: mut, height: 1.45)),
            if (action != null && onAction != null) ...[
              const SizedBox(height: 20),
              PressScale(
                onTap: onAction,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  decoration: BoxDecoration(
                    color: kCommunityGold,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  alignment: Alignment.center,
                  child: Text(action!,
                      maxLines: 1,
                      style: communityText(size: 15, weight: FontWeight.w800, color: AppColors.onAccentDark)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
