import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Green round "Call an expert" hub button.
///
/// A green circle with a phone that hops and rings (little wiggle + sound
/// waves) every few seconds, with a breathing glow and a light sweep. Every
/// other cycle a "Call an expert" label slides out next to it. Tapping calls
/// the Reperi expert line.
///
/// Use as a Scaffold `floatingActionButton` (it then sits above any bottom
/// bar) or inside a Positioned.
class CallExpertButton extends StatefulWidget {
  const CallExpertButton({
    super.key,
    this.phone = kExpertPhone,
    this.labelOnLeft = true,
    this.showLabel = true,
  });

  final String phone;

  /// Off when the button sits inside a bar (the sliding label would push
  /// the other buttons around).
  final bool showLabel;

  /// The "Call an expert" label slides out to the left (button on the right
  /// edge) or to the right (button on the left edge).
  final bool labelOnLeft;

  static const String kExpertPhone = '9353094672';

  @override
  State<CallExpertButton> createState() => _CallExpertButtonState();
}

class _CallExpertButtonState extends State<CallExpertButton> with TickerProviderStateMixin {
  static const double _size = 60;
  static const Color _green = Color(0xFF1FAA59);
  static const Color _greenDark = Color(0xFF128043);

  /// Two attention cycles per loop; the label shows on the second.
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 8400))..repeat();
  late final AnimationController _glow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    _glow.dispose();
    super.dispose();
  }

  Future<void> _call() async {
    HapticFeedback.mediumImpact();
    final uri = Uri.parse('tel:${widget.phone}');
    try {
      if (!await launchUrl(uri)) throw 'no dialer';
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Call us on ${widget.phone}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Semantics(
      button: true,
      label: 'Call an expert',
      child: GestureDetector(
        onTap: _call,
        child: AnimatedBuilder(
          animation: Listenable.merge([_c, _glow]),
          builder: (context, _) {
            final loop = reduceMotion ? 0.9 : _c.value;
            final v = (loop * 2) % 1.0; // one attention cycle
            final labelT = reduceMotion || !widget.showLabel ? 0.0 : _label(loop);

            final label = ClipRect(
              child: Align(
                alignment: widget.labelOnLeft ? Alignment.centerRight : Alignment.centerLeft,
                widthFactor: labelT,
                child: Opacity(
                  opacity: labelT,
                  child: Container(
                    margin: EdgeInsets.only(left: widget.labelOnLeft ? 0 : 8, right: widget.labelOnLeft ? 8 : 0),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: _greenDark,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: const Text(
                      'Call an expert',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            );

            final bubble = Transform.translate(
              offset: Offset(0, _hop(v)),
              child: SizedBox(
                width: _size,
                height: _size,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // Sound-wave rings while it "rings".
                    if (!reduceMotion)
                      for (final delay in const [0.0, 0.12])
                        Builder(builder: (_) {
                          final p = _ring(v, delay);
                          if (p == null) return const SizedBox.shrink();
                          return Transform.scale(
                            scale: 1 + 0.75 * Curves.easeOutCubic.transform(p),
                            child: Container(
                              width: _size,
                              height: _size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: _green.withOpacity(0.8 * (1 - p)), width: 3 * (1 - p) + 0.5),
                              ),
                            ),
                          );
                        }),
                    Container(
                      width: _size,
                      height: _size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF34D17A), _green, _greenDark],
                        ),
                        border: Border.all(color: Colors.white.withOpacity(0.75), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: _green.withOpacity(0.3 + 0.3 * _glow.value),
                            blurRadius: 14 + 10 * _glow.value,
                            spreadRadius: 1 + 3 * _glow.value,
                          ),
                          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6)),
                        ],
                      ),
                      child: ClipOval(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Center(
                              child: Transform.rotate(
                                angle: _wiggle(v),
                                child: const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 28),
                              ),
                            ),
                            if (!reduceMotion)
                              Builder(builder: (_) {
                                final p = _shine(v);
                                if (p == null) return const SizedBox.shrink();
                                return Transform.translate(
                                  offset: Offset(-_size + 2 * _size * p, 0),
                                  child: Transform.rotate(
                                    angle: 0.5,
                                    child: Center(
                                      child: Container(
                                        width: 14,
                                        height: _size * 1.8,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(colors: [
                                            Colors.white.withOpacity(0),
                                            Colors.white.withOpacity(0.7),
                                            Colors.white.withOpacity(0),
                                          ]),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );

            if (!widget.showLabel) return bubble;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: widget.labelOnLeft ? [label, bubble] : [bubble, label],
            );
          },
        ),
      ),
    );
  }

  // One attention cycle (4.2 s): hop · ring (wiggle + waves) · shine · rest.
  static double _hop(double v) {
    const h = 9.0;
    if (v < 0.07) return -h * Curves.easeOutCubic.transform(v / 0.07);
    if (v < 0.20) return -h * (1 - Curves.bounceOut.transform((v - 0.07) / 0.13));
    return 0;
  }

  static double _wiggle(double v) {
    if (v < 0.20 || v >= 0.42) return 0;
    final p = (v - 0.20) / 0.22;
    return math.sin(p * math.pi * 8) * 0.35 * (1 - p);
  }

  static double? _ring(double v, double delay) {
    final a = 0.20 + delay;
    if (v < a || v >= a + 0.36) return null;
    return (v - a) / 0.36;
  }

  static double? _shine(double v) =>
      (v < 0.5 || v >= 0.68) ? null : Curves.easeInOutCubic.transform((v - 0.5) / 0.18);

  /// Label: slides out during the second cycle, stays ~2 s, slides back.
  static double _label(double loop) {
    const inStart = 0.55, inEnd = 0.62, outStart = 0.86, outEnd = 0.93;
    if (loop < inStart || loop >= outEnd) return 0;
    if (loop < inEnd) return Curves.easeOutCubic.transform((loop - inStart) / (inEnd - inStart));
    if (loop < outStart) return 1;
    return 1 - Curves.easeInCubic.transform((loop - outStart) / (outEnd - outStart));
  }
}

/// Pins the button to the bottom-right corner: 16 px from the right edge,
/// 12 px above the bottom bar (or the screen bottom when there's none).
/// Use with `floatingActionButtonLocation: kCallExpertLocation`.
const FloatingActionButtonLocation kCallExpertLocation = _CornerLocation();

class _CornerLocation extends FloatingActionButtonLocation {
  const _CornerLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry g) {
    final x = g.scaffoldSize.width - g.floatingActionButtonSize.width - 16 - g.minViewPadding.right;
    // contentBottom = top of the bottom bar / keyboard / safe area.
    final y = g.contentBottom - g.floatingActionButtonSize.height - 12;
    return Offset(x, y);
  }
}
