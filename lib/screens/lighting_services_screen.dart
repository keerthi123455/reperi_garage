import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/catalog_item.dart' show formatRupees;
import '../services/catalog_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import 'payment_screen.dart';

/// Lighting Services — three jobs on one screen:
///   • Bulb change          (1 or 2 bulbs, priced by car size)
///   • Headlight restoration (2 or all 4 lamps)
///   • Headlight replacement (cracked / damaged; at our station or your spot)
///
/// Prices come from the Supabase `services` table (keys `lt_…`, see
/// supabase/lighting_services.sql) — the numbers below are only fallbacks
/// shown while the catalog loads. Booking goes through PaymentScreen like
/// every other package, which handles login, vehicle and address.
class LightingServicesScreen extends StatefulWidget {
  const LightingServicesScreen({super.key, this.vehicle, this.highlightPackage});

  final Map<String, dynamic>? vehicle;

  /// Opens on the matching service when it names one (e.g. from the
  /// Services catalog or the AI advisor).
  final String? highlightPackage;

  @override
  State<LightingServicesScreen> createState() => _LightingServicesScreenState();
}

enum _Svc { bulb, restore, replace }

enum _Size { std, csuv, lsuv }

extension on _Size {
  String get code => switch (this) { _Size.std => 'std', _Size.csuv => 'csuv', _Size.lsuv => 'lsuv' };
  String get label => switch (this) {
        _Size.std => 'Hatchback & Sedan',
        _Size.csuv => 'Compact SUV',
        _Size.lsuv => 'Large SUV',
      };
  IconData get icon => switch (this) {
        _Size.std => Icons.directions_car_filled_rounded,
        _Size.csuv => Icons.airport_shuttle_rounded,
        _Size.lsuv => Icons.local_shipping_rounded,
      };
}

const _gold = Color(0xFFD4A017);
const _goldSoft = Color(0x29D4A017);
const _green = Color(0xFF2E9E5B);

/// Shown only until the catalog loads; the server always charges its own price.
const Map<String, int> _fallbackPrices = {
  'lt_bulb1_std': 399,
  'lt_bulb1_csuv': 399,
  'lt_bulb1_lsuv': 449,
  'lt_bulb2_std': 599,
  'lt_bulb2_csuv': 599,
  'lt_bulb2_lsuv': 649,
  'lt_hl_restore_2': 6299,
  'lt_hl_restore_4': 8999,
  'lt_hl_replace_station': 1199,
  'lt_hl_replace_spot': 1199,
};

class _LightingServicesScreenState extends State<LightingServicesScreen> with TickerProviderStateMixin {
  _Svc _svc = _Svc.bulb;
  int _bulbs = 1;
  _Size _size = _Size.std;
  int _lamps = 2;
  String _mode = 'spot'; // replacement: 'spot' | 'station'

