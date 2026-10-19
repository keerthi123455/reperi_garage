import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/guest_mode.dart';

// Two playful yellow bottom sheets:
//
//  • showGuestInvite()  — on the login / register screens:
//      "Sign in as guest — do the boring stuff later....."  [Login as guest]
//
//  • requireAccount()   — when a guest taps Book Now / Pay / Add car /
//      Add address: sign up or log in RIGHT THERE with an email code, then
//      the sheet closes and they carry on from the same screen.

const _yellowTop = Color(0xFFFFE27A);
const _yellow = Color(0xFFFFD23F);
const _yellowDeep = Color(0xFFFFC21A);
const _ink = Color(0xFF16213E);
const _inkSoft = Color(0xB316213E);

// ═══════════════════════════════════════════════════════════════════════
//  Guest invite (login / register screens)
// ═══════════════════════════════════════════════════════════════════════

final Set<String> _invitesShown = {};

/// Shows the yellow "Sign in as guest" sheet — once per app launch for each
/// [screen]. [onGuest] runs after guest mode is switched on; it should
/// navigate to Home.
Future<void> showGuestInvite(
  BuildContext context, {
  required VoidCallback onGuest,
  String screen = 'login',
}) async {
  // Once per app launch for each screen, so it never nags.
  if (!_invitesShown.add(screen)) return;
  final go = await _showYellowSheet<bool>(
    context,
    (ctx) => const _GuestInviteSheet(),
  );
  if (go == true) {
    await GuestMode.enable();
    onGuest();
  }
}

class _GuestInviteSheet extends StatelessWidget {
  const _GuestInviteSheet();

