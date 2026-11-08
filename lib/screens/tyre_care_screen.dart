import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/catalog_item.dart';
import '../services/catalog_service.dart';
import '../services/contact_settings.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../widgets/catalog_gate.dart';
import 'payment_screen.dart';

/// Wheel care — alignment, balancing (priced per wheel, 1–4 wheels), the
/// combo, plus the other tyre-care packages and the tyre-change quote.
///
/// One screen for both entry points: the "Tyres & Wheels" tile and the
/// "Wheel Management" banner (WheelManagementPackageScreen just opens this).
///
/// Every name and price comes from the Supabase `services` table:
///   wheel_alignment            ₹439   all 4 wheels
///   wheel_balancing            ₹676   4 wheels (details.per_wheel = 169)
///   wheel_balancing_1w/2w/3w   ₹169 / ₹338 / ₹507 — hidden rows, booked
///                              when the customer picks fewer wheels
///   wheel_alignment_balancing  ₹1,099
///   + anything else on the 'tyre_care' screen (e.g. Quick Air & Check)
/// The server re-prices whatever key is booked, so the app never sends a price.
class TyreCareScreen extends StatefulWidget {
  final Map<String, dynamic> vehicle;

  /// When set (a package name, case-insensitive), that package is
  /// pre-selected on open.
  final String? highlightPackage;

  const TyreCareScreen({
    super.key,
    required this.vehicle,
    this.highlightPackage,
  });

  @override
  State<TyreCareScreen> createState() => _TyreCareScreenState();
}

// ── Catalog keys ─────────────────────────────────────────────────────
const _kCombo = 'wheel_alignment_balancing';
const _kAlign = 'wheel_alignment';
const _kBalance = 'wheel_balancing';
const _wheelKeys = {_kCombo, _kAlign, _kBalance};

/// Booking key for balancing [n] wheels (4 = the main row).
String _balanceKey(int n) => n >= 4 ? _kBalance : '${_kBalance}_${n}w';

/// The one-line "when you need this" under each wheel option. Can be
/// overridden per service in Supabase: details.display.wheel_care.symptom.
const _symptoms = {
  _kCombo: 'Complete wheel care in one visit',
  _kAlign: 'Car pulls to one side',
  _kBalance: 'Steering shakes at speed',
};

// ── Colours (this screen's green, tuned for light and dark mode) ─────
const _heroGreen = Color(0xFF0F3D24);
const _heroMint = Color(0xFF86EFAC);
Color get _green => AppColors.isDark ? const Color(0xFF22A55A) : const Color(0xFF15803D);
Color get _greenSoft => _green.withOpacity(AppColors.isDark ? 0.14 : 0.08);
Color get _greenLine => _green.withOpacity(AppColors.isDark ? 0.45 : 0.30);
const _onGreen = Colors.white;

class _TyreCareScreenState extends State<TyreCareScreen> {
  /// Selected option: one of the wheel keys or another tyre-care key.
  String? _selectedKey;

  /// Wheels to balance (1–4) when Wheel Balancing is selected.
  int _wheels = 4;

  String? _tyreBrand;
  int? _wheelSize;

  final GlobalKey _optionsKey = GlobalKey();

  static const _tyreBrands = ['MRF', 'CEAT', 'Michelin', 'Continental', 'Bridgestone'];
  static const _wheelSizes = [15, 16, 17, 18, 19, 20];

