import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/catalog_item.dart' show formatRupees;
import '../services/catalog_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import 'lighting_services_screen.dart';
import 'payment_screen.dart';
import 'reperi_resolve_screen.dart';
import 'services_screen.dart';

/// "Other Reperi Services" — opened from the yellow banner in the home
/// carousel (and the Services catalog).
///
///   • Doorstep Car Inspection  ₹299  (+ OBD scan add-on ₹899)
///   • Second Opinion           ₹399
///   • Shortcuts to Lighting, After-service issues and All services
///
/// Prices come from the Supabase `services` table (keys `os_…`, see
/// supabase/other_services.sql); the numbers below are only fallbacks.
class OtherServicesScreen extends StatefulWidget {
  const OtherServicesScreen({super.key, this.vehicle, this.highlightPackage});

  final Map<String, dynamic>? vehicle;
  final String? highlightPackage;

  @override
  State<OtherServicesScreen> createState() => _OtherServicesScreenState();
}

const _yellow = Color(0xFFFDF003);
const _navy = Color(0xFF022B57);
const _gold = Color(0xFFD4A017);
const _goldSoft = Color(0x29D4A017);
const _green = Color(0xFF2E9E5B);

const Map<String, int> _fallback = {
  'os_inspection': 299,
  'os_obd_scan': 899,
  'os_second_opinion': 399,
};

enum _Pick { inspection, opinion }