  @override
  Widget build(BuildContext context) {
    return _YellowSheet(
      children: [
        const SizedBox(height: 4),
        const SizedBox(height: 132, child: _LaterDoodle()),
        const SizedBox(height: 10),
        _Pop(
          delay: 120,
          child: Text(
            'Sign in as guest',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: _ink,
              letterSpacing: -0.6,
            ),
          ),
        ),
        const SizedBox(height: 6),
        _Pop(
          delay: 220,
          child: Text(
            'Do the boring stuff later.....',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(fontSize: 15.5, fontWeight: FontWeight.w600, color: _inkSoft),
          ),
        ),
        const SizedBox(height: 24),
        _Pop(
          delay: 320,
          child: _InkButton(
            label: 'Login as guest',
            icon: Icons.arrow_forward_rounded,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ),
        const SizedBox(height: 10),
        _Pop(
          delay: 400,
          child: Text(
            'Browse everything. We\'ll only ask you to sign up when you book.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600, color: _inkSoft),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Account gate (guest → signed in, without leaving the screen)
// ═══════════════════════════════════════════════════════════════════════

/// Returns true straight away when someone is signed in. For a guest it
/// opens the sign-up sheet and returns true once they're signed in (false
/// if they close it). Use before any booking / payment / add-car action:
///
///   if (!await requireAccount(context)) return;
Future<bool> requireAccount(BuildContext context, {String? title, String? subtitle}) async {
  if (Supabase.instance.client.auth.currentUser != null) return true;
  final ok = await _showYellowSheet<bool>(
    context,
    (ctx) => _AccountSheet(title: title, subtitle: subtitle),
    dismissible: true,
  );
  return ok == true && Supabase.instance.client.auth.currentUser != null;
}

/// Signed in, but the account has no name / phone yet (e.g. an older
/// account): opens the same yellow sheet straight at "One last thing".
Future<bool> requireContactDetails(BuildContext context) async {
  if (Supabase.instance.client.auth.currentUser == null) return requireAccount(context);
  final ok = await _showYellowSheet<bool>(
    context,
    (ctx) => const _AccountSheet(detailsOnly: true),
    dismissible: true,
  );
  return ok == true;
}

/// True when the signed-in account has both a name and a phone number.
Future<bool> hasContactDetails() async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) return false;
  final meta = user.userMetadata ?? const {};
  final phone = (user.phone ?? meta['phone'] ?? '').toString().trim();
  var name = (meta['full_name'] ?? meta['name'] ?? '').toString().trim();
  if (name.isEmpty) {
    try {
      final p = await supabase.from('profiles').select('name').eq('id', user.id).maybeSingle();
      name = (p?['name'] ?? '').toString().trim();
    } catch (_) {}
  }
  return name.isNotEmpty && phone.isNotEmpty;
}

enum _Step { email, code, details, done }

class _AccountSheet extends StatefulWidget {
  const _AccountSheet({this.title, this.subtitle, this.detailsOnly = false});

  final String? title;
  final String? subtitle;
  final bool detailsOnly;

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  final _auth = Supabase.instance.client.auth;
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  _Step _step = _Step.email;
  bool _busy = false;
  String? _error;
  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    if (widget.detailsOnly) {
      _step = _Step.details;
      final user = _auth.currentUser;
      final meta = user?.userMetadata ?? const {};
      _name.text = (meta['full_name'] ?? meta['name'] ?? '').toString();
      _phone.text = (user?.phone ?? meta['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      if (_phone.text.length == 12 && _phone.text.startsWith('91')) _phone.text = _phone.text.substring(2);
      if (_name.text.trim().isEmpty && user != null) _prefillName(user.id);
    }
  }

  Future<void> _prefillName(String userId) async {
    try {
      final p = await Supabase.instance.client.from('profiles').select('name').eq('id', userId).maybeSingle();
      if (mounted && _name.text.trim().isEmpty) _name.text = (p?['name'] ?? '').toString();
    } catch (_) {}
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _email.dispose();
    _code.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn = math.max(0, _resendIn - 1));
      if (_resendIn == 0) t.cancel();
    });
  }

  String get _emailText => _email.text.trim().toLowerCase();

  Future<void> _sendCode({bool resend = false}) async {
    final email = _emailText;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Creates the account if it's new, or sends a login code if it
      // already exists — one flow for both.
      await _auth.signInWithOtp(email: email, shouldCreateUser: true).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _Step.code;
      });
      _startResendTimer();
      if (resend) HapticFeedback.lightImpact();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is TimeoutException
            ? 'That took too long — check your internet and try again.'
            : (e is AuthException && e.statusCode == '429')
                ? 'Too many tries. Please wait a minute and try again.'
                : "Couldn't send the code. Please try again.";
      });
    }
  }

  Future<void> _verify() async {
    final code = _code.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (code.length < 6) {
      setState(() => _error = 'Enter the code from your email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // An existing account's code verifies as "email"; a brand-new
      // account's first code verifies as "signup" (see signup_screen.dart).
      Session? session;
      try {
        session = (await _auth
                .verifyOTP(email: _emailText, token: code, type: OtpType.email)
                .timeout(const Duration(seconds: 15)))
            .session;
      } catch (_) {}
      session ??= (await _auth
              .verifyOTP(email: _emailText, token: code, type: OtpType.signup)
              .timeout(const Duration(seconds: 15)))
          .session;
      if (session == null) throw Exception('invalid');
      await GuestMode.disable();
      if (!mounted) return;

      // Ask for name + phone only if this account doesn't have them yet.
      final user = _auth.currentUser!;
      final meta = user.userMetadata ?? const {};
      String name = (meta['full_name'] ?? meta['name'] ?? '').toString();
      try {
        final p = await Supabase.instance.client.from('profiles').select('name').eq('id', user.id).maybeSingle();
        if ((p?['name'] ?? '').toString().trim().isNotEmpty) name = p!['name'].toString();
      } catch (_) {}
      final phone = (user.phone ?? meta['phone'] ?? '').toString();
      if (!mounted) return;
      if (name.trim().isNotEmpty && phone.trim().isNotEmpty) {
        await _finish();
      } else {
        _name.text = name;
        _phone.text = phone.replaceAll(RegExp(r'[^0-9]'), '');
        setState(() {
          _busy = false;
          _step = _Step.details;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'That code is wrong or expired. Check it, or resend a new one.';
      });
    }
  }

  Future<void> _saveDetails() async {
    final name = _name.text.trim();
    var phone = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length == 12 && phone.startsWith('91')) phone = phone.substring(2);
    if (name.isEmpty) {
      setState(() => _error = 'Tell us your name.');
      return;
    }
    if (phone.length != 10) {
      setState(() => _error = 'Enter your 10-digit mobile number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser!;
      await supabase.auth.updateUser(UserAttributes(data: {'phone': phone, 'full_name': name, 'name': name}));
      try {
        final existing = await supabase.from('profiles').select('id').eq('id', user.id).maybeSingle();
        if (existing == null) {
          await supabase.from('profiles').insert({'id': user.id, 'name': name, 'email': user.email});
        } else {
          await supabase.from('profiles').update({'name': name}).eq('id', user.id);
        }
      } catch (e) {
        debugPrint('Profile save failed (continuing): $e');
      }
      await _finish();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = "Couldn't save that. Please try again.";
      });
    }
  }

  Future<void> _finish() async {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = false;
      _step = _Step.done;
    });
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return _YellowSheet(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(a),
              child: child,
            ),
          ),
          child: KeyedSubtree(key: ValueKey(_step), child: _stepBody()),
        ),
      ],
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case _Step.email:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 110, child: _LaterDoodle()),
            const SizedBox(height: 6),
            _title(widget.title ?? 'Quick sign up to book'),
            _subtitle(widget.subtitle ?? "Takes 30 seconds. We'll email you a code — no password needed."),
            const SizedBox(height: 18),
            _field(
              controller: _email,
              hint: 'you@email.com',
              icon: Icons.alternate_email_rounded,
              keyboard: TextInputType.emailAddress,
              autofill: const [AutofillHints.email],
              autofocus: true,
              onSubmitted: (_) => _sendCode(),
            ),
            _errorLine(),
            const SizedBox(height: 14),
            _InkButton(label: 'Send code', icon: Icons.send_rounded, busy: _busy, onTap: _sendCode),
            const SizedBox(height: 10),
            _hint('Already have an account? Use the same email — we\'ll log you in.'),
          ],
        );
      case _Step.code:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Center(child: _MailBounce()),
            const SizedBox(height: 12),
            _title('Check your email'),
            _subtitle('Enter the code we sent to\n$_emailText'),
            const SizedBox(height: 18),
            _field(
              controller: _code,
              hint: '• • • • • •',
              icon: Icons.lock_outline_rounded,
              keyboard: TextInputType.number,
              autofill: const [AutofillHints.oneTimeCode],
              big: true,
              autofocus: true,
              maxLength: 8,
              onChanged: (v) {
                if (v.replaceAll(RegExp(r'[^0-9]'), '').length == 6 && !_busy) _verify();
              },
              onSubmitted: (_) => _verify(),
            ),
            _errorLine(),
            const SizedBox(height: 14),
            _InkButton(label: 'Verify', icon: Icons.check_rounded, busy: _busy, onTap: _verify),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _step = _Step.email;
                            _code.clear();
                            _error = null;
                          }),
                  child: Text('Change email',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: _ink)),
                ),
                TextButton(
                  onPressed: (_busy || _resendIn > 0) ? null : () => _sendCode(resend: true),
                  child: Text(
                    _resendIn > 0 ? 'Resend in ${_resendIn}s' : 'Resend code',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w800,
                      color: _resendIn > 0 ? _inkSoft : _ink,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      case _Step.details:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Center(child: Text('👋', style: TextStyle(fontSize: 46))),
            const SizedBox(height: 8),
            _title('One last thing'),
            _subtitle('So our team can reach you about your booking.'),
            const SizedBox(height: 18),
            _field(
              controller: _name,
              hint: 'Your name',
              icon: Icons.person_outline_rounded,
              autofill: const [AutofillHints.name],
              caps: TextCapitalization.words,
              autofocus: true,
            ),
            const SizedBox(height: 10),
            _field(
              controller: _phone,
              hint: 'Mobile number',
              icon: Icons.phone_iphone_rounded,
              prefix: '+91 ',
              keyboard: TextInputType.phone,
              autofill: const [AutofillHints.telephoneNumberNational],
              maxLength: 10,
              onSubmitted: (_) => _saveDetails(),
            ),
            _errorLine(),
            const SizedBox(height: 14),
            _InkButton(label: 'Continue booking', icon: Icons.arrow_forward_rounded, busy: _busy, onTap: _saveDetails),
          ],
        );
      default: // _Step.done
        return Column(
          children: [
            const SizedBox(height: 20),
            const _CheckPop(),
            const SizedBox(height: 14),
            _title("You're in!"),
            _subtitle('Taking you back to your booking…'),
            const SizedBox(height: 24),
          ],
        );
    }
  }

  Widget _title(String t) => Text(
        t,
        textAlign: TextAlign.center,
        style: GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.5),
      );

  Widget _subtitle(String t) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          t,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(fontSize: 14.5, fontWeight: FontWeight.w600, color: _inkSoft, height: 1.35),
        ),
      );

  Widget _hint(String t) => Text(
        t,
        textAlign: TextAlign.center,
        style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600, color: _inkSoft),
      );

  Widget _errorLine() => AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: _error == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    const Icon(Icons.error_rounded, size: 16, color: Color(0xFFB3261E)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_error!,
                          style: GoogleFonts.manrope(
                              fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFFB3261E))),
                    ),
                  ],
                ),
              ),
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboard,
    Iterable<String>? autofill,
    bool big = false,
    bool autofocus = false,
    int? maxLength,
    String? prefix,
    TextCapitalization caps = TextCapitalization.none,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: keyboard,
        autofillHints: autofill,
        textCapitalization: caps,
        maxLength: maxLength,
        readOnly: _busy,
        textAlign: big ? TextAlign.center : TextAlign.start,
        onChanged: (v) {
          if (_error != null) setState(() => _error = null);
          onChanged?.call(v);
        },
        onSubmitted: onSubmitted,
        inputFormatters: keyboard == TextInputType.number || keyboard == TextInputType.phone
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        style: GoogleFonts.manrope(
          fontSize: big ? 26 : 16,
          fontWeight: FontWeight.w800,
          color: _ink,
          letterSpacing: big ? 8 : 0,
        ),
        decoration: InputDecoration(
          counterText: '',
          hintText: hint,
          hintStyle: GoogleFonts.manrope(
            fontSize: big ? 22 : 15,
            fontWeight: FontWeight.w600,
            color: const Color(0x6616213E),
            letterSpacing: big ? 4 : 0,
          ),
          prefixIcon: big ? null : Icon(icon, color: _ink, size: 20),
          prefixText: prefix,
          prefixStyle: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800, color: _ink),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: big ? 18 : 17),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Shared pieces
