import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';

const String kEmergencySupportNumber = '9353094672';

/// Package-name prefix every Roadside Assistance booking is saved under
/// (see roadside_assistance_screen.dart) — the only marker distinguishing
/// an emergency booking from an ordinary one in the `bookings` table.
const String kEmergencyPackagePrefix = 'Roadside Assistance';

/// Public Indian emergency numbers shown in the help sheet.
const List<({String label, String number, IconData icon})> _kEmergencyContacts = [
  (label: 'National Emergency', number: '112', icon: Symbols.emergency),
  (label: 'Police', number: '100', icon: Symbols.local_police),
  (label: 'Ambulance', number: '108', icon: Symbols.local_hospital),
  (label: 'Ambulance (Patient Transport)', number: '102', icon: Symbols.medical_services),
  (label: 'Fire', number: '101', icon: Symbols.local_fire_department),
  (label: 'Women Helpline', number: '1091', icon: Symbols.woman),
  (label: 'Women Helpline (Domestic Abuse)', number: '181', icon: Symbols.support_agent),
  (label: 'Child Helpline', number: '1098', icon: Symbols.child_care),
  (label: 'Road Accident Emergency', number: '1073', icon: Symbols.car_crash),
  (label: 'Highway Helpline (NHAI)', number: '1033', icon: Symbols.add_road),
];

Future<void> _dial(String number) async {
  await launchUrl(Uri(scheme: 'tel', path: number));
}

/// Wraps a screen's body and floats [EmergencyStatusBanner] over its
/// bottom edge — used by the screens whose Scaffold shows the shared
/// BottomNavBar (the banner sits just above that bar, clear of the
/// docked "Ask AI" button).
class EmergencyBannerOverlay extends StatelessWidget {
  const EmergencyBannerOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 42,
          child: EmergencyStatusBanner(),
        ),
      ],
    );
  }
}

/// A red "Emergency assistance is on the way" pill, shown only while the
/// signed-in customer has an open Roadside Assistance booking. Tapping it
/// opens a sheet with a call-us button and national emergency numbers.
class EmergencyStatusBanner extends StatefulWidget {
  const EmergencyStatusBanner({super.key});

  @override
  State<EmergencyStatusBanner> createState() => _EmergencyStatusBannerState();
}