class _OtherServicesScreenState extends State<OtherServicesScreen> with TickerProviderStateMixin {
  _Pick _pick = _Pick.inspection;
  bool _obd = false;

  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    themeController.addListener(_refresh);
    CatalogService.revision.addListener(_refresh);
    CatalogService.ensureLoaded().catchError((_) {});
    final h = (widget.highlightPackage ?? '').toLowerCase();
    if (h.contains('opinion')) _pick = _Pick.opinion;
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeController.removeListener(_refresh);
    CatalogService.revision.removeListener(_refresh);
    _spin.dispose();
    super.dispose();
  }

  int _price(String key) => CatalogService.byKey(key)?.price ?? _fallback[key] ?? 0;

  int get _total => _pick == _Pick.inspection
      ? _price('os_inspection') + (_obd ? _price('os_obd_scan') : 0)
      : _price('os_second_opinion');

  String get _summary => _pick == _Pick.inspection
      ? (_obd ? 'Doorstep inspection + OBD scan' : 'Doorstep inspection')
      : 'Second opinion';

  void _select(VoidCallback f) {
    HapticFeedback.selectionClick();
    setState(f);
  }

  void _book() {
    HapticFeedback.mediumImpact();
    final keys = _pick == _Pick.inspection
        ? ['os_inspection', if (_obd) 'os_obd_scan']
        : ['os_second_opinion'];
    final main = CatalogService.byKey(keys.first);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: main?.name ?? (_pick == _Pick.inspection ? 'Doorstep Car Inspection' : 'Second Opinion'),
          duration: main?.duration ?? '',
          vehicleId: widget.vehicle?['id']?.toString() ?? '',
          serviceKeys: keys,
        ),
      ),
    );
  }

  void _open(Widget screen) {
    HapticFeedback.selectionClick();
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    var i = 0;
    Widget r(Widget w) => _Reveal(index: i++, child: w);
    final v = widget.vehicle;
    final vehicleLabel = v == null
        ? null
        : [
            [v['car_brand'], v['car_model']].where((x) => (x ?? '').toString().isNotEmpty).join(' '),
            (v['car_number'] ?? '').toString(),
          ].where((x) => x.trim().isNotEmpty).join(' · ');

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 270,
            backgroundColor: _yellow,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                color: _navy.withOpacity(0.12),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.maybePop(context),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.arrow_back_rounded, color: _navy, size: 22),
                  ),
                ),
              ),
            ),
            flexibleSpace: LayoutBuilder(builder: (context, c) {
              final minH = kToolbarHeight + top;
              final t = ((c.maxHeight - minH) / (270 + top - minH)).clamp(0.0, 1.0).toDouble();
              return Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(decoration: BoxDecoration(color: _yellow)),
                  // Soft rings for depth.
                  Positioned(
                    right: -60,
                    top: -40,
                    child: Opacity(
                      opacity: t,
                      child: Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.25)),
                      ),
                    ),
                  ),
                  // Big spanner that gently rocks.
                  Positioned(
                    right: 26,
                    top: top + 40,
                    child: Opacity(
                      opacity: t,
                      child: AnimatedBuilder(
                        animation: _spin,
                        builder: (context, child) => Transform.rotate(
                          angle: (Curves.easeInOut.transform(_spin.value) - 0.5) * 0.5,
                          child: child,
                        ),
                        child: const Icon(Icons.build_rounded, size: 110, color: _navy),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 150,
                    bottom: 26,
                    child: Opacity(
                      opacity: t,
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Other Reperi\nServices',
                              style: TextStyle(
                                  color: _navy, fontSize: 32, fontWeight: FontWeight.w900, height: 1.05, letterSpacing: -0.6)),
                          SizedBox(height: 8),
                          Text('Expert help at your doorstep — before you spend on repairs.',
                              style: TextStyle(color: _navy, fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 64,
                    right: 16,
                    top: top,
                    height: kToolbarHeight,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: (1 - t * 2.5).clamp(0.0, 1.0).toDouble(),
                        child: const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Other Reperi Services',
                              style: TextStyle(color: _navy, fontWeight: FontWeight.w900, fontSize: 18)),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 150),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                r(_label('Pick a service')),
                // ── Doorstep inspection ──
                r(_ServiceCard(
                  selected: _pick == _Pick.inspection,
                  icon: Icons.search_rounded,
                  eyebrow: "Don't know what's wrong with your car?",
                  title: 'Doorstep Car Inspection',
                  price: _price('os_inspection'),
                  pitch:
                      "Our expert comes to your doorstep, inspects your car, gives you a clear quote for what needs fixing — and leaves. No pressure to book the repair.",
                  bullets: const [
                    'Expert visit at your parking spot',
                    'Checks the problem you describe, plus a look over the car',
                    'A clear quote for the repair, before anything is touched',
                    'No obligation — book the repair only if you want to',
                  ],
                  onTap: () => _select(() => _pick = _Pick.inspection),
                  extra: _ObdAddOn(
                    on: _obd,
                    price: _price('os_obd_scan'),
                    onChanged: (v) => _select(() {
                      _pick = _Pick.inspection;
                      _obd = v;
                    }),
                  ),
                )),
                const SizedBox(height: 14),
                // ── Second opinion ──
                r(_ServiceCard(
                  selected: _pick == _Pick.opinion,
                  icon: Icons.balance_rounded,
                  eyebrow: 'Got a big quote from a garage?',
                  title: 'Second Opinion',
                  price: _price('os_second_opinion'),
                  pitch:
                      'Get a second opinion on your car before you get it serviced. Our expert checks your car and tells you honestly what really needs doing.',
                  bullets: const [
                    'Expert inspects your car at your parking spot',
                    'Goes through your garage or dealer quote line by line',
                    "Tells you what's urgent, what can wait and what isn't needed",
                    'A fair price estimate for the work that is needed',
                  ],
                  onTap: () => _select(() => _pick = _Pick.opinion),
                )),
                r(_label('How it works')),
                r(_Timeline(steps: [
                  const _Step(Icons.event_available_rounded, 'Book a slot',
                      "Pick a time and tell us where your car is parked. You'll get your expert's details."),
                  const _Step(Icons.directions_walk_rounded, 'Expert visits',
                      'They come to your parking spot with the tools needed and check your car with you.'),
                  _pick == _Pick.inspection
                      ? const _Step(Icons.receipt_long_rounded, 'Get your quote',
                          "You get a clear quote on the spot. Book the repair with us only if you want to.")
                      : const _Step(Icons.fact_check_rounded, 'Get honest advice',
                          "You get a clear answer on what's really needed and a fair price for it — then decide."),
                ])),
                r(_label('Why Reperi')),
                r(const _WhyRow()),
                r(_label('More from Reperi')),
                r(Row(
                  children: [
                    Expanded(
                      child: _MoreTile(
                        icon: Icons.lightbulb_rounded,
                        color: const Color(0xFFFFD54F),
                        title: 'Lighting',
                        sub: 'From ₹399',
                        onTap: () => _open(LightingServicesScreen(vehicle: widget.vehicle)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MoreTile(
                        icon: Icons.build_circle_rounded,
                        color: const Color(0xFFEF5B4C),
                        title: 'After-service issue',
                        sub: 'Get a price',
                        onTap: () => _open(ReperiResolveScreen(
                          vehicleId: v?['id']?.toString(),
                          vehicleLabel: vehicleLabel,
                        )),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MoreTile(
                        icon: Icons.grid_view_rounded,
                        color: const Color(0xFF4FA3E3),
                        title: 'All services',
                        sub: 'Browse',
                        onTap: () => _open(ServicesScreen(activeVehicle: widget.vehicle)),
                      ),
                    ),
                  ],
                )),
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BookBar(summary: _summary, price: _total, onBook: _book),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 12),
        child: Text(t, style: TextStyle(color: AppColors.txt, fontSize: 19, fontWeight: FontWeight.w900)),
      );
}

// ═══════════════════════════════════════════════════════════════════════

class _Step {
  const _Step(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;
}

class _Reveal extends StatefulWidget {
  const _Reveal({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 80 + math.min(widget.index, 8) * 60), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(a),
        child: widget.child,
      ),
    );
  }
}

class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(scale: _down ? 0.97 : 1, duration: const Duration(milliseconds: 120), child: widget.child),
    );
  }
}