// ═══════════════════════════════════════════════════════════════════════

/// Slides a yellow sheet up from the bottom over a dimmed screen.
Future<T?> _showYellowSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool dismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Close',
    barrierColor: const Color(0x8C0B0B14),
    transitionDuration: const Duration(milliseconds: 460),
    pageBuilder: (ctx, _, __) => Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        // Lift above the keyboard.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Material(type: MaterialType.transparency, child: builder(ctx)),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final slide = CurvedAnimation(parent: anim, curve: Curves.easeOutQuart, reverseCurve: Curves.easeInCubic);
      return SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(slide),
        child: child,
      );
    },
  );
}

class _YellowSheet extends StatelessWidget {
  const _YellowSheet({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_yellowTop, _yellow, _yellowDeep],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, -6))],
        ),
        child: Stack(
          children: [
            // Soft polka dots for texture.
            const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _DotsPainter()))),
            SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(color: _ink.withOpacity(0.18), borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                    ...children,
                  ],
                ),
              ),
            ),
            Positioned(
              top: 14,
              right: 14,
              child: _CloseButton(onTap: () => Navigator.of(context).pop(false)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.85 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedRotation(
            turns: _down ? 0.125 : 0,
            duration: const Duration(milliseconds: 160),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.65),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, size: 20, color: _ink),
            ),
          ),
        ),
      ),
    );
  }
}

