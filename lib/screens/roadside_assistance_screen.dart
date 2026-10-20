import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../services/geocoding_bridge.dart';
import '../widgets/web_location_permission.dart';
import 'package:url_launcher/url_launcher.dart';
import 'payment_screen.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../services/catalog_service.dart';

class RoadsideAssistanceScreen extends StatefulWidget {
  /// This screen represents a single service with no sub-packages to
  /// select between, so there's nothing further to highlight — accepted
  /// only so callers that pass it (see buildPackageScreenFor) compile.
  final String? highlightPackage;

  const RoadsideAssistanceScreen({super.key, this.highlightPackage});

  @override
  State<RoadsideAssistanceScreen> createState() =>
      _RoadsideAssistanceScreenState();
}

class _RoadsideAssistanceScreenState
    extends State<RoadsideAssistanceScreen> with TickerProviderStateMixin {

  // ── Look ──
  static const Color _red = Color(0xFFE5484D);
  static const Color _redDeep = Color(0xFFB3141A);

  /// The issue the customer tapped (null = not picked yet → "General
  /// Assistance" is booked).
  _Issue? _selected;

  /// Slow beacon pulse in the header.
  late final AnimationController _beacon =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  /// One-time entrance (tiles fade/slide in one by one).
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  String address = "Detecting location...";

  // Website only: true when our own location prompt / "unblock" steps were
  // just shown, so Book Now doesn't stack the generic "Sorry" dialog on top.
  bool _webLocationDialogShown = false;

  @override
  void initState() {
    super.initState();
    _getLocation();
    // AppColors' fields are mutated in place by themeController, not routed
    // through an InheritedWidget — nothing marks this screen dirty on its
    // own when the toggle flips, so it must listen and rebuild itself.
    themeController.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    _beacon.dispose();
    _intro.dispose();
    super.dispose();
  }

  bool get _isDetecting => address == "Detecting location...";

  bool get _isLocationDetected =>
      address != "Detecting location..." && address != "Location unavailable";

  Future<void> _getLocation() async {
    if (mounted && address != "Detecting location...") {
      setState(() => address = "Detecting location...");
    }
    try {
      // Web (especially Safari) doesn't reliably support the Permissions
      // API that checkPermission()/requestPermission() depend on, so the
      // website uses its own soft-ask (askForWebLocation) and then
      // getCurrentPosition(), which shows the browser's native "Allow
      // location" popup; a denial throws an error we catch below.
      if (!kIsWeb) {
        LocationPermission permission =
            await Geolocator.checkPermission();

        if (permission == LocationPermission.denied) {
          permission =
              await Geolocator.requestPermission();
        }

        if (permission ==
                LocationPermission.denied ||
            permission ==
                LocationPermission.deniedForever) {
          if (!mounted) return;
          setState(() {
            address = "Location unavailable";
          });
          return;
        }
      } else {
        // Website: our own "Use your location?" prompt first (or unblock
        // steps if the browser has blocked it). Apps never reach this.
        _webLocationDialogShown = false;
        final goAhead = await askForWebLocation(context);
        if (!goAhead) {
          _webLocationDialogShown = true;
          if (!mounted) return;
          setState(() {
            address = "Location unavailable";
          });
          return;
        }
      }

      final position =
          await Geolocator.getCurrentPosition(
        desiredAccuracy:
            LocationAccuracy.high,
      );

      final placemarks =
          await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      final place = placemarks.first;

      if (!mounted) return;
      setState(() {
        address =
            "${place.locality}, ${place.administrativeArea}";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        address = "Location unavailable";
      });
      // Website: the browser refused location -> show how to turn it on.
      if (kIsWeb && e is PermissionDeniedException) {
        _webLocationDialogShown = true;
        await showWebLocationBlockedHelp(context);
      }
    }
  }

  Future<void> _callSupport() async {
    final uri = Uri(scheme: 'tel', path: '9353094672');
    await launchUrl(uri);
  }

  // Called when "BOOK NOW" is tapped — either from a specific service card,
  // or from the generic "General Assistance" button at the bottom of the
  // main screen.
  // - If location is already detected, goes straight to the base-pay popup.
  // - If not, tries to detect it again.
  // - If it's still not detected after that retry, shows a "can't detect
  //   your location" message instead of proceeding.
  Future<void> _handleBookNow(String issueTitle) async {
    // The base fare shown below comes from the services table.
    try {
      await CatalogService.ensureLoaded();
    } catch (_) {}
    if (!_isLocationDetected) {
      await _getLocation();
    }

    if (!mounted) return;

    if (!_isLocationDetected) {
      // Website: our own prompt/unblock steps were already shown.
      if (kIsWeb && _webLocationDialogShown) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surfaceRaised,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Sorry! Cannot detect your location',
            style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Please enable location access and try again.',
            style: TextStyle(color: AppColors.txt.withOpacity(0.7)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Color(0xFFD4A017))),
            ),
          ],
        ),
      );
      return;
    }

    // Location is detected — show the base-pay notice before proceeding.
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Base Fare',
          style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w900),
        ),
        content: Text(
          'Base pay is ${CatalogService.byKey('roadside_assistance')?.priceText ?? ''}. Additional charges will apply based on distance and service required.',
          style: TextStyle(color: AppColors.txt.withOpacity(0.7), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL', style: TextStyle(color: AppColors.mut)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4A017),
            ),
            onPressed: () {
              Navigator.pop(context); // close this dialog
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PaymentScreen(
                    title: 'Roadside Assistance - $issueTitle',
                    duration: CatalogService.byKey('roadside_assistance')?.duration ?? 'On-demand',
                    vehicleId: '',
                    vehicleRequired: false,
                    // The server routes this to the emergency technician
                    // (services.admin_pool = garage_emergency), always adds
                    // the doorstep fee (pickup_mode = locked) and assigns no
                    // separate delivery partner — the technician fixes it
                    // on the spot.
                    serviceKeys: const ['roadside_assistance'],
                    bookingOptions: {'label': issueTitle},
                  ),
                ),
              );
            },
            child: Text('CONTINUE',
                style: TextStyle(color: AppColors.onAccentDark, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  UI
  // ════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _hero()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _reveal(0, _locationCard()),
                    const SizedBox(height: 24),
                    _reveal(1, _sectionTitle('What happened?', 'Tap the closest match — our technician comes prepared.')),
                    const SizedBox(height: 14),
                    _issueGrid(),
                    const SizedBox(height: 26),
                    _reveal(8, _sectionTitle('How it works', null)),
                    const SizedBox(height: 12),
                    _reveal(9, _howItWorks()),
                    const SizedBox(height: 18),
                    _reveal(10, _fareNote()),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  /// Staggered fade + slide-up entrance.
  Widget _reveal(int i, Widget child) {
    return AnimatedBuilder(
      animation: _intro,
      builder: (context, c) {
        final start = (i * 0.06).clamp(0.0, 0.7);
        final t = Curves.easeOutCubic.transform(((_intro.value - start) / 0.3).clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: c),
        );
      },
      child: child,
    );
  }

  // ── Header ──────────────────────────────────────────────────────────
  Widget _hero() {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(8, top + 6, 18, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A0B0E), Color(0xFF1A0607)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _red.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _red.withOpacity(0.5)),
                        ),
                        child: const Text('ROADSIDE ASSISTANCE · 24×7',
                            style: TextStyle(
                                color: Color(0xFFFF8A8E), fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      ),
                      const SizedBox(height: 12),
                      const Text('Stuck on the road?',
                          style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, height: 1.1)),
                      const SizedBox(height: 8),
                      Text("Tell us what happened — a technician comes to you and fixes it on the spot.",
                          style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 14, height: 1.4)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _beaconIcon(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Pulsing red beacon.
  Widget _beaconIcon() {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      width: 84,
      height: 84,
      child: AnimatedBuilder(
        animation: _beacon,
        builder: (context, _) {
          final v = reduceMotion ? 0.0 : _beacon.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              for (final d in const [0.0, 0.5])
                Builder(builder: (_) {
                  final p = (v + d) % 1.0;
                  return Container(
                    width: 44 + 40 * p,
                    height: 44 + 40 * p,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _red.withOpacity(0.55 * (1 - p)), width: 2),
                    ),
                  );
                }),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(colors: [Color(0xFFFF7A7E), _red, _redDeep], stops: [0, 0.6, 1]),
                  boxShadow: [BoxShadow(color: _red.withOpacity(0.5), blurRadius: 18)],
                ),
                child: const Icon(Icons.car_crash_rounded, color: Colors.white, size: 26),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Location ────────────────────────────────────────────────────────
  Widget _locationCard() {
    final ok = _isLocationDetected;
    final detecting = _isDetecting;
    final statusColor = ok ? const Color(0xFF2FB36A) : (detecting ? AppColors.accent : _red);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ok ? statusColor.withOpacity(0.4) : AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: statusColor.withOpacity(0.14), shape: BoxShape.circle),
            child: detecting
                ? Padding(
                    padding: const EdgeInsets.all(11),
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: statusColor),
                  )
                : Icon(ok ? Icons.my_location_rounded : Icons.location_off_rounded, color: statusColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ok ? 'Help will come here' : (detecting ? 'Finding you…' : "We couldn't find your location"),
                  style: TextStyle(color: AppColors.mut, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  ok ? address : (detecting ? 'Getting your location' : 'Turn on location and tap Retry'),
                  style: TextStyle(color: AppColors.txt, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          if (!detecting)
            TextButton(
              onPressed: _getLocation,
              child: Text(ok ? 'Refresh' : 'Retry',
                  style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String? sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: AppColors.txt, fontSize: 20, fontWeight: FontWeight.w900)),
        if (sub != null) ...[
          const SizedBox(height: 4),
          Text(sub, style: TextStyle(color: AppColors.mut, fontSize: 13, height: 1.35)),
        ],
      ],
    );
  }

  // ── Issues ──────────────────────────────────────────────────────────
  Widget _issueGrid() {
    return LayoutBuilder(builder: (context, c) {
      // Two per row; one per row on very narrow screens / very large text.
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final cols = (c.maxWidth / scale) < 330 ? 1 : 2;
      const gap = 12.0;
      // Rows of [cols] tiles; tiles in a row share the tallest one's height.
      final rows = <Widget>[];
      for (var start = 0; start < _kIssues.length; start += cols) {
        final cells = <Widget>[];
        for (var k = 0; k < cols; k++) {
          final i = start + k;
          if (k > 0) cells.add(const SizedBox(width: gap));
          cells.add(Expanded(
            child: i < _kIssues.length ? _reveal(2 + i, _issueTile(_kIssues[i])) : const SizedBox(),
          ));
        }
        if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
        rows.add(IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells),
        ));
      }
      return Column(children: rows);
    });
  }

  Widget _issueTile(_Issue issue) {
    final on = _selected == issue;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selected = on ? null : issue);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: on ? _red.withOpacity(0.10) : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: on ? _red : AppColors.line, width: on ? 1.8 : 1),
          boxShadow: on ? [BoxShadow(color: _red.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 6))] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: issue.color.withOpacity(0.16), borderRadius: BorderRadius.circular(14)),
                  child: Icon(issue.icon, color: issue.color, size: 24),
                ),
                const Spacer(),
                AnimatedScale(
                  scale: on ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(color: _red, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(issue.title, style: TextStyle(color: AppColors.txt, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(issue.hint, style: TextStyle(color: AppColors.mut, fontSize: 12, height: 1.3)),
          ],
        ),
      ),
    );
  }

  // ── How it works ────────────────────────────────────────────────────
  Widget _howItWorks() {
    const steps = [
      (Icons.touch_app_rounded, 'Book', 'Pick the problem and confirm'),
      (Icons.engineering_rounded, 'We dispatch', 'Nearest technician heads to you'),
      (Icons.verified_rounded, 'Back on the road', 'Fixed on the spot, or towed'),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.15), shape: BoxShape.circle),
                      child: Icon(steps[i].$1, color: AppColors.accent, size: 18),
                    ),
                    if (i < steps.length - 1)
                      Container(width: 2, height: 18, margin: const EdgeInsets.symmetric(vertical: 3), color: AppColors.line),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(steps[i].$2,
                            style: TextStyle(color: AppColors.txt, fontSize: 14, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(steps[i].$3, style: TextStyle(color: AppColors.mut, fontSize: 12.5, height: 1.3)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _fareNote() {
    final price = CatalogService.byKey('roadside_assistance')?.priceText ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              price.isEmpty
                  ? 'You pay a base fare to book. Extra charges depend on distance and the work needed — our technician tells you before starting.'
                  : 'Base fare $price to book. Extra charges depend on distance and the work needed — our technician tells you before starting.',
              style: TextStyle(color: AppColors.txt, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom bar ──────────────────────────────────────────────────────
  Widget _bottomBar() {
    final label = _selected == null ? 'Get help now' : 'Get help · ${_selected!.title}';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border(top: BorderSide(color: AppColors.line)),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              // Call
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _callSupport,
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.call_rounded, color: Color(0xFF2FB36A), size: 22),
                        const SizedBox(width: 6),
                        Text('Call', style: TextStyle(color: AppColors.txt, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Get help
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      _handleBookNow(_selected?.title ?? 'General Assistance');
                    },
                    child: Ink(
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(colors: [Color(0xFFFF5A5F), _red, _redDeep]),
                        boxShadow: [BoxShadow(color: _red.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Text(
                                  label,
                                  key: ValueKey(label),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
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

/// One "What happened?" option. [title] is what gets saved on the booking.
class _Issue {
  const _Issue(this.title, this.hint, this.icon, this.color);
  final String title;
  final String hint;
  final IconData icon;
  final Color color;
}

const List<_Issue> _kIssues = [
  _Issue('Flat Tyre', 'Puncture or burst — we fix or fit the spare', Icons.tire_repair_rounded, Color(0xFF4FA3E3)),
  _Issue('Dead Battery', "Won't start — jump-start or battery help", Icons.battery_alert_rounded, Color(0xFF2FB36A)),
  _Issue('Out Of Fuel', 'We bring enough fuel to reach a pump', Icons.local_gas_station_rounded, Color(0xFFF0A020)),
  _Issue('Towing', 'Vehicle moved safely to a garage', Icons.local_shipping_rounded, Color(0xFF9B7BFF)),
  _Issue('Breakdown', 'Engine trouble or any other fault', Icons.build_rounded, Color(0xFFE3B23C)),
  _Issue('Accident', 'Minor damage? We help you get moving', Icons.warning_amber_rounded, Color(0xFFE5484D)),
];
