import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'home_screen.dart';
import 'signup_screen.dart';
import 'admin_dashboard_screen.dart';
import 'package:reperi_garage/widgets/error_display.dart';

// Same project URL/anon key as Supabase.initialize() in main.dart — used
// to spin up a throwaway SupabaseClient for the admin OTP reset flow below
// (see the comment on _forgotPasswordAdmin for why it can't reuse the
// app-wide Supabase.instance.client).
const String _supabaseUrl = 'https://rmvxqjyoqfinbrpubsvp.supabase.co';
const String _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtdnhxanlvcWZpbmJycHVic3ZwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcyMzQyNDcsImV4cCI6MjA5MjgxMDI0N30.NAxb2XnicLSaBoA4kpTFmmutT68Z2ksu-T-P_NUxy5E';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  bool isClient = true;
  bool _isLoading = false;
  bool _obscurePassword = true;

  // CLIENT-only alternate sign-in: email + one-time code instead of a
  // password. Garage login never shows this — see _buildLoginCard/
  // _buildLoginAsSection, which only render the toggle when isClient.
  bool _clientOtpMode = false;
  bool _otpSent = false;
  bool _otpLoading = false;
  final otpLoginController = TextEditingController();

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  // Garage/admin "forgot password" — a two-step, email-verified reset.
  // Step 0 confirms the email+username pair is a real admin account (via
  // the admin-verify-identity edge function, which never exposes the
  // password column) then sends a one-time code to that email through
  // Supabase Auth's own email-OTP delivery. Step 1 verifies that code —
  // proving the requester actually owns the inbox — and only then calls
  // admin-reset-password, which hashes the new password server-side.
  //
  // FIX: the dialog is now its own StatefulWidget
  // ([_AdminForgotPasswordDialog]) — same pattern as the client reset.
  // Previously its controllers and throwaway client were disposed right
  // after showDialog returned, while the dialog's closing animation was
  // still rebuilding the TextFields that used them, and the Cancel
  // button unfocused right before popping. Both caused the
  // "'_dependents.isEmpty': is not true" red screen. Now everything is
  // disposed in the dialog's own dispose(), and the success toast is
  // shown here with LoginScreen's live context.
  Future<void> _forgotPasswordAdmin() async {
    final didReset = await showDialog<bool>(
      context: context,
      builder: (_) => const _AdminForgotPasswordDialog(),
    );

    if (didReset == true && mounted) {
      ErrorDisplay.showPremiumToast(
        context,
        message: 'Password reset — sign in with your new one.',
        icon: Icons.check_circle_rounded,
        accent: const Color(0xFF3DD68C),
      );
    }
  }

  /// CLIENT password reset — OTP-based. The dialog itself is
  /// [_ForgotPasswordDialog], a dedicated StatefulWidget rather than an
  /// inline showDialog+StatefulBuilder — see its own dispose() for why
  /// the keyboard-dismiss has to live there instead of right before each
  /// button's Navigator.pop.
  ///
  /// FIX: the dialog now pops with `true` on a successful reset, and the
  /// success toast is shown HERE, with LoginScreen's own still-alive
  /// context. Previously the dialog showed the toast itself using its own
  /// context immediately after popping — that context was already
  /// deactivated, and that is what caused the
  /// "'_dependents.isEmpty': is not true" red screen.
  Future<void> _forgotPassword() async {
    final didReset = await showDialog<bool>(
      context: context,
      builder: (_) => const _ForgotPasswordDialog(),
    );

    if (didReset == true && mounted) {
      ErrorDisplay.showPremiumToast(
        context,
        message: 'Password reset — sign in with your new one.',
        icon: Icons.check_circle_rounded,
        accent: const Color(0xFF3DD68C),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    otpLoginController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = usernameController.text.trim();
    final password = passwordController.text.trim();

    // ── Client-side validation ──
    if (email.isEmpty) {
      ErrorDisplay.showPremiumToast(
        context,
        message: isClient
            ? 'Enter your email to continue signing in.'
            : 'Enter your garage username to continue.',
        icon: Icons.alternate_email_rounded,
      );
      return;
    }

    if (isClient && (!email.contains('@') || !email.contains('.'))) {
      ErrorDisplay.showPremiumToast(
        context,
        message: 'That doesn\'t look like a valid email address.',
        icon: Icons.alternate_email_rounded,
      );
      return;
    }

    if (password.isEmpty) {
      ErrorDisplay.showPremiumToast(
        context,
        message: 'Enter your password to continue.',
        icon: Icons.lock_outline_rounded,
      );
      return;
    }

    if (password.length < 6) {
      ErrorDisplay.showPremiumToast(
        context,
        message: 'Passwords are at least 6 characters — double-check yours.',
        icon: Icons.lock_outline_rounded,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      if (isClient) {
        // Client login via Supabase Auth
        await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        ).timeout(const Duration(seconds: 15));

        if (!mounted) return;

        // pushReplacement only swaps the top route — if this LoginScreen
        // was itself pushed on top of another screen (e.g. reached via
        // Signup's "Already have an account?" link), that screen would
        // stay buried at the bottom of the stack as the "first" route.
        // The bottom nav's Home button pops back to whatever route is
        // first, so it would land back on that buried screen instead of
        // Home — looking exactly like an unexpected logout. Clearing the
        // whole stack here guarantees Home is truly the first route.
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      } else {
        // Admin login — verified server-side against a bcrypt hash so the
        // password never travels as a plain-text table filter.
        final result = await supabase.functions.invoke(
          'admin-login',
          body: {'username': email, 'password': password},
        ).timeout(const Duration(seconds: 15));

        if (!mounted) return;

        final data = result.data as Map<String, dynamic>?;

        if (data != null && data['success'] == true) {
          final adminId = data['adminId'];

          // Garage/admin login never touches Supabase Auth (it's its own
          // bcrypt-checked table), so nothing here would otherwise survive
          // an app restart — persisting it the same way fleet login
          // already does is what lets SplashScreen send an already-logged-
          // in garage straight back to their dashboard instead of Login.
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('admin_logged_in', true);
          await prefs.setString('admin_id', adminId.toString());

          if (!mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => AdminDashboardScreen(adminId: adminId),
            ),
            (route) => false,
          );
        } else {
          ErrorDisplay.showPremiumError(
            context,
            error: 'invalid credentials',
            customMessage: 'That garage username or password isn\'t right — give it another try.',
          );
          setState(() => _isLoading = false);
        }
      }
    } on TimeoutException {
      if (!context.mounted) return;

      ErrorDisplay.showPremiumError(
        context,
        error: 'timeout',
        customMessage: 'That took too long — check your internet connection and try again.',
      );

      setState(() => _isLoading = false);
    } catch (e) {
      if (!context.mounted) return;

      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: isClient
            ? 'Could not sign in — check your email and password and try again.'
            : 'Could not log in to the garage dashboard — check your username and password and try again.',
      );

      setState(() => _isLoading = false);
    }
  }

  /// Step 1 of CLIENT OTP login — sends a one-time code to the entered
  /// email. Deliberately does NOT pre-check registration via
  /// customer-verify-email the way _forgotPassword does: that function
  /// calls admin.generateLink(type: "recovery") to check existence, which
  /// is not a harmless read — it consumes the exact same
  /// once-per-60-seconds email-send rate limit signInWithOtp itself uses.
  /// Calling both back-to-back for the same email meant this always
  /// collided with the limit it had just burned a moment earlier,
  /// failing every single send, for every email, 100% of the time. For
  /// login specifically, skipping the pre-check is a fair trade — an
  /// unregistered email just won't receive anything (Supabase's own
  /// anti-enumeration behavior for signInWithOtp already keeps the
  /// response looking the same either way), and the person can still
  /// tell something's wrong when no code ever arrives.
  Future<void> _sendClientLoginOtp() async {
    final email = usernameController.text.trim();

    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      ErrorDisplay.showPremiumToast(
        context,
        message: 'Enter a valid email to receive your login code.',
        icon: Icons.alternate_email_rounded,
      );
      return;
    }

    setState(() => _otpLoading = true);

    try {
      await Supabase.instance.client.auth
          .signInWithOtp(email: email, shouldCreateUser: false)
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _otpLoading = false;
      });
      ErrorDisplay.showPremiumToast(
        context,
        message: 'Code sent to $email.',
        icon: Icons.mark_email_read_rounded,
        accent: const Color(0xFF3DD68C),
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _otpLoading = false);
      ErrorDisplay.showPremiumError(
        context,
        error: 'timeout',
        customMessage: 'That took too long — check your internet connection and try again.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _otpLoading = false);
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not send the code. Please try again.',
      );
    }
  }

  /// Step 2 of CLIENT OTP login — verifying against the real, app-wide
  /// Supabase client (unlike _forgotPassword's throwaway one) is exactly
  /// what's needed here: the whole point of this flow is to actually sign
  /// the customer in, so the resulting session has to land on the client
  /// the rest of the app reads auth state from.
  Future<void> _verifyClientLoginOtp() async {
    final email = usernameController.text.trim();
    final code = otpLoginController.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (code.isEmpty) {
      ErrorDisplay.showPremiumToast(
        context,
        message: 'Enter the code we sent to your email.',
        icon: Icons.info_outline_rounded,
      );
      return;
    }

    setState(() => _otpLoading = true);

    try {
      final response = await Supabase.instance.client.auth
          .verifyOTP(email: email, token: code, type: OtpType.email)
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.session == null) {
        setState(() => _otpLoading = false);
        ErrorDisplay.showPremiumError(
          context,
          error: 'invalid otp',
          customMessage: 'That code is invalid or expired — request a new one.',
        );
        return;
      }

      // Same reasoning as _handleLogin's client branch — clear the whole
      // stack so Home is truly the first route.
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _otpLoading = false);
      ErrorDisplay.showPremiumError(
        context,
        error: 'timeout',
        customMessage: 'That took too long — check your internet connection and try again.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _otpLoading = false);
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'That code is invalid or expired — request a new one.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Detect if we're on a wide screen (web/tablet)
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 600;

    return Scaffold(
      // Plain, flat dark grey — no glow orbs or gradient texture behind
      // the content, just this one solid color.
      backgroundColor: const Color(0xFF262626),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: ConstrainedBox(
              // KEY FIX: cap width at 480px so it doesn't stretch on web
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: 0,
                  vertical: isWide ? 24 : 0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                        // Enough top breathing room to not sit flush
                        // against the status bar, without pushing
                        // everything below it too far down.
                        const SizedBox(height: 32),

                        /// ── HERO IMAGE ────────────────────────────────
                        SizedBox(
                          height: 180,
                          width: double.infinity,
                          child: Image.asset(
                            'assets/images/login.jpeg',
                            fit: BoxFit.contain,
                          ),
                        ),

                        const SizedBox(height: 12),

                        /// ── LOGIN CARD ──────────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _buildLoginCard(),
                        ),

                        if (isClient) ...[
                        const SizedBox(height: 16),

                        /// ── REGISTER LINK (CLIENT ONLY) ──────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Don't have an account?  ",
                              style: TextStyle(
                                color: Color(0xFF777777),
                                fontSize: 14,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const SignupScreen()),
                                );
                              },
                              child: Row(
                                children: const [
                                  Text(
                                    'Register Now',
                                    style: TextStyle(
                                      color: Color(0xFFD4A017),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Color(0xFFD4A017),
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        ],

                        const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── LOGIN CARD ─────────────────────────────────────────────────────────────
  Widget _buildLoginCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFFD4A017).withOpacity(0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4A017).withOpacity(0.08),
            blurRadius: 40,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          /// EMAIL FIELD
          _buildInputField(
            controller: usernameController,
            hint: 'Email',
            icon: Icons.person_outline_rounded,
          ),

          const SizedBox(height: 12),

          // CLIENT-only: "Password" vs "OTP Login" mode toggle. Garage
          // login never sees this — the else-branch below always shows
          // the plain password field regardless of _clientOtpMode.
          if (isClient) ...[
            _buildClientLoginModeToggle(),
            const SizedBox(height: 12),
          ],

          if (!isClient || !_clientOtpMode) ...[
            /// PASSWORD FIELD
            _buildPasswordField(),

            /// FORGOT PASSWORD
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  if (isClient) {
                    _forgotPassword();
                  } else {
                    _forgotPasswordAdmin();
                  }
                },
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Forgot Password?',
                  style: TextStyle(
                    color: Color(0xFFD4A017),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            /// SIGN IN BUTTON
            _buildSignInButton(),
          ] else ...[
            /// CLIENT OTP LOGIN
            _buildClientOtpLoginSection(),
          ],

          const SizedBox(height: 18),

          /// LOGIN AS TOGGLE
          _buildLoginAsSection(),
        ],
      ),
    );
  }

  /// The small "Password" / "OTP Login" segmented toggle shown only for
  /// CLIENT. Switching modes clears whatever OTP was in flight, so
  /// bouncing back and forth can't leave a stale "code sent" state behind.
  Widget _buildClientLoginModeToggle() {
    Widget segment(String label, bool selectedValue) {
      final selected = _clientOtpMode == selectedValue;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (_clientOtpMode == selectedValue) return;
            setState(() {
              _clientOtpMode = selectedValue;
              _otpSent = false;
              otpLoginController.clear();
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFD4A017).withOpacity(0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? const Color(0xFFD4A017) : const Color(0xFF3A3A3A),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? const Color(0xFFD4A017) : Colors.white54,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        segment('Password', false),
        const SizedBox(width: 10),
        segment('OTP Login', true),
      ],
    );
  }

  /// CLIENT OTP login body — an email field is already shown above this
  /// (shared with the password path), so this only needs the OTP field
  /// (once sent) plus the send/verify button.
  Widget _buildClientOtpLoginSection() {
    return Column(
      children: [
        if (_otpSent) ...[
          _buildInputField(
            controller: otpLoginController,
            hint: 'Enter the code sent to your email',
            icon: Icons.mark_email_read_outlined,
            keyboardType: TextInputType.number,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _otpLoading ? null : _sendClientLoginOtp,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Resend code',
                style: TextStyle(color: Color(0xFFD4A017), fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ] else
          const SizedBox(height: 14),
        GestureDetector(
          onTap: _otpLoading ? null : (_otpSent ? _verifyClientLoginOtp : _sendClientLoginOtp),
          child: Container(
            width: double.infinity,
            height: 62,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFD4A017), Color(0xFFF5C842)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD4A017).withOpacity(0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Center(
              child: _otpLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                    )
                  : Text(
                      _otpSent ? 'VERIFY & SIGN IN' : 'SEND OTP',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(icon, color: const Color(0xFFD4A017), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Color(0xFF555555)),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Icon(Icons.lock_outline_rounded,
              color: Color(0xFFD4A017), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: passwordController,
              obscureText: _obscurePassword,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: const InputDecoration(
                hintText: 'Password',
                hintStyle: TextStyle(color: Color(0xFF555555)),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: _obscurePassword ? 'Show password' : 'Hide password',
            child: GestureDetector(
              onTap: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: const Color(0xFFD4A017),
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignInButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _handleLogin,
      child: Container(
        width: double.infinity,
        height: 62,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFD4A017), Color(0xFFF5C842)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4A017).withOpacity(0.45),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Center(
          child: _isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.black,
                    strokeWidth: 2.5,
                  ),
                )
              : const Text(
                  'SIGN IN',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildLoginAsSection() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: Container(height: 1, color: const Color(0xFF222222))),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Login As',
                style: TextStyle(color: Color(0xFF555555), fontSize: 13),
              ),
            ),
            Expanded(
                child: Container(height: 1, color: const Color(0xFF222222))),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                child: _toggleButton(true, Icons.person_rounded, 'CLIENT')),
            const SizedBox(width: 12),
            Expanded(
                child: _toggleButton(false, Icons.shield_rounded, 'GARAGE')),
          ],
        ),
      ],
    );
  }

  Widget _toggleButton(bool value, IconData icon, String label) {
    final isSelected = isClient == value;
    return GestureDetector(
      onTap: () => setState(() {
        isClient = value;
        // Garage never shows OTP login — reset so switching back to
        // CLIENT later always starts fresh in password mode rather than
        // reappearing mid-flow with a stale "code sent" state.
        _clientOtpMode = false;
        _otpSent = false;
        otpLoginController.clear();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 52,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFD4A017).withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFD4A017)
                : const Color(0xFF3A3A3A),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? const Color(0xFFD4A017)
                  : const Color(0xFF555555),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFFD4A017)
                    : const Color(0xFF555555),
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CLIENT forgot-password popup — its own StatefulWidget rather than an
/// inline showDialog+StatefulBuilder, specifically so it gets a
/// dispose() lifecycle hook. Calling
/// FocusManager.instance.primaryFocus?.unfocus() right before
/// Navigator.pop (Cancel, or the success path) races the pop's own
/// teardown of this route and crashed with a
/// "'_dependents.isEmpty': is not true" assertion. dispose() always
/// runs exactly once, strictly after the route has actually been
/// removed, so there's no teardown left to race.
class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog();

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();

  // Throwaway client — the OTP dance (signInWithOtp/verifyOTP) signs in
  // whatever client runs it, and running it on the app-wide
  // Supabase.instance.client would silently replace/destroy a real
  // customer's already-active session on this device if one existed.
  // This client's session lives only in memory and is disposed with
  // this dialog.
  late final _otpClient = SupabaseClient(
    _supabaseUrl,
    _supabaseAnonKey,
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  );

  bool _isLoading = false;
  int _step = 0; // 0 = enter email, 1 = enter code + new password
  String? _error;

  @override
  void dispose() {
    FocusManager.instance.primaryFocus?.unfocus();
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _otpClient.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF6B6B6B)),
        filled: true,
        fillColor: const Color(0xFF1C1C1C),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF333333)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF333333)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD4A017), width: 1.4),
        ),
      );

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter the email you signed up with.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // No customer-verify-email pre-check here anymore — that function
      // calls admin.generateLink(type: "recovery") to test registration,
      // which is not a harmless read: it consumes the same
      // once-per-60-seconds email-send rate limit signInWithOtp itself
      // uses. Calling both back to back for the same email meant this
      // always collided with the limit it had just burned a moment
      // earlier, failing the send 100% of the time regardless of
      // whether the email was actually registered. Dropping the
      // pre-check trades away a distinct "no account found" message,
      // but signInWithOtp already resolves the same way either way
      // (Supabase's own anti-enumeration behavior), so an unregistered
      // email simply never receives anything, same as before this
      // feature existed.
      await _otpClient.auth.signInWithOtp(
        email: email,
        shouldCreateUser: false,
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _step = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not send the code. Please try again.';
      });
    }
  }

  Future<void> _confirmReset() async {
    final email = _emailController.text.trim();
    // Strip anything but digits — see signup_screen.dart's
    // _verifySignupOtp for why (a copy-pasted code with a formatting
    // space/dash would otherwise fail verification even though the
    // digits are correct).
    final code = _otpController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final newPassword = _newPasswordController.text.trim();

    if (code.isEmpty || newPassword.isEmpty) {
      setState(() => _error = 'Enter the code and your new password.');
      return;
    }
    if (newPassword.length < 6) {
      setState(() => _error = 'Passwords are at least 6 characters — double-check yours.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final verifyResponse = await _otpClient.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );

      if (verifyResponse.session == null) {
        throw Exception('No session returned for that code');
      }

      // _otpClient now holds a valid session for this customer (from
      // verifyOTP above) — updateUser on that same client changes that
      // authenticated user's own password directly, no separate edge
      // function needed (unlike the admin flow's bcrypt table, this is
      // Supabase Auth's own password column).
      await _otpClient.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      if (!mounted) return;
      // FIX: pop with `true` and let LoginScreen._forgotPassword show the
      // success toast with its own live context. Showing it here with
      // this dialog's context right after the pop is what caused the
      // "'_dependents.isEmpty': is not true" red screen.
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'That code is invalid or expired — request a new one.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF262626),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: const Color(0xFFD4A017).withOpacity(0.25)),
      ),
      // FIX: scrollable so the dialog no longer overflows ("BOTTOM
      // OVERFLOWED BY 97 PIXELS") when the keyboard shrinks the space
      // available to it on step 1 (code + new password fields).
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD4A017).withOpacity(0.12),
              ),
              child: const Icon(Icons.lock_reset_rounded, color: Color(0xFFD4A017), size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              _step == 0 ? 'Reset Your Password' : 'Enter Code & New Password',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _step == 0
                  ? 'Enter the email you signed up with — we\'ll send a code to it if it\'s registered.'
                  : 'Enter the code sent to ${_emailController.text.trim()} and choose a new password.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            if (_step == 0) ...[
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                enabled: !_isLoading,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration('your@email.com'),
              ),
            ] else ...[
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                enabled: !_isLoading,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration('6-digit code'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPasswordController,
                obscureText: true,
                enabled: !_isLoading,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration('New password'),
              ),
            ],
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _error == null
                  ? const SizedBox.shrink(key: ValueKey('no-error'))
                  : Padding(
                      key: const ValueKey('error'),
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Color(0xFFE5484D), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Color(0xFFE5484D), fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: Color(0xFF3A3A3A)),
                    ),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : (_step == 0 ? _sendCode : _confirmReset),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4A017),
                      disabledBackgroundColor: const Color(0xFFD4A017).withOpacity(0.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                            ),
                          )
                        : Text(
                            _step == 0 ? 'Send Code' : 'Reset Password',
                            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
                          ),
                  ),
                ),
              ],
            ),
            if (_step == 1) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: _isLoading ? null : _sendCode,
                child: const Text('Resend code', style: TextStyle(color: Color(0xFFD4A017))),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// GARAGE/admin forgot-password popup — same logic and look as before,