class _InkButton extends StatefulWidget {
  const _InkButton({required this.label, required this.icon, required this.onTap, this.busy = false});

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;

  @override
  State<_InkButton> createState() => _InkButtonState();
}

class _InkButtonState extends State<_InkButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.busy
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap();
            },
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            color: _ink,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Color(0x5516213E), blurRadius: 18, offset: Offset(0, 8))],
          ),
          alignment: Alignment.center,
          child: widget.busy
              ? const SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.6, color: _yellow))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.label,
                      style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(color: _yellow, shape: BoxShape.circle),
                      child: Icon(widget.icon, size: 17, color: _ink),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Fades + springs its child in after [delay] ms — used to stagger the
/// sheet's lines as it opens.
class _Pop extends StatefulWidget {
  const _Pop({required this.child, this.delay = 0});
  final Widget child;
  final int delay;

  @override
  State<_Pop> createState() => _PopState();
}

class _PopState extends State<_Pop> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 180 + widget.delay), () {
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
    final a = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Opacity(
        opacity: _c.value.clamp(0.0, 1.0).toDouble(),
        child: Transform.translate(offset: Offset(0, 14 * (1 - a.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.18);
    const gap = 26.0;
    for (var y = 10.0; y < size.height; y += gap) {
      final row = (y / gap).round();
      for (var x = (row.isEven ? 8.0 : 21.0); x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 1.6, p);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => false;
}

/// A little car cruising along while paperwork ("the boring stuff") flies
/// off behind it. Loops forever.
class _LaterDoodle extends StatefulWidget {
  const _LaterDoodle();

  @override
  State<_LaterDoodle> createState() => _LaterDoodleState();
}

class _LaterDoodleState extends State<_LaterDoodle> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(painter: _DoodlePainter(_c.value), size: Size.infinite),
    );
  }
}

class _DoodlePainter extends CustomPainter {
  _DoodlePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final groundY = h * 0.84;
    final ink = Paint()..color = _ink;