  String get _vehicleId => (widget.vehicle['id'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    // AppColors is changed in place by themeController, so listen and rebuild.
    themeController.addListener(_onThemeChanged);
    CatalogService.ensureLoaded().then((_) {
      if (mounted) setState(_applyInitialSelection);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  // ── Catalog helpers ────────────────────────────────────────────────
  CatalogItem? _item(String key) => CatalogService.byKey(key);

  /// The three wheel options that exist in the catalog, in display order.
  List<CatalogItem> get _wheelOptions => [
        for (final k in const [_kCombo, _kAlign, _kBalance])
          if (_item(k) != null) _item(k)!,
      ];

  /// Every other tyre/wheel package (e.g. Quick Air & Check).
  List<CatalogItem> get _otherOptions {
    final seen = <String>{};
    return [
      for (final i in [...CatalogService.forScreen('tyre_care'), ...CatalogService.forScreen('wheel')])
        if (!i.isAddon && !_wheelKeys.contains(i.key) && seen.add(i.key)) i,
    ];
  }

  /// Wheel counts (1–4) that have a price row.
  List<int> get _wheelChoices => [
        for (var n = 1; n <= 4; n++)
          if (_item(_balanceKey(n))?.price != null) n,
      ];

  /// ₹ per wheel = the 1-wheel row's price, so changing that price in
  /// Supabase / the CRM also changes the "₹169 per wheel" label. Falls back
  /// to details.per_wheel; null until wheel_pricing.sql has been run.
  int? get _perWheel {
    final single = _item(_balanceKey(1))?.price;
    if (single != null) return single;
    final v = _item(_kBalance)?.details['per_wheel'];
    return v is num ? v.round() : int.tryParse('${v ?? ''}');
  }

  /// What actually gets booked for the current selection.
  CatalogItem? get _bookingItem {
    final key = _selectedKey;
    if (key == null) return null;
    if (key == _kBalance) {
      final n = _wheelChoices.contains(_wheels) ? _wheels : 4;
      return _item(_balanceKey(n)) ?? _item(_kBalance);
    }
    return _item(key);
  }

  void _applyInitialSelection() {
    final all = [..._wheelOptions, ..._otherOptions];
    if (all.isEmpty) return;
    String? key;
    final target = widget.highlightPackage?.trim().toLowerCase();
    if (target != null && target.isNotEmpty) {
      for (final i in all) {
        if (i.name.toLowerCase() == target || i.bookingName.toLowerCase() == target) {
          key = i.key;
          break;
        }
      }
    }
    key ??= _item(_kCombo) != null ? _kCombo : all.first.key;
    _selectedKey = key;
    if (!_wheelChoices.contains(_wheels)) {
      _wheels = _wheelChoices.isEmpty ? 4 : _wheelChoices.last;
    }
  }

  void _select(String key) {
    if (_selectedKey == key) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedKey = key);
  }

  void _setWheels(int n) {
    if (_wheels == n) return;
    HapticFeedback.selectionClick();
    setState(() => _wheels = n);
  }

  // ── Actions ────────────────────────────────────────────────────────
  void _book() {
    final item = _bookingItem;
    if (item == null || !item.isDirectlyPayable) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          title: item.name,
          duration: item.duration,
          vehicleId: _vehicleId,
          serviceKeys: [item.key],
        ),
      ),
    );
  }

  Future<void> _call() async {
    await launchUrl(ContactSettings.telUri());
  }

