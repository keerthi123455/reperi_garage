import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/catalog_service.dart';

/// Home screen strip (in place of the old Book Service / Book Washing
/// buttons): plain yellow, navy text —
///   "Car inspection at your location within [2 hours]      ₹199 ›"
///
/// Every 3 seconds, while the page isn't being scrolled, the strip grows a
/// touch and "2 hours" lights up (navy box, yellow text), then both settle
/// back. Stays still when the phone's "reduce motion" setting is on.
///
/// No fixed height anywhere: on a small phone or with a big font the text
/// simply wraps to another line and the strip gets taller — it never
/// overflows. The price column always keeps its own width.
class InspectionStrip extends StatefulWidget {
  const InspectionStrip({super.key, required this.onTap});

  final VoidCallback onTap;

  /// Doorstep Car Inspection in the Supabase `services` table.
  static const String serviceKey = 'os_inspection';

  @override
  State<InspectionStrip> createState() => _InspectionStripState();
}

class _InspectionStripState extends State<InspectionStrip> with SingleTickerProviderStateMixin {
  static const Color _yellow = Color(0xFFFDF003);
  static const Color _navy = Color(0xFF022B57);

  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  Timer? _timer;
  ScrollPosition? _scroll;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _maybePulse());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The page this strip sits in — used only to skip the pulse while the
    // customer is scrolling.
    _scroll = Scrollable.maybeOf(context)?.position;
  }

  void _maybePulse() {
    if (!mounted || _pulse.isAnimating || _pressed) return;
    if (MediaQuery.of(context).disableAnimations) return;
    if (_scroll?.isScrollingNotifier.value ?? false) return;
    _pulse.forward(from: 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final price = CatalogService.byKey(InspectionStrip.serviceKey)?.price ?? 199;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        // 0 → 1 → 0 over the pulse.
        final k = math.sin(math.pi * _pulse.value);
        return Transform.scale(
          scale: (_pressed ? 0.98 : 1.0) + 0.03 * k,
          child: Semantics(
            button: true,
            label: 'Car inspection at your location within 2 hours, $price rupees. Book.',
            excludeSemantics: true,
            child: Material(
              color: _yellow,
              borderRadius: BorderRadius.circular(18),
              elevation: 0,
              shadowColor: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                onHighlightChanged: (v) => setState(() => _pressed = v),
                borderRadius: BorderRadius.circular(18),
                splashColor: _navy.withOpacity(0.08),
                highlightColor: _navy.withOpacity(0.05),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(color: _navy.withOpacity(0.14), blurRadius: 16, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Padding(
                    // Slim: tight padding; the strip is only as tall as its
                    // text (one line on most phones, two on small ones).
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    child: Row(
                      children: [
                        Expanded(child: _text(k)),
                        const SizedBox(width: 10),
                        Text(
                          '₹$price',
                          maxLines: 1,
                          style: GoogleFonts.manrope(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                            color: _navy,
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: _navy, size: 22),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _text(double k) {
    final base = GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w800, height: 1.35, color: _navy);
    // "2 hours": plain bold text at rest; during the pulse it becomes a navy
    // box with yellow text.
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: _navy.withOpacity(k),
        borderRadius: BorderRadius.circular(6),
        boxShadow: k > 0
            ? [BoxShadow(color: _navy.withOpacity(0.22 * k), spreadRadius: 2.5 * k)]
            : null,
      ),
      child: Text(
        '2 hours',
        maxLines: 1,
        style: base.copyWith(
          fontWeight: FontWeight.w900,
          color: Color.lerp(_navy, _yellow, k),
          height: 1.3,
        ),
      ),
    );
    // One run of text, so it simply wraps onto a second line when the phone
    // is narrow or the font is big — never overflows.
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'Car inspection at your location '),
          TextSpan(text: 'within ', style: base.copyWith(fontWeight: FontWeight.w600)),
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: chip),
        ],
      ),
    );
  }
}