    // Road dashes sliding left.
    final dash = Paint()
      ..color = _ink.withOpacity(0.28)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const seg = 38.0;
    final off = (t * seg * 6) % seg;
    for (var x = -seg + (seg - off); x < w + seg; x += seg) {
      canvas.drawLine(Offset(x, groundY + 10), Offset(x + 16, groundY + 10), dash);
    }

    // Car, gently bobbing.
    final carW = math.min(170.0, w * 0.46);
    final s = carW / 450;
    final bob = math.sin(t * math.pi * 2 * 4) * 2.2;
    final cx = w * 0.56;
    final carLeft = cx - carW / 2;
    canvas.save();
    canvas.translate(carLeft, groundY - 156 * s + bob);
    canvas.scale(s);
    // Body (design space 0..450 x 0..156; wheels centred on y 156).
    final body = Path()
      ..moveTo(0, 134)
      ..quadraticBezierTo(-4, 94, 30, 84)
      ..lineTo(92, 72)
      ..quadraticBezierTo(120, 18, 174, 4)
      ..lineTo(290, 0)
      ..quadraticBezierTo(332, 2, 364, 40)
      ..lineTo(398, 74)
      ..quadraticBezierTo(444, 82, 448, 116)
      ..lineTo(450, 142)
      ..quadraticBezierTo(450, 156, 436, 156)
      ..lineTo(18, 156)
      ..quadraticBezierTo(2, 156, 0, 142)
      ..close();
    canvas.drawPath(body, ink);
    final glass = Paint()..color = Colors.white.withOpacity(0.92);
    canvas.drawPath(
      Path()
        ..moveTo(110, 72)
        ..quadraticBezierTo(132, 26, 174, 18)
        ..lineTo(224, 16)
        ..lineTo(224, 72)
        ..close(),
      glass,
    );
    canvas.drawPath(
      Path()
        ..moveTo(240, 16)
        ..lineTo(288, 16)
        ..quadraticBezierTo(320, 18, 346, 48)
        ..lineTo(364, 72)
        ..lineTo(240, 72)
        ..close(),
      glass,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(430, 100, 16, 12), const Radius.circular(5)),
        Paint()..color = _yellowTop);
    canvas.restore();

