import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

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
    with SingleTickerProviderStateMixin {
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

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  Timer? _poll;
  bool _active = false;

  /// The open booking's id, and whether the technician has already tapped
  /// "mark as done" (which generates the completion OTP the customer types
  /// in below).
  String? _bookingId;
  bool _otpRequested = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _pulse.dispose();
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
      if (active != _active ||
          otpRequested != _otpRequested ||
          open?['id']?.toString() != _bookingId) {
        setState(() {
          _active = active;
          _otpRequested = otpRequested;
          _bookingId = open?['id']?.toString();
        });
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

  @override
  Widget build(BuildContext context) {
    if (!_active) return const SizedBox.shrink();
    const glow = Color(0xFFFF4D57);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = _pulse.value; // 0 -> 1 -> 0
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: glow.withOpacity(0.16 + 0.14 * t),
                  blurRadius: 28 + 10 * t,
                  spreadRadius: 1 + t,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: child,
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: _openSheet,
                splashColor: glow.withOpacity(0.12),
                highlightColor: glow.withOpacity(0.06),
                child: Ink(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF1B0B0D).withOpacity(0.92),
                        const Color(0xFF120607).withOpacity(0.96),
                      ],
                    ),
                    border: Border.all(
                      color: glow.withOpacity(0.55),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 42,
                        height: 42,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedBuilder(
                              animation: _pulse,
                              builder: (context, _) => Container(
                                width: 42 * (0.7 + 0.3 * _pulse.value),
                                height: 42 * (0.7 + 0.3 * _pulse.value),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: glow
                                      .withOpacity(0.30 * (1 - _pulse.value)),
                                ),
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
                                  BoxShadow(
                                    color: glow.withOpacity(0.5),
                                    blurRadius: 10,
                                  ),
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
                                      BoxShadow(
                                        color: glow.withOpacity(0.8),
                                        blurRadius: 5,
                                      ),
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
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _otpRequested
                                  ? 'Work finished · tap to enter your OTP'
                                  : 'Hold tight · tap for help & contacts',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withOpacity(0.62),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.06),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.10)),
                        ),
                        child: const Icon(Symbols.chevron_right,
                            color: Colors.white70, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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

  @override
  void dispose() {
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
      child: SingleChildScrollView(
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
            Text(
              'Help is on the way',
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.txt,
              ),
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
                    const Icon(Symbols.call, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'CALL US NOW  ·  $kEmergencySupportNumber',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: Colors.white,
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
    );
  }
}