  /// Tyre change is quote-based (no fixed price), so it goes to WhatsApp.
  Future<void> _requestTyreQuote() async {
    final details = [
      if (_tyreBrand != null) 'Brand: $_tyreBrand',
      if (_wheelSize != null) 'Wheel size: $_wheelSize"',
    ].join(', ');
    final message = details.isEmpty
        ? "Hi, I'd like a quote for a tyre change."
        : "Hi, I'd like a quote for a tyre change. $details.";
    final uri = Uri.parse(ContactSettings.whatsappUrl(message));
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open WhatsApp. Please try again.')),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return CatalogGate(builder: (context) {
      if (_wheelOptions.isEmpty && _otherOptions.isEmpty) return const CatalogEmpty();
      if (_selectedKey == null || _item(_selectedKey!) == null) _applyInitialSelection();

      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: AppColors.ink,
          body: Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHero(),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _FadeSlideIn(index: 0, child: _buildWheelOptions()),
                            if (_otherOptions.isNotEmpty)
                              _FadeSlideIn(index: 1, child: _buildOtherOptions()),
                            _FadeSlideIn(index: 2, child: _buildTyreQuote()),
                            _FadeSlideIn(index: 3, child: _buildWhyReperi()),
                            const SizedBox(height: 130),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(left: 0, right: 0, bottom: 0, child: _buildBookBar()),
            ],
          ),
        ),
      );
    });
  }

  // ── HERO ───────────────────────────────────────────────────────────
  Widget _buildHero() {
    return Container(
      color: _heroGreen,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Semantics(
                    button: true,
                    label: 'Back',
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withOpacity(0.24)),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 40, height: 40, child: CustomPaint(painter: _WheelGlyph())),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'WHEEL CARE',
                style: TextStyle(color: _heroMint, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2),
              ),
              const SizedBox(height: 6),
              const Text(
                'Alignment & Balancing',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Computerized equipment, trained technicians and a digital report after every job.',
                style: TextStyle(color: Colors.white.withOpacity(0.74), fontSize: 13.5, height: 1.45),
              ),
              const SizedBox(height: 16),
              Container(height: 1, color: Colors.white.withOpacity(0.16)),
              const SizedBox(height: 12),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _HeroFact(value: '30–60 min', label: 'Turnaround')),
                  Expanded(child: _HeroFact(value: '4 wheels', label: 'Checked')),
                  Expanded(child: _HeroFact(value: 'Report', label: 'Before / after')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── WHEEL OPTIONS ──────────────────────────────────────────────────
  Widget _buildWheelOptions() {
    final combo = _item(_kCombo);
    final align = _item(_kAlign);
    final balance = _item(_kBalance);
    final perWheel = _perWheel;

    // "Bought separately" price for the combo: alignment + all 4 wheels.
    int? separate;
    if (combo?.price != null && align?.price != null && balance?.price != null) {
      separate = align!.price! + balance!.price!;
      if (separate <= combo!.price!) separate = null;
    }

    return Padding(
      key: _optionsKey,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeading(eyebrow: 'CHOOSE A SERVICE', title: 'What does your car need?'),
          if (combo != null)
            _OptionCard(
              item: combo,
              badge: 'BEST VALUE',
              subtitle: _symptomFor(combo),
              price: combo.priceText,
              strikePrice: separate == null ? null : formatRupees(separate),
              priceNote: separate == null ? null : 'Save ${formatRupees(separate - combo.price!)}',
              priceNoteIsSaving: true,
              selected: _selectedKey == _kCombo,
              onTap: () => _select(_kCombo),
              details: _features(combo),
            ),
          if (align != null)
            _OptionCard(
              item: align,
              subtitle: _symptomFor(align),
              price: align.priceText,
              priceNote: 'all 4 wheels',
              selected: _selectedKey == _kAlign,
              onTap: () => _select(_kAlign),
              details: _features(align),
            ),
          if (balance != null)
            _OptionCard(
              item: balance,
              subtitle: _symptomFor(balance),
              price: perWheel != null ? formatRupees(perWheel) : balance.priceText,
              priceNote: perWheel != null ? 'per wheel' : 'all 4 wheels',
              selected: _selectedKey == _kBalance,
              onTap: () => _select(_kBalance),
              details: _balanceDetails(balance, perWheel),
            ),
          // Nudge from balancing up to the combo.
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: (_selectedKey == _kBalance && combo?.price != null)
                ? _UpgradeNudge(
                    text: 'All 4 wheels + alignment for ',
                    price: combo!.priceText,
                    onTap: () => _select(_kCombo),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  String _symptomFor(CatalogItem item) =>
      item.displayText('wheel_care', 'symptom', _symptoms[item.key] ?? item.tagline);

  bool _hasExtraCharge(CatalogItem item) =>
      item.displayBool('tyre_care', 'has_extra_charge', item.detailBool('has_extra_charge'));

  /// Feature list without the "extra charges" line (that's shown as a note).
  List<String> _featureLines(CatalogItem item) => item
      .displayFeatures('tyre_care')
      .where((f) => !f.toLowerCase().contains('extra charge'))
      .toList();

  Widget _features(CatalogItem item) {
    final lines = _featureLines(item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in lines) _CheckLine(text: f),
        if (_hasExtraCharge(item)) const _ExtraChargeNote(),
        if (item.duration.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 14, color: AppColors.mut),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Takes about ${item.duration}',
                    style: TextStyle(color: AppColors.mut, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _balanceDetails(CatalogItem balance, int? perWheel) {
    final choices = _wheelChoices;
    final current = _item(_balanceKey(_wheels));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (choices.length > 1) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'How many wheels?',
                  style: TextStyle(color: AppColors.txt, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              if (perWheel != null)
                Text(
                  '${formatRupees(perWheel)} each',
                  style: TextStyle(color: AppColors.mut, fontSize: 12.5),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _WheelPicker(choices: choices, selected: _wheels, onChanged: _setWheels),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  perWheel != null
                      ? '$_wheels ${_wheels == 1 ? 'wheel' : 'wheels'} × ${formatRupees(perWheel)}'
                      : '$_wheels ${_wheels == 1 ? 'wheel' : 'wheels'}',
                  style: TextStyle(color: AppColors.mut, fontSize: 12.5),
                ),
              ),
              _AnimatedPrice(
                text: current?.priceText ?? balance.priceText,
                style: TextStyle(color: AppColors.txt, fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: AppColors.line),
          const SizedBox(height: 10),
        ],
        _features(balance),
      ],
    );
  }

  // ── OTHER TYRE CARE ────────────────────────────────────────────────
  Widget _buildOtherOptions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeading(eyebrow: 'MORE TYRE CARE', title: 'Other services'),
          for (final item in _otherOptions)
            _OptionCard(
              item: item,
              subtitle: item.displayText('tyre_care', 'description', item.tagline),
              price: item.priceText,
              priceNote: item.duration.isEmpty ? null : item.duration,
              selected: _selectedKey == item.key,
              onTap: () => _select(item.key),
              details: _features(item),
            ),
        ],
      ),
    );
  }

  // ── TYRE CHANGE QUOTE ──────────────────────────────────────────────
  Widget _buildTyreQuote() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: _greenSoft, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.tire_repair_rounded, color: _green, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Need new tyres?',
                        style: TextStyle(color: AppColors.txt, fontSize: 15.5, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Pick a brand and size — we'll WhatsApp you a quote",
                        style: TextStyle(color: AppColors.mut, fontSize: 12.5, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _smallLabel('Brand'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in _tyreBrands)
                  _Chip(
                    label: b,
                    selected: _tyreBrand == b,
                    onTap: () => setState(() => _tyreBrand = _tyreBrand == b ? null : b),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _smallLabel('Wheel size'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _wheelSizes)
                  _Chip(
                    label: '$s"',
                    selected: _wheelSize == s,
                    onTap: () => setState(() => _wheelSize = _wheelSize == s ? null : s),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _requestTyreQuote,
              style: OutlinedButton.styleFrom(
                foregroundColor: _green,
                side: BorderSide(color: _green, width: 1.4),
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                'Get my quote on WhatsApp',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallLabel(String text) => Text(
        text,
        style: TextStyle(color: AppColors.txt, fontSize: 13, fontWeight: FontWeight.w600),
      );

  // ── WHY REPERI ─────────────────────────────────────────────────────
  Widget _buildWhyReperi() {
    const items = [
      (Icons.gps_fixed_rounded, 'Computerized alignment'),
      (Icons.speed_rounded, 'High-speed balancing'),
      (Icons.description_outlined, 'Before / after report'),
      (Icons.my_location_rounded, 'Live tracking'),
    ];
    Widget tile((IconData, String) t) => Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Icon(t.$1, color: _green, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t.$2,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.txt, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3),
                ),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeading(eyebrow: 'WHY REPERI', title: 'Done right, every time'),
          for (var r = 0; r < items.length; r += 2) ...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tile(items[r])),
                  const SizedBox(width: 10),
                  Expanded(child: r + 1 < items.length ? tile(items[r + 1]) : const SizedBox()),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  // ── BOOK BAR ───────────────────────────────────────────────────────
  Widget _buildBookBar() {
    final item = _bookingItem;
    final canBook = item != null && item.isDirectlyPayable;
    final label = item == null ? 'Choose a service' : item.name;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        label,
                        key: ValueKey(label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.mut, fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 2),
                    _AnimatedPrice(
                      text: item?.priceText ?? '',
                      style: TextStyle(
                        color: AppColors.txt,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: 'Call us',
                child: InkWell(
                  onTap: _call,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Icon(Icons.call_outlined, color: _green, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: canBook ? 1 : 0.5,
                child: Material(
                  color: _green,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: canBook ? _book : null,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 128, minHeight: 48),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Book now',
                              style: TextStyle(color: _onGreen, fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward_rounded, color: _onGreen, size: 18),
                          ],
                        ),
                      ),
                    ),
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

// ═════════════════════════════════════════════════════════════════════
// Building blocks
// ═════════════════════════════════════════════════════════════════════

class _HeroFact extends StatelessWidget {
  const _HeroFact({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withOpacity(0.62), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.eyebrow, required this.title});
  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: TextStyle(color: AppColors.mut, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.6),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(color: AppColors.txt, fontSize: 18, fontWeight: FontWeight.w800, height: 1.2),
          ),
        ],
      ),
    );
  }
}