class _EmergencyStatusBannerState extends State<EmergencyStatusBanner>
    with TickerProviderStateMixin {
  /// An emergency booking older than this is treated as over even if
  /// nobody ever marked it completed, so the banner can't stick forever.
  static const Duration _maxAge = Duration(hours: 24);

  static const Set<String> _closedStatuses = {
    'completed',
    'cancelled',
    'canceled',
    'rejected',
    'delivered',
  };

  // ── Geometry ──────────────────────────────────────────────────────────
  static const double _sideInset = 16; // gap from screen edges
  static const double _pillHeight = 66;
  static const double _circleSize = 56;
  static const double _pillRadius = 22;

  /// How far (px) the finger has to travel for a full pill → circle morph.
  static const double _dragDistance = 150;

  /// Shared spring for every snap — critically-ish damped so it settles
  /// with a soft, premium overshoot rather than a bounce.
  static final SpringDescription _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 240,
    ratio: 0.82,
  );

  // ── Collapsed state, shared by every banner instance ──────────────────
  // Home, Services, Profile and Bookings each mount their own banner, so
  // the collapsed choice lives here (and in SharedPreferences) rather than
  // in one instance — tuck it away once and it stays tucked everywhere,
  // even after an app restart. It's keyed to the booking id, so a NEW
  // emergency booking always starts as the full, unmissable pill.
  static const String _prefsKey = 'emergency_banner_collapsed_booking';
  static final ValueNotifier<String?> _collapsedBookingId =
      ValueNotifier<String?>(null);
  static bool _prefsLoaded = false;

  static Future<void> _loadCollapsedPref() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _collapsedBookingId.value = prefs.getString(_prefsKey);
    } catch (_) {}
  }

  static Future<void> _saveCollapsedPref(String? bookingId) async {
    _collapsedBookingId.value = bookingId;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (bookingId == null) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, bookingId);
      }
    } catch (_) {}
  }

  /// Slow, calm glow — the old 1.1 s pulse read as an alarm.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  /// 0 = full pill, 1 = corner circle. Unbounded so the spring can
  /// overshoot a hair and settle, which is what makes it feel physical.
  late final AnimationController _morph = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  Timer? _poll;
  bool _active = false;
  bool _pressed = false;
  bool _crossedThreshold = false;

  /// The open booking's id, and whether the technician has already tapped
  /// "mark as done" (which generates the completion OTP the customer types
  /// in below).
  String? _bookingId;
  bool _otpRequested = false;

  bool get _isCollapsed =>
      _bookingId != null && _collapsedBookingId.value == _bookingId;

  @override
  void initState() {
    super.initState();
    _collapsedBookingId.addListener(_onSharedCollapseChanged);
    _loadCollapsedPref().then((_) => _syncToSharedState(animate: false));
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
    // AppColors are swapped in place on a light/dark toggle — rebuild so
    // the banner follows the theme like every other screen does.
    themeController.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  /// Another screen's banner collapsed/expanded — follow it.
  void _onSharedCollapseChanged() => _syncToSharedState(animate: true);

  void _syncToSharedState({required bool animate}) {
    if (!mounted) return;
    final target = _isCollapsed ? 1.0 : 0.0;
    if ((_morph.value - target).abs() < 0.001 || _morph.isAnimating) return;
    if (animate && _active) {
      _springTo(target);
    } else {
      _morph.value = target;
    }
  }

  @override
  void dispose() {
    _collapsedBookingId.removeListener(_onSharedCollapseChanged);
    themeController.removeListener(_onThemeChanged);
    _poll?.cancel();
    _pulse.dispose();
    _morph.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final rows = List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('bookings')
            .select(
                'id, booking_status, created_at, return_otp_generated_at, return_otp_verified_at')
            .eq('user_id', user.id)
            .ilike('package_name', '$kEmergencyPackagePrefix%')
            .order('created_at', ascending: false)
            .limit(5),
      );
      final now = DateTime.now();
      Map<String, dynamic>? open;
      for (final r in rows) {
        final status = (r['booking_status'] ?? '').toString().toLowerCase();
        if (_closedStatuses.contains(status)) continue;
        if (r['return_otp_verified_at'] != null) continue;
        final created = DateTime.tryParse((r['created_at'] ?? '').toString());
        if (created == null || now.difference(created) >= _maxAge) continue;
        open = r;
        break;
      }
      if (!mounted) return;
      final active = open != null;
      final otpRequested = open?['return_otp_generated_at'] != null;
      final bookingId = open?['id']?.toString();
      if (active != _active ||
          otpRequested != _otpRequested ||
          bookingId != _bookingId) {
        setState(() {
          _active = active;
          _otpRequested = otpRequested;
          _bookingId = bookingId;
        });
        // A different (or no) booking: jump straight to whatever that
        // booking's saved state is — no animation on first appearance.
        _morph.value = _isCollapsed ? 1.0 : 0.0;
      }
    } catch (_) {
      // Non-fatal — keep whatever the banner showed last.
    }
  }

  void _openSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EmergencyHelpSheet(
        bookingId: _bookingId,
        otpRequested: _otpRequested,
        onVerified: _refresh,
      ),
    );
  }

  // ── Motion ───────────────────────────────────────────────────────────

  void _springTo(double target, {double velocity = 0}) {
    _morph.animateWith(
      SpringSimulation(_spring, _morph.value, target, velocity),
    );
  }

  void _collapse({double velocity = 0}) {
    HapticFeedback.lightImpact();
    _springTo(1, velocity: velocity);
    _saveCollapsedPref(_bookingId);
  }

  void _expand({double velocity = 0}) {
    HapticFeedback.lightImpact();
    _springTo(0, velocity: velocity);
    _saveCollapsedPref(null);
  }

  void _onDragStart(DragStartDetails _) {
    _morph.stop();
    _crossedThreshold = false;
    setState(() => _pressed = false);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // Follows the finger 1:1 between the two states, then turns heavy
    // past either end (rubber-band) so it feels weighted, not loose.
    final delta = (d.primaryDelta ?? 0) / _dragDistance;
    final v = _morph.value;
    final outside = (v < 0 && delta < 0) || (v > 1 && delta > 0);
    _morph.value = (v + (outside ? delta * 0.25 : delta)).clamp(-0.08, 1.08);
    // One soft tick the moment the gesture has gone far enough to commit.
    final past = _morph.value > 0.5;
    if (past != _crossedThreshold) {
      _crossedThreshold = past;
      HapticFeedback.selectionClick();
    }
  }

  void _onDragEnd(DragEndDetails d) {
    final v = (d.primaryVelocity ?? 0) / _dragDistance; // units per second
    final shouldCollapse = v > 1.2 || (v > -1.2 && _morph.value > 0.35);
    if (shouldCollapse) {
      _collapse(velocity: v);
    } else {
      _expand(velocity: v);
    }
  }

  void _onTap() {
    if (_morph.value > 0.5) {
      // Circle → grow back into the pill (no sheet yet).
      _expand();
    } else {
      _openSheet();
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_active) return const SizedBox.shrink();
    // Dark mode keeps the original look exactly. Light mode swaps the
    // near-black red pill and white text for a soft red-tinted card with
    // the theme's own dark text, so it reads correctly on a light screen.
    final isDark = AppColors.isDark;
    final glow = isDark ? const Color(0xFFFF4D57) : const Color(0xFFD92D3A);
    final bgColors = isDark
        ? [
            const Color(0xFF1B0B0D).withOpacity(0.92),
            const Color(0xFF120607).withOpacity(0.96),
          ]
        : [
            const Color(0xFFFFF1F2).withOpacity(0.96),
            const Color(0xFFFFE3E5).withOpacity(0.98),
          ];
    final dropShadow = Colors.black.withOpacity(isDark ? 0.35 : 0.10);

    return SizedBox(
      height: _pillHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fullWidth = constraints.maxWidth;
          final pillWidth = fullWidth - _sideInset * 2;
          final circleLeft = fullWidth - _sideInset - _circleSize;

          return AnimatedBuilder(
            animation: Listenable.merge([_morph, _pulse]),
            builder: (context, _) {
              final raw = _morph.value;
              final t = raw.clamp(0.0, 1.0);
              // Width/height ease in a little later than position so the
              // shape "gathers itself" before travelling to the corner.
              final sizeT = Curves.easeInOutCubic.transform(t);
              final moveT = Curves.easeInOutCubic.transform(t);

              final width = lerpDouble(pillWidth, _circleSize, sizeT)!;
              final height = lerpDouble(_pillHeight, _circleSize, sizeT)!;
              // Position uses the raw (overshooting) value so the circle
              // glides a hair past its spot and settles back.
              final left = lerpDouble(_sideInset, circleLeft,
                  moveT + (raw - t) * 0.6)!;
              final radius = lerpDouble(_pillRadius, _circleSize / 2, sizeT)!;
              // A gentle downward arc while morphing — reads as the pill
              // being "tucked down" into the corner.
              final dip = sin(pi * t) * 10;
              // Text leaves early on collapse and arrives late on expand.
              final textOpacity = (1 - t / 0.32).clamp(0.0, 1.0);
              final hPad = lerpDouble(14, (_circleSize - 42) / 2, sizeT)!;
              final pulse = _pulse.value;
              final pressScale = _pressed ? 0.965 : 1.0;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: left,
                    bottom: -dip,
                    width: width,
                    height: height,
                    child: AnimatedScale(
                      scale: pressScale,
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      child: Semantics(
                        button: true,
                        label: t > 0.5
                            ? 'Emergency assistance on the way. Tap to expand.'
                            : 'Emergency assistance is on the way. Tap for help and contacts. Swipe down to minimise.',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (_) => setState(() => _pressed = true),
                          onTapCancel: () => setState(() => _pressed = false),
                          onTapUp: (_) => setState(() => _pressed = false),
                          onTap: _onTap,
                          onVerticalDragStart: _onDragStart,
                          onVerticalDragUpdate: _onDragUpdate,
                          onVerticalDragEnd: _onDragEnd,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(radius),
                              boxShadow: [
                                BoxShadow(
                                  color: glow.withOpacity(0.14 + 0.12 * pulse),
                                  blurRadius: 24 + 10 * pulse,
                                  spreadRadius: 1 + pulse,
                                  offset: Offset(0, lerpDouble(10, 6, t)!),
                                ),
                                BoxShadow(
                                  color: dropShadow,
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(radius),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(radius),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: bgColors,
                                    ),
                                    border: Border.all(
                                      color: glow.withOpacity(isDark ? 0.55 : 0.45),
                                      width: 1.2,
                                    ),
                                  ),
                                  // Content is always laid out at full pill
                                  // width and simply clipped by the shrinking
                                  // shape — no overflow, no re-layout jank.
                                  child: OverflowBox(
                                    alignment: Alignment.centerLeft,
                                    minWidth: pillWidth,
                                    maxWidth: pillWidth,
                                    minHeight: height,
                                    maxHeight: height,
                                    // The row gets the shape's full height
                                    // (no vertical padding) and text size is
                                    // capped, so the 3-line text always fits.
                                    child: MediaQuery.withClampedTextScaling(
                                      maxScaleFactor: 1.0,
                                      child: Padding(
                                      padding: EdgeInsets.fromLTRB(
                                          hPad, 0, 14, 0),
                                      child: _PillContent(
                                        glow: glow,
                                        isDark: isDark,
                                        pulse: pulse,
                                        textOpacity: textOpacity,
                                        otpRequested: _otpRequested,
                                      ),
                                    ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// The pill's inner row: pulsing emergency icon, LIVE label, title,
/// subtitle and chevron. Only the icon survives into the circle — the rest
/// fades with [textOpacity].
class _PillContent extends StatelessWidget {
  const _PillContent({
    required this.glow,
    required this.isDark,
    required this.pulse,
    required this.textOpacity,
    required this.otpRequested,
  });

  final Color glow;
  final bool isDark;
  final double pulse;
  final double textOpacity;
  final bool otpRequested;

  @override
  Widget build(BuildContext context) {
    final titleColor = isDark ? Colors.white : AppColors.txt;
    final subtitleColor = isDark ? Colors.white.withOpacity(0.62) : AppColors.mut;
    final chevronBg = isDark ? Colors.white.withOpacity(0.06) : AppColors.txt.withOpacity(0.05);
    final chevronBorder = isDark ? Colors.white.withOpacity(0.10) : AppColors.line;
    final chevronIcon = isDark ? Colors.white70 : AppColors.mut;

    return Row(
      children: [
        SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 42 * (0.7 + 0.3 * pulse),
                height: 42 * (0.7 + 0.3 * pulse),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glow.withOpacity(0.30 * (1 - pulse)),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF5A63), Color(0xFFB3121E)],
                  ),
                  boxShadow: [
                    BoxShadow(color: glow.withOpacity(0.5), blurRadius: 10),
                  ],
                ),
                child: const Icon(Symbols.emergency,
                    color: Colors.white, size: 18, weight: 600),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Opacity(
            opacity: textOpacity,
            child: Transform.translate(
              // Text drifts slightly left as it fades, so it feels pulled
              // into the icon rather than just vanishing.
              offset: Offset(-12 * (1 - textOpacity), 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: glow,
                          boxShadow: [
                            BoxShadow(color: glow.withOpacity(0.8), blurRadius: 5),
                          ],
                        ),
                      ),
                      Text(
                        'LIVE',
                        style: GoogleFonts.manrope(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                          color: glow,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Emergency assistance is on the way',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.1,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    otpRequested
                        ? 'Work finished · tap to enter your OTP'
                        : 'Tap for help · swipe down to minimise',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Opacity(
          opacity: textOpacity,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: chevronBg,
              border: Border.all(color: chevronBorder),
            ),
            child: Icon(Symbols.chevron_right, color: chevronIcon, size: 18),
          ),
        ),
      ],
    );
  }
}

class _EmergencyHelpSheet extends StatefulWidget {
  const _EmergencyHelpSheet({
    required this.bookingId,
    required this.otpRequested,
    required this.onVerified,
  });

  final String? bookingId;
  final bool otpRequested;
  final Future<void> Function() onVerified;

  @override
  State<_EmergencyHelpSheet> createState() => _EmergencyHelpSheetState();
}

class _EmergencyHelpSheetState extends State<_EmergencyHelpSheet> {
  final _otpController = TextEditingController();
  bool _submitting = false;
  String? _error;
  bool _closing = false;

  /// Closes the sheet once — shared by the ✕ button and pull-down-to-close.
  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context);
  }

  /// Pull-down-to-close: when the list is already at the very top and the
  /// customer keeps dragging down, the sheet closes (collapses back into
  /// the banner) instead of just bouncing — the scrollable content used to
  /// swallow that drag, so the sheet was hard to dismiss once opened.
  bool _onScroll(ScrollNotification n) {
    final draggingByFinger = (n is ScrollUpdateNotification && n.dragDetails != null) ||
        (n is OverscrollNotification && n.dragDetails != null);
    if (!draggingByFinger) return false;
    final pulledPastTop = n.metrics.pixels < n.metrics.minScrollExtent - 60 ||
        (n is OverscrollNotification && n.overscroll < -6 && n.metrics.pixels <= n.metrics.minScrollExtent);
    if (pulledPastTop) _close();
    return false;
  }

  @override
  void initState() {
    super.initState();
    themeController.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    themeController.removeListener(_onThemeChanged);
    _otpController.dispose();
    super.dispose();
  }

  /// Same server-side check the app's other return OTPs use: the update
  /// only matches a row whose `return_otp_code` equals what was typed, so
  /// the code itself never has to be read back to this device.
  Future<void> _verifyOtp() async {
    final entered = _otpController.text.trim();
    if (entered.length != 4 || widget.bookingId == null) {
      setState(() => _error = 'Enter the 4-digit code shown by the technician');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client
          .from('bookings')
          .update({
            'return_otp_verified_at': DateTime.now().toIso8601String(),
            'booking_status': 'Delivered',
          })
          .eq('id', widget.bookingId!)
          .eq('return_otp_code', entered)
          .select('id');
      if (!mounted) return;
      if ((rows as List).isEmpty) {
        setState(() {
          _error = "That code doesn't match — check the code and try again.";
          _submitting = false;
        });
        return;
      }
      await widget.onVerified();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Emergency service marked as done')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong — please try again.';
        _submitting = false;
      });
    }
  }

  Widget _otpSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.chipBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5323B).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Confirm service completed',
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.txt,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Enter the 4-digit OTP shown on the technician\'s screen.',
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: AppColors.mut,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.manrope(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 12,
              color: AppColors.txt,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••',
              hintStyle: TextStyle(color: AppColors.mut, letterSpacing: 12),
              errorText: _error,
              filled: true,
              fillColor: AppColors.surfaceSunken,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppColors.line),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _submitting ? null : _verifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE5323B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    'CONFIRM & MARK DONE',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: AppColors.line),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + bottomInset + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: SingleChildScrollView(
        // Always scrollable (with the same bounce on iOS and Android) so a
        // pull-down at the top is detected even when the content is short.
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Help is on the way',
                    style: GoogleFonts.manrope(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.txt,
                    ),
                  ),
                ),
                // Clear, always-visible way to close the sheet.
                Semantics(
                  button: true,
                  label: 'Close',
                  child: InkWell(
                    onTap: _close,
                    customBorder: const CircleBorder(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surfaceSunken,
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Icon(Icons.close_rounded, size: 20, color: AppColors.txt),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Our team has your location and phone number. Need us sooner? Call now.',
              style: GoogleFonts.manrope(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.mut,
              ),
            ),
            const SizedBox(height: 18),
            if (widget.otpRequested) _otpSection(),
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _dial(kEmergencySupportNumber),
              child: Ink(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE5323B), Color(0xFF9E1420)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE5323B).withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Black in light mode, white in dark mode.
                    Icon(Symbols.call,
                        color: AppColors.isDark ? Colors.white : Colors.black,
                        size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'CALL US NOW  ·  $kEmergencySupportNumber',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: AppColors.isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'EMERGENCY NUMBERS (INDIA)',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: AppColors.mut,
              ),
            ),
            const SizedBox(height: 10),
            for (final c in _kEmergencyContacts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _dial(c.number),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.chipBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      children: [
                        Icon(c.icon,
                            size: 22, color: const Color(0xFFE5323B)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            c.label,
                            style: GoogleFonts.manrope(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.txt,
                            ),
                          ),
                        ),
                        Text(
                          c.number,
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.txt,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(Symbols.call, size: 18, color: AppColors.mut),
                      ],
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