/// just moved into its own StatefulWidget so its controllers, throwaway
/// client and keyboard-dismiss live in dispose(), which runs strictly
/// after the route is fully removed (no teardown left to race).
class _AdminForgotPasswordDialog extends StatefulWidget {
  const _AdminForgotPasswordDialog();

  @override
  State<_AdminForgotPasswordDialog> createState() =>
      _AdminForgotPasswordDialogState();
}

class _AdminForgotPasswordDialogState
    extends State<_AdminForgotPasswordDialog> {
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();

  // A throwaway client, isolated from Supabase.instance.client. The OTP
  // dance below (signInWithOtp/verifyOTP) sets whatever client runs it
  // as "logged in" — running it on the app-wide client would silently
  // replace/destroy a real customer's session if one was active on this
  // device, which is exactly what broke `user_id` on AI-chat reports
  // after someone reset a garage password. This client's session lives
  // only in memory and is disposed with the dialog, so it can never
  // touch the customer-facing auth state.
  late final _otpClient = SupabaseClient(
    _supabaseUrl,
    _supabaseAnonKey,
    // PKCE (the default flow) needs a persistent storage backend to hold
    // a code verifier across steps — this client never persists
    // anything and never survives a redirect, so implicit flow (which
    // doesn't need that storage) is the right fit here.
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  );

  bool _isLoading = false;
  int _step = 0; // 0 = enter email/username, 1 = enter code + new password

  @override
  void dispose() {
    FocusManager.instance.primaryFocus?.unfocus();
    _emailController.dispose();
    _usernameController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _otpClient.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF3A3A3A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF333333)),
        ),
      );

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();

    if (email.isEmpty || username.isEmpty) {
      ErrorDisplay.showPremiumToast(
        context,
        message: 'Enter both the registered email and username.',
        icon: Icons.info_outline_rounded,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final verify = await Supabase.instance.client.functions.invoke(
        'admin-verify-identity',
        body: {'email': email, 'username': username},
      );
      final verifyData = verify.data as Map<String, dynamic>?;

      if (verifyData?['valid'] != true) {
        if (!mounted) return;
        ErrorDisplay.showPremiumToast(
          context,
          message: 'That email and username don\'t match a garage account.',
          icon: Icons.error_outline_rounded,
          accent: const Color(0xFFE5484D),
        );
        setState(() => _isLoading = false);
        return;
      }

      await _otpClient.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _step = 1;
      });
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showPremiumError(context, error: e);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmReset() async {
    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();
    // Strip anything but digits — see signup_screen.dart's
    // _verifySignupOtp for why (a copy-pasted code with a formatting
    // space/dash would otherwise fail verification even though the
    // digits are correct).
    final code = _otpController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final newPassword = _passwordController.text.trim();

    if (code.isEmpty || newPassword.isEmpty) {
      ErrorDisplay.showPremiumToast(
        context,
        message: 'Enter the code and your new password.',
        icon: Icons.info_outline_rounded,
      );
      return;
    }
    if (newPassword.length < 6) {
      ErrorDisplay.showPremiumToast(
        context,
        message: 'Passwords are at least 6 characters — double-check yours.',
        icon: Icons.lock_outline_rounded,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final verifyResponse = await _otpClient.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );

      final accessToken = verifyResponse.session?.accessToken;
      if (accessToken == null) {
        throw Exception('No session returned for that code');
      }

      // Passed explicitly rather than relying on the app-wide client's
      // current session — that session was never touched by this flow
      // in the first place (see _otpClient above).
      final reset = await Supabase.instance.client.functions.invoke(
        'admin-reset-password',
        body: {'username': username, 'newPassword': newPassword},
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      final resetData = reset.data as Map<String, dynamic>?;
      if (!mounted) return;

      if (resetData?['success'] == true) {
        // Success toast is shown by LoginScreen._forgotPasswordAdmin.
        Navigator.pop(context, true);
      } else {
        ErrorDisplay.showPremiumToast(
          context,
          message: '${resetData?['error'] ?? 'Could not reset password — please try again.'}',
          icon: Icons.error_outline_rounded,
          accent: const Color(0xFFE5484D),
        );
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showPremiumToast(
        context,
        message: 'That code is invalid or expired — request a new one.',
        icon: Icons.error_outline_rounded,
        accent: const Color(0xFFE5484D),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset Password'),
      backgroundColor: const Color(0xFF262626),
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _step == 0
              ? [
                  _fieldLabel('Email registered with Reperi'),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white),
                    enabled: !_isLoading,
                    decoration: _fieldDecoration('your@email.com'),
                  ),
                  const SizedBox(height: 16),
                  _fieldLabel('Username registered with Reperi'),
                  TextField(
                    controller: _usernameController,
                    style: const TextStyle(color: Colors.white),
                    enabled: !_isLoading,
                    decoration: _fieldDecoration('your_username'),
                  ),
                ]
              : [
                  Text(
                    'We sent a 6-digit code to ${_emailController.text.trim()}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  _fieldLabel('Verification Code'),
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    enabled: !_isLoading,
                    decoration: _fieldDecoration('123456'),
                  ),
                  const SizedBox(height: 16),
                  _fieldLabel('New Password'),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    enabled: !_isLoading,
                    decoration: _fieldDecoration('Enter new password'),
                  ),
                ],
        ),
      ),
      actions: [
        TextButton(
          // Keyboard dismiss now happens in dispose(), not here — doing
          // it right before pop is what raced the route teardown.
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Color(0xFFD4A017)),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD4A017),
          ),
          onPressed: _isLoading ? null : (_step == 0 ? _sendCode : _confirmReset),
          child: _isLoading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                  ),
                )
              : Text(
                  _step == 0 ? 'Send Code' : 'Reset Password',
                  style: const TextStyle(color: Colors.black),
                ),
        ),
      ],
    );
  }
}