/// A service card: collapsed shows the headline + price; selected expands
/// to show the pitch, what you get and any add-on.
class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.selected,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.price,
    required this.pitch,
    required this.bullets,
    required this.onTap,
    this.extra,
  });

  final bool selected;
  final IconData icon;
  final String eyebrow;
  final String title;
  final int price;
  final String pitch;
  final List<String> bullets;
  final VoidCallback onTap;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected ? _goldSoft : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: selected ? _gold : AppColors.line, width: selected ? 1.8 : 1),
          boxShadow: selected
              ? [BoxShadow(color: _gold.withOpacity(0.18), blurRadius: 22, offset: const Offset(0, 8))]
              : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: selected ? _gold : AppColors.chipBg,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: selected ? AppColors.onAccentDark : _gold, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(eyebrow,
                          style: TextStyle(color: AppColors.mut, fontSize: 12.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(title, style: TextStyle(color: AppColors.txt, fontSize: 18, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatRupees(price),
                        style: TextStyle(
                            color: selected ? _gold : AppColors.txt, fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    _Radio(selected: selected),
                  ],
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !selected
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pitch, style: TextStyle(color: AppColors.txt, fontSize: 14, height: 1.45)),
                          const SizedBox(height: 12),
                          for (final b in bullets)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: _green, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(b,
                                        style: TextStyle(color: AppColors.txt, fontSize: 13.5, height: 1.35)),
                                  ),
                                ],
                              ),
                            ),
                          if (extra != null) ...[const SizedBox(height: 6), extra!],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? _gold : Colors.transparent,
        border: Border.all(color: selected ? _gold : AppColors.mut, width: 2),
      ),
      child: AnimatedScale(
        scale: selected ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: Icon(Icons.check_rounded, size: 14, color: AppColors.onAccentDark),
      ),
    );
  }
}

/// "Add OBD scan +₹899" — an add-on with a switch.
class _ObdAddOn extends StatelessWidget {
  const _ObdAddOn({required this.on, required this.price, required this.onChanged});
  final bool on;
  final int price;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!on),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: on ? const Color(0x264FA3E3) : AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: on ? const Color(0xFF4FA3E3) : AppColors.line, width: on ? 1.6 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF4FA3E3).withOpacity(on ? 1 : 0.15),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.memory_rounded, color: on ? Colors.white : const Color(0xFF4FA3E3)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text('Add OBD scan',
                            style: TextStyle(color: AppColors.txt, fontSize: 15, fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 6),
                      Text('+${formatRupees(price)}',
                          style: const TextStyle(color: Color(0xFF4FA3E3), fontSize: 14, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    "Plugs into your car's computer to read fault codes and live sensor data — catches hidden engine and electrical faults.",
                    style: TextStyle(color: AppColors.mut, fontSize: 12.5, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: on,
              onChanged: onChanged,
              activeColor: Colors.white,
              activeTrackColor: const Color(0xFF4FA3E3),
            ),
          ],
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.steps});
  final List<_Step> steps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: _gold, shape: BoxShape.circle),
                        child: Text('${i + 1}',
                            style: TextStyle(color: AppColors.onAccentDark, fontWeight: FontWeight.w900, fontSize: 15)),
                      ),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [_gold, _gold.withOpacity(0.15)],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 18, top: 5),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        child: Column(
                          key: ValueKey(steps[i].title),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(steps[i].icon, size: 17, color: _gold),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(steps[i].title,
                                      style:
                                          TextStyle(color: AppColors.txt, fontSize: 15, fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(steps[i].text, style: TextStyle(color: AppColors.mut, fontSize: 13, height: 1.4)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WhyRow extends StatelessWidget {
  const _WhyRow();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.location_on_rounded, 'At your spot'),
      (Icons.verified_rounded, 'Checked experts'),
      (Icons.sell_rounded, 'Upfront prices'),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                children: [
                  Icon(items[i].$1, color: _gold, size: 26),
                  const SizedBox(height: 8),
                  Text(items[i].$2,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.txt, fontSize: 12.5, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.sub,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Container(
        height: 128,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: color.withOpacity(0.16), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 22),
            ),
            const Spacer(),
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.txt, fontSize: 13.5, fontWeight: FontWeight.w800, height: 1.15)),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _BookBar extends StatelessWidget {
  const _BookBar({required this.summary, required this.price, required this.onBook});
  final String summary;
  final int price;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, -6))],
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(summary,
                          key: ValueKey(summary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.mut, fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 2),
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: price.toDouble()),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => Text(formatRupees(v.round()),
                          style: const TextStyle(color: _gold, fontSize: 24, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
              ),
              _Pressable(
                onTap: onBook,
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: BoxDecoration(
                    color: _gold,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: _gold.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Row(
                    children: [
                      Text('Book now',
                          style: TextStyle(color: AppColors.onAccentDark, fontSize: 16, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, color: AppColors.onAccentDark, size: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