/// A selectable service row. Selected: green border + radio, and the
/// [details] slide open underneath.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.item,
    required this.subtitle,
    required this.price,
    required this.selected,
    required this.onTap,
    required this.details,
    this.badge,
    this.strikePrice,
    this.priceNote,
    this.priceNoteIsSaving = false,
  });

  final CatalogItem item;
  final String subtitle;
  final String price;
  final bool selected;
  final VoidCallback onTap;
  final Widget details;
  final String? badge;
  final String? strikePrice;
  final String? priceNote;
  final bool priceNoteIsSaving;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        selected: selected,
        button: true,
        label: '${item.name}, $price',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? _green : AppColors.line,
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _Radio(selected: selected),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (badge != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: _greenLine),
                                ),
                                child: Text(
                                  badge!,
                                  style: TextStyle(
                                    color: _green,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                            ],
                            Text(
                              item.name,
                              style: TextStyle(
                                color: AppColors.txt,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: AppColors.mut, fontSize: 12.5, height: 1.3),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 104),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (strikePrice != null)
                              Text(
                                strikePrice!,
                                style: TextStyle(
                                  color: AppColors.mut,
                                  fontSize: 11.5,
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: AppColors.mut,
                                ),
                              ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                price,
                                style: TextStyle(
                                  color: AppColors.txt,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            if (priceNote != null)
                              Text(
                                priceNote!,
                                textAlign: TextAlign.right,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: priceNoteIsSaving ? _green : AppColors.mut,
                                  fontSize: 11,
                                  fontWeight: priceNoteIsSaving ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Details slide open when selected.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: selected
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(height: 1, color: AppColors.line),
                                const SizedBox(height: 12),
                                _FadeIn(child: details),
                              ],
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
          ),
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
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? _green : AppColors.txt.withOpacity(0.28),
          width: selected ? 6 : 1.6,
        ),
      ),
    );
  }
}