  late final AnimationController _glow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    themeController.addListener(_onTheme);
    CatalogService.revision.addListener(_onTheme);
    CatalogService.ensureLoaded().catchError((_) {});
    final h = (widget.highlightPackage ?? '').toLowerCase();
    if (h.contains('restor')) _svc = _Svc.restore;
    if (h.contains('replace')) _svc = _Svc.replace;
  }

  void _onTheme() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeController.removeListener(_onTheme);
    CatalogService.revision.removeListener(_onTheme);
    _glow.dispose();
    super.dispose();
  }

  // ── Selection → service key & price ──────────────────────────────────

  String get _key => switch (_svc) {
        _Svc.bulb => 'lt_bulb${_bulbs}_${_size.code}',
        _Svc.restore => 'lt_hl_restore_$_lamps',
        _Svc.replace => 'lt_hl_replace_$_mode',
      };

  int _priceOf(String key) => CatalogService.byKey(key)?.price ?? _fallbackPrices[key] ?? 0;

  String get _summary => switch (_svc) {
        _Svc.bulb => '${_bulbs == 1 ? '1 bulb' : '2 bulbs'} · ${_size.label}',
        _Svc.restore => _lamps == 2 ? '2 headlights' : 'All 4 headlights',
        _Svc.replace => _mode == 'station' ? 'At our service station' : 'At your parking spot',
      };

  String get _title => switch (_svc) {
        _Svc.bulb => 'Bulb Change',
        _Svc.restore => 'Headlight Restoration',
        _Svc.replace => 'Headlight Replacement',
      };

  void _book() {
    HapticFeedback.mediumImpact();
    final key = _key;
    final item = CatalogService.byKey(key);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: item?.name ?? '$_title — $_summary',
          duration: item?.duration ?? '',
          vehicleId: widget.vehicle?['id']?.toString() ?? '',
          serviceKeys: [key],
        ),
      ),
    );
  }

  void _select(VoidCallback change) {
    HapticFeedback.selectionClick();
    setState(change);
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            backgroundColor: AppColors.ink,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: _CircleButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.maybePop(context)),
            ),
            flexibleSpace: LayoutBuilder(builder: (context, c) {
              // 1 = fully open, 0 = collapsed to the toolbar.
              final minH = kToolbarHeight + top;
              final t = ((c.maxHeight - minH) / (300 + top - minH)).clamp(0.0, 1.0).toDouble();
              return Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(opacity: t, child: _Hero(glow: _glow)),
                  // Small title fades in as the photo collapses.
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
                          child: Text('Lighting Services',
                              style: TextStyle(color: _gold, fontWeight: FontWeight.w900, fontSize: 18)),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabsHeader(
              selected: _svc,
              onSelect: (s) => _select(() => _svc = s),
            ),
          ),
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(a),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(_svc),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 150),
                  child: switch (_svc) {
                    _Svc.bulb => _bulbContent(),
                    _Svc.restore => _restoreContent(),
                    _Svc.replace => _replaceContent(),
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BookBar(
        title: _title,
        summary: _summary,
        price: _priceOf(_key),
        fromPrice: _svc == _Svc.replace,
        onBook: _book,
      ),
    );
  }

  // ── Bulb change ──────────────────────────────────────────────────────

  Widget _bulbContent() {
    var i = 0;
    Widget r(Widget w) => _Reveal(index: i++, child: w);
    final n = _bulbs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        r(_lead(
          n == 1 ? 'Covers one bulb swap.' : 'Covers two bulb swaps.',
          'Any socket or wiring work is billed separately, based on what\'s actually needed.',
        )),
        r(_heading('How many bulbs?')),
        r(Row(
          children: [
            Expanded(
              child: _ChoiceCard(
                selected: _bulbs == 1,
                icon: Icons.lightbulb_outline_rounded,
                title: '1 bulb',
                subtitle: 'Single swap',
                onTap: () => _select(() => _bulbs = 1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ChoiceCard(
                selected: _bulbs == 2,
                icon: Icons.lightbulb_rounded,
                title: '2 bulbs',
                subtitle: '+ ${formatRupees(_priceOf('lt_bulb2_${_size.code}') - _priceOf('lt_bulb1_${_size.code}'))}',
                tag: 'Pair',
                onTap: () => _select(() => _bulbs = 2),
              ),
            ),
          ],
        )),
        r(_heading('Pricing for your car')),
        r(Column(
          children: [
            for (final s in _Size.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SizeRow(
                  size: s,
                  price: _priceOf('lt_bulb${_bulbs}_${s.code}'),
                  selected: _size == s,
                  onTap: () => _select(() => _size = s),
                ),
              ),
          ],
        )),
        r(_heading('How the job is done')),
        r(_Steps(items: [
          const _Item(Icons.search_rounded, 'Fault check',
              "We find the bulb that's out and spot any lighting problem in your headlamps, tail lamps, turn signals, brake lamps or any other light we can reach."),
          _Item(Icons.swap_horiz_rounded, 'Bulb swap',
              n == 1
                  ? 'The blown or damaged bulb is carefully removed without touching the lamp housing or wiring, and one matching bulb is fitted firmly with a secure connection.'
                  : 'The blown or damaged bulbs are carefully removed without touching the lamp housing or wiring, and two matching bulbs are fitted firmly with secure connections.'),
          const _Item(Icons.flash_on_rounded, 'Light test',
              "We switch it on to confirm it's bright, working properly and getting power correctly."),
          _Item(Icons.receipt_long_rounded, 'What the price covers',
              n == 1
                  ? 'The fee is for the labour of swapping one bulb. The bulb itself, sockets, wiring fixes and any extra swaps are billed on top.'
                  : 'The fee is for the labour of swapping two bulbs. The bulbs themselves, sockets, wiring fixes and any extra swaps are billed on top.'),
        ])),
        r(_heading('What you pay for')),
        r(const _PayFor(
          covered: [
            'The work in this package, including the consumables mentioned in the offer',
            'A quick look over the connected parts',
          ],
          extra: [
            "Any other worn parts we find (we share the price first) and jobs that aren't part of this package",
          ],
        )),
        ..._commonSections(r, atStation: false),
      ],
    );
  }

  // ── Headlight restoration ────────────────────────────────────────────

  Widget _restoreContent() {
    var i = 0;
    Widget r(Widget w) => _Reveal(index: i++, child: w);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        r(_lead('Cloudy, yellowed headlights made clear again.',
            'Brings back a cleaner look and a brighter beam at night — done at your parking spot.')),
        r(_heading('How many headlights?')),
        r(Row(
          children: [
            Expanded(
              child: _ChoiceCard(
                selected: _lamps == 2,
                icon: Icons.highlight_rounded,
                title: '2 headlights',
                subtitle: formatRupees(_priceOf('lt_hl_restore_2')),
                onTap: () => _select(() => _lamps = 2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ChoiceCard(
                selected: _lamps == 4,
                icon: Icons.wb_iridescent_rounded,
                title: 'All 4',
                subtitle: formatRupees(_priceOf('lt_hl_restore_4')),
                tag: 'Best value',
                onTap: () => _select(() => _lamps = 4),
              ),
            ),
          ],
        )),
        r(_heading('How the job is done')),
        r(const _Steps(items: [
          _Item(Icons.search_rounded, 'Lens check',
              'We look at each headlight to see how hazy, yellowed or scratched the lens is.'),
          _Item(Icons.auto_fix_high_rounded, 'Restoring the lens',
              'The dull outer layer is worked back to a clear finish, without removing the headlight from your car.'),
          _Item(Icons.flash_on_rounded, 'Light test',
              'We switch the lights on with you to check the clarity and brightness.'),
        ])),
        r(_heading('What you pay for')),
        r(_PayFor(
          covered: [
            _lamps == 2 ? 'Restoration of 2 headlights' : 'Restoration of all 4 headlights',
            'A quick look over the connected parts',
          ],
          extra: const [
            "Cracked lenses or damaged headlights that need replacing (we share the price first) and jobs that aren't part of this package",
          ],
        )),
        ..._commonSections(r, atStation: false),
      ],
    );
  }

  // ── Headlight replacement ────────────────────────────────────────────

  Widget _replaceContent() {
    var i = 0;
    Widget r(Widget w) => _Reveal(index: i++, child: w);
    final station = _mode == 'station';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        r(_lead('Cracked or damaged headlights, replaced.',
            'Starting from ${formatRupees(_priceOf('lt_hl_replace_spot'))}.')),
        r(const _Note(
          icon: Icons.info_rounded,
          text: "The final price depends on your car's brand and model. We confirm it with you before any work starts.",
        )),
        r(_heading('Where should we do it?')),
        r(Column(
          children: [
            _ModeCard(
              selected: !station,
              icon: Icons.local_parking_rounded,
              title: 'At your parking spot',
              text: 'Our technician brings every tool needed and fixes it right where your car is parked.',
              onTap: () => _select(() => _mode = 'spot'),
            ),
            const SizedBox(height: 12),
            _ModeCard(
              selected: station,
              icon: Icons.garage_rounded,
              title: 'At our service station',
              text:
                  'Our technician takes your car to the service station, gets it fixed and brings it back to your parking spot as soon as it\'s done.',
              tag: 'Pickup & drop included',
              onTap: () => _select(() => _mode = 'station'),
            ),
          ],
        )),
        r(_heading('What you pay for')),
        r(const _PayFor(
          covered: [
            'Labour to remove the damaged headlight and fit the new one',
            'Checking the new headlight works properly',
          ],
          extra: [
            'The headlight unit itself — priced for your car, shared with you first',
            "Any other worn parts we find and jobs that aren't part of this package",
          ],
        )),
        ..._commonSections(r, atStation: station),
      ],
    );
  }

  // ── Sections shared by all three ─────────────────────────────────────

  List<Widget> _commonSections(Widget Function(Widget) r, {required bool atStation}) {
    return [
      r(_heading('Why book with Reperi')),
      r(_WhyGrid(items: [
        atStation
            ? const _Item(Icons.swap_calls_rounded, 'Pickup & drop', 'We collect your car and bring it back')
            : const _Item(Icons.location_on_rounded, 'At your spot', 'We come to wherever your car is parked'),
        const _Item(Icons.sell_rounded, 'Fixed price', 'One clear price for this job, no surprises'),
        const _Item(Icons.visibility_rounded, 'Old parts shown', 'You see them before we throw them away'),
        const _Item(Icons.description_rounded, 'Work report', 'A short report once the work is done'),
      ])),
      r(_heading('How it works')),
      r(_Timeline(steps: [
        const _Item(Icons.event_available_rounded, 'You book',
            'Choose a time and tell us where your car is parked, and a checked mechanic is assigned to you.'),
        atStation
            ? const _Item(Icons.garage_rounded, 'We take it in and fix it',
                "Your technician picks up your car, gets it fixed at our service station and drives it back to your parking spot as soon as it's done. If something more is needed, we tell you the price and wait for your OK.")
            : const _Item(Icons.build_rounded, 'We come and fix it on the spot',
                'Your mechanic arrives with every tool and consumable needed and does the work right where your car is. If something more is needed, we tell you the price and wait for your OK.'),
        const _Item(Icons.handshake_rounded, 'We wrap up together',
            'Your mechanic walks you through what was done and sends you a summary.'),
      ])),
      r(_heading('Your Reperi mechanic')),
      r(const _MechanicCard()),
    ];
  }

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 12),
        child: Text(t, style: TextStyle(color: AppColors.txt, fontSize: 19, fontWeight: FontWeight.w900)),
      );

  Widget _lead(String title, String text) => Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [_goldSoft, _gold.withOpacity(0.04)]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _gold.withOpacity(0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.tips_and_updates_rounded, color: _gold, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: AppColors.txt, fontSize: 15.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(text, style: TextStyle(color: AppColors.mut, fontSize: 13.5, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════
//  Pieces
// ═══════════════════════════════════════════════════════════════════════

class _Item {
  const _Item(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;
}

/// Headlight photo with a slow "breathing" glow over the bulb.
class _Hero extends StatelessWidget {
  const _Hero({required this.glow});
  final Animation<double> glow;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/images/lighting_hero.jpeg', fit: BoxFit.cover, alignment: const Alignment(-0.1, 0)),
        AnimatedBuilder(
          animation: glow,
          builder: (context, _) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.25, -0.05),
                radius: 0.45 + glow.value * 0.12,
                colors: [
                  Colors.white.withOpacity(0.10 + glow.value * 0.18),
                  Colors.white.withOpacity(0),
                ],
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.35, 1],
              colors: [Colors.black.withOpacity(0.55), Colors.transparent, AppColors.ink],
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 22,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(8)),
                child: Text('FROM ₹399',
                    style: TextStyle(
                        color: AppColors.onAccentDark, fontWeight: FontWeight.w900, fontSize: 11.5, letterSpacing: 1)),
              ),
              const SizedBox(height: 10),
              const Text('Lighting Services',
                  style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              const SizedBox(height: 4),
              Text('Bulbs, restoration & replacement — done at your parking spot',
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13.5, height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

/// Pinned pill tabs: Bulb change · Restoration · Replacement.
class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader({required this.selected, required this.onSelect});
  final _Svc selected;
  final ValueChanged<_Svc> onSelect;

  @override
  double get minExtent => 68;
  @override
  double get maxExtent => 68;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    const labels = {_Svc.bulb: 'Bulb change', _Svc.restore: 'Restoration', _Svc.replace: 'Replacement'};
    const icons = {
      _Svc.bulb: Icons.lightbulb_rounded,
      _Svc.restore: Icons.auto_fix_high_rounded,
      _Svc.replace: Icons.build_circle_rounded,
    };
    return Container(
      color: AppColors.ink,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / 3;
        final idx = _Svc.values.indexOf(selected);
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                left: idx * w + 3,
                top: 3,
                bottom: 3,
                width: w - 6,
                child: Container(
                  decoration: BoxDecoration(
                    color: _gold,
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [BoxShadow(color: _gold.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final s in _Svc.values)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelect(s),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 220),
                            style: TextStyle(
                              color: s == selected ? AppColors.onAccentDark : AppColors.mut,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(icons[s], size: 15, color: s == selected ? AppColors.onAccentDark : AppColors.mut),
                                  const SizedBox(width: 5),
                                  Text(labels[s]!),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }

  @override
  bool shouldRebuild(_TabsHeader old) => old.selected != selected;
}

/// Fades and slides a section in, staggered by [index].
class _Reveal extends StatefulWidget {
  const _Reveal({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: math.min(widget.index, 8) * 55), () {
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

/// Springy press feedback for anything tappable.
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
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tag,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? _goldSoft : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _gold : AppColors.line, width: selected ? 1.8 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: selected ? _gold : AppColors.chipBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: selected ? AppColors.onAccentDark : _gold),
                ),
                const Spacer(),
                _Radio(selected: selected),
              ],
            ),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: AppColors.txt, fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Row(
              children: [
                Flexible(
                  child: Text(subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: selected ? _gold : AppColors.mut, fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
                if (tag != null) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: _green.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                      child: Text(tag!,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _green, fontSize: 10.5, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ],
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

class _SizeRow extends StatelessWidget {
  const _SizeRow({required this.size, required this.price, required this.selected, required this.onTap});
  final _Size size;
  final int price;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? _goldSoft : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? _gold : AppColors.line, width: selected ? 1.8 : 1),
        ),
        child: Row(
          children: [
            Icon(size.icon, color: selected ? _gold : AppColors.mut, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Text(size.label,
                  style: TextStyle(color: AppColors.txt, fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.5), end: Offset.zero).animate(a),
                  child: c,
                ),
              ),
              child: Text(formatRupees(price),
                  key: ValueKey(price),
                  style: TextStyle(
                      color: selected ? _gold : AppColors.txt, fontSize: 17, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 12),
            _Radio(selected: selected),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
    this.tag,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String text;
  final String? tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? _goldSoft : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _gold : AppColors.line, width: selected ? 1.8 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected ? _gold : AppColors.chipBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: selected ? AppColors.onAccentDark : _gold),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: AppColors.txt, fontSize: 15.5, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(text, style: TextStyle(color: AppColors.mut, fontSize: 13, height: 1.4)),
                  if (tag != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _green.withOpacity(0.15), borderRadius: BorderRadius.circular(7)),
                      child: Text(tag!,
                          style: const TextStyle(color: _green, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Radio(selected: selected),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x1FF0A020),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x66F0A020)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFF0A020), size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: AppColors.txt, fontSize: 13.5, height: 1.4))),
        ],
      ),
    );
  }
}