    // Wheels (not bobbing) with turning spokes.
    for (final wx in [carLeft + 94 * s, carLeft + 356 * s]) {
      final c = Offset(wx, groundY);
      final r = 40 * s;
      canvas.drawCircle(c, r, ink);
      canvas.drawCircle(c, r * 0.48, Paint()..color = Colors.white);
      final spoke = Paint()
        ..color = _ink
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 3; i++) {
        final a = t * math.pi * 2 * 5 + i * math.pi * 2 / 3;
        canvas.drawLine(c, c + Offset(math.cos(a), math.sin(a)) * r * 0.42, spoke);
      }
    }

    // Speed lines behind the car.
    final speed = Paint()
      ..color = _ink.withOpacity(0.35)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final phase = (t * 3 + i / 3) % 1.0;
      final y = groundY - 30 * s * (i + 1.4);
      final x1 = carLeft - 14 - phase * 40;
      canvas.drawLine(Offset(x1, y), Offset(x1 - 22 + phase * 10, y),
          speed..color = _ink.withOpacity(0.35 * (1 - phase)));
    }

    // Paperwork flying off behind and fading — the "boring stuff".
    for (var i = 0; i < 4; i++) {
      final p = (t + i / 4) % 1.0;
      final start = Offset(carLeft + 60 * s, groundY - 150 * s);
      final pos = start + Offset(-p * w * 0.42, -p * h * 0.55 + math.sin(p * math.pi * 3 + i) * 6);
      final op = p < 0.15 ? p / 0.15 : (1 - p);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate((-0.6 + i * 0.35) * p * 2.2);
      final sheet = RRect.fromRectAndRadius(const Rect.fromLTWH(-11, -14, 22, 28), const Radius.circular(3));
      canvas.drawRRect(sheet, Paint()..color = Colors.white.withOpacity(op.clamp(0.0, 1.0).toDouble()));
      final line = Paint()
        ..color = _ink.withOpacity((0.45 * op).clamp(0.0, 1.0).toDouble())
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (var k = 0; k < 3; k++) {
        canvas.drawLine(Offset(-6, -7 + k * 6.0), Offset(6 - (k == 2 ? 5 : 0), -7 + k * 6.0), line);
      }
      canvas.restore();
    }

    // Sparkles.
    final sp = Paint()..color = Colors.white.withOpacity(0.9);
    for (var i = 0; i < 3; i++) {
      final p = (t * 1.5 + i * 0.33) % 1.0;
      final c = Offset(w * (0.78 + i * 0.07), h * (0.18 + i * 0.16));
      final r = 5 * math.sin(p * math.pi);
      if (r <= 0) continue;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - r * 2)
          ..quadraticBezierTo(c.dx, c.dy, c.dx + r * 2, c.dy)
          ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r * 2)
          ..quadraticBezierTo(c.dx, c.dy, c.dx - r * 2, c.dy)
          ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r * 2)
          ..close(),
        sp,
      );
    }
  }

  @override
  bool shouldRepaint(_DoodlePainter old) => old.t != t;
}

/// Envelope that bounces gently on the "check your email" step.
class _MailBounce extends StatefulWidget {
  const _MailBounce();

  @override
  State<_MailBounce> createState() => _MailBounceState();
}

class _MailBounceState extends State<_MailBounce> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final y = -math.sin(_c.value * math.pi * 2).abs() * 10;
        final tilt = math.sin(_c.value * math.pi * 2) * 0.06;
        return Transform.translate(offset: Offset(0, y), child: Transform.rotate(angle: tilt, child: child));
      },
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Color(0x2216213E), blurRadius: 16, offset: Offset(0, 8))],
        ),
        child: const Icon(Icons.mark_email_unread_rounded, size: 38, color: _ink),
      ),
    );
  }
}

/// Big tick that springs in on success.
class _CheckPop extends StatefulWidget {
  const _CheckPop();

  @override
  State<_CheckPop> createState() => _CheckPopState();
}

class _CheckPopState extends State<_CheckPop> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: _c, curve: Curves.elasticOut),
      child: Container(
        width: 86,
        height: 86,
        decoration: const BoxDecoration(color: _ink, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, size: 50, color: _yellow),
      ),
    );
  }
}