class _CheckLine extends StatelessWidget {
  const _CheckLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.check_circle_outline_rounded, color: _green, size: 16),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: AppColors.txt, fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtraChargeNote extends StatelessWidget {
  const _ExtraChargeNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, size: 14, color: AppColors.mut),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Wheel weights may cost up to ₹200 extra, depending on your tyres.',
              style: TextStyle(color: AppColors.mut, fontSize: 11.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// 1 | 2 | 3 | 4 segmented picker.
class _WheelPicker extends StatelessWidget {
  const _WheelPicker({required this.choices, required this.selected, required this.onChanged});
  final List<int> choices;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          for (final n in choices)
            Expanded(
              child: Semantics(
                button: true,
                selected: n == selected,
                label: '$n ${n == 1 ? 'wheel' : 'wheels'}',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(n),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: n == selected ? _green : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$n',
                      style: TextStyle(
                        color: n == selected ? _onGreen : AppColors.txt,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UpgradeNudge extends StatelessWidget {
  const _UpgradeNudge({required this.text, required this.price, required this.onTap});
  final String text;
  final String price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: _greenSoft,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _greenLine),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: text,
                      children: [
                        TextSpan(text: price, style: TextStyle(color: _green, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    style: TextStyle(color: AppColors.txt, fontSize: 12.5, height: 1.3),
                  ),
                ),
                const SizedBox(width: 10),
                Text('Switch', style: TextStyle(color: _green, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(width: 2),
                Icon(Icons.arrow_forward_rounded, color: _green, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? _green : AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: selected ? _green : AppColors.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? _onGreen : AppColors.txt,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Price text that slides/fades to its new value.
class _AnimatedPrice extends StatelessWidget {
  const _AnimatedPrice({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, if (current != null) current],
      ),
      child: Text(
        text,
        key: ValueKey(text),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

/// Fades content in when it first appears (used inside opening cards).
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(opacity: v, child: child),
      child: child,
    );
  }
}

/// Fades + rises a section into place, staggered by [index].
class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + index * 90),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, (1 - value) * 18), child: child),
      ),
      child: child,
    );
  }
}

/// Small line-drawn wheel in the hero.
class _WheelGlyph extends CustomPainter {
  const _WheelGlyph();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final outer = Paint()
      ..color = _heroMint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final thin = Paint()
      ..color = _heroMint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(c, r - 2, outer);
    canvas.drawCircle(c, r * 0.45, thin);
    canvas.drawLine(c.translate(0, -r * 0.45), c.translate(0, r * 0.45), thin);
    canvas.drawLine(c.translate(-r * 0.45, 0), c.translate(r * 0.45, 0), thin);
  }

  @override
  bool shouldRepaint(covariant _WheelGlyph oldDelegate) => false;
}