/// "How the job is done" — icon cards in a column.
class _Steps extends StatelessWidget {
  const _Steps({required this.items});
  final List<_Item> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.line, indent: 66),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: _goldSoft, borderRadius: BorderRadius.circular(12)),
                    child: Icon(items[i].icon, color: _gold, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(items[i].title,
                            style: TextStyle(color: AppColors.txt, fontSize: 14.5, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(items[i].text, style: TextStyle(color: AppColors.mut, fontSize: 13, height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PayFor extends StatelessWidget {
  const _PayFor({required this.covered, required this.extra});
  final List<String> covered;
  final List<String> extra;

  @override
  Widget build(BuildContext context) {
    Widget block(String title, List<String> lines, bool ok) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: (ok ? _green : const Color(0xFFE5484D)).withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: ok ? _green : const Color(0xFFE5484D), fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
              const SizedBox(height: 10),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(ok ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                          size: 18, color: ok ? _green : const Color(0xFFE5484D)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(l, style: TextStyle(color: AppColors.txt, fontSize: 13.5, height: 1.35))),
                    ],
                  ),
                ),
            ],
          ),
        );
    return Column(
      children: [
        block('COVERED IN THE PRICE', covered, true),
        const SizedBox(height: 10),
        block('BILLED SEPARATELY', extra, false),
      ],
    );
  }
}

class _WhyGrid extends StatelessWidget {
  const _WhyGrid({required this.items});
  final List<_Item> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final it in items)
            Container(
              width: w,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(it.icon, color: _gold, size: 24),
                  const SizedBox(height: 10),
                  Text(it.title, style: TextStyle(color: AppColors.txt, fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(it.text, style: TextStyle(color: AppColors.mut, fontSize: 12.5, height: 1.35)),
                ],
              ),
            ),
        ],
      );
    });
  }
}

/// Numbered vertical timeline for "How it works".
class _Timeline extends StatelessWidget {
  const _Timeline({required this.steps});
  final List<_Item> steps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(steps[i].icon, size: 17, color: _gold),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(steps[i].title,
                                    style: TextStyle(color: AppColors.txt, fontSize: 15, fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(steps[i].text, style: TextStyle(color: AppColors.mut, fontSize: 13, height: 1.4)),
                        ],
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

class _MechanicCard extends StatelessWidget {
  const _MechanicCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceRaised, AppColors.surfaceSunken],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _gold.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: const BoxDecoration(color: _goldSoft, shape: BoxShape.circle),
                    child: const Icon(Icons.engineering_rounded, color: _gold, size: 30),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: AppColors.surfaceRaised, shape: BoxShape.circle),
                      child: const Icon(Icons.verified_rounded, color: _green, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text('Checked and trusted, on every visit',
                    style: TextStyle(color: AppColors.txt, fontSize: 15.5, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final t in const [
            'Background-checked before joining, and fully skilled and equipped for this work',
            'One mechanic updates you from start to finish',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_rounded, color: _gold, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(t, style: TextStyle(color: AppColors.txt, fontSize: 13.5, height: 1.35))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Sticky booking bar: what's selected, the price (animated) and Book now.
class _BookBar extends StatelessWidget {
  const _BookBar({
    required this.title,
    required this.summary,
    required this.price,
    required this.fromPrice,
    required this.onBook,
  });

  final String title;
  final String summary;
  final int price;
  final bool fromPrice;
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        if (fromPrice)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text('from', style: TextStyle(color: AppColors.mut, fontSize: 12.5)),
                          ),
                        TweenAnimationBuilder<double>(
                          tween: Tween(end: price.toDouble()),
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOutCubic,
                          builder: (context, v, _) => Text(
                            formatRupees(v.round()),
                            style: const TextStyle(color: _gold, fontSize: 24, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
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
