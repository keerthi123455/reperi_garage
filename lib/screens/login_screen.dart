import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'home_screen.dart';
import 'signup_screen.dart';
import 'admin_dashboard_screen.dart';
import 'package:reperi_garage/widgets/error_display.dart';
import 'package:reperi_garage/widgets/guest_sheets.dart';
import 'package:reperi_garage/services/guest_mode.dart';
import 'package:reperi_garage/theme/app_colors.dart';
import 'package:reperi_garage/widgets/auth_ui.dart';

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

    // "Sign in as guest — do the boring stuff later" (once per launch).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      showGuestInvite(context, screen: 'login', onGuest: _continueAsGuest);
    });
  }

  void _continueAsGuest() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
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

  /// "New to Reperi? Create an account". When this screen was opened from
  /// the sign-up screen (the app's first screen), just go back to it;
  /// otherwise (e.g. after logging out) open it.
  void _openSignup() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.push(MaterialPageRoute(builder: (_) => const SignupScreen()));
    }
  }

  Future<void> _guestTapped() async {
    await GuestMode.enable(source: 'login_button');
    _continueAsGuest();
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return FadeTransition(
      opacity: _fadeAnimation,
      child: AuthPage(
        topBar: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                if (canPop)
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back_rounded, color: AppColors.txt),
                  ),
                const Spacer(),
              ],
            ),
          ),
        ),
        children: [
          const Center(child: AuthWordmark()),
          const SizedBox(height: 18),
          if (isClient)
            const Center(child: AuthHero(size: 72))
          else
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(color: kAuthGold.withOpacity(0.16), shape: BoxShape.circle),
                child: const Icon(Icons.storefront_rounded, color: kAuthGold, size: 38),
              ),
            ),
          const SizedBox(height: 14),
          AuthTitle(
            title: isClient ? 'Welcome back 👋' : 'Garage partner login',
            subtitle: isClient
                ? 'Log in to book, track and pay for your vehicle care.'
                : 'Log in to manage the bookings sent to your garage.',
          ),
          const SizedBox(height: 18),

          /// ── WHO ARE YOU ────────────────────────────────
          _buildLoginAsSection(),
          const SizedBox(height: 14),

          /// ── LOGIN CARD ─────────────────────────────────
          AuthCard(child: _buildLoginForm()),

          if (isClient) ...[
            const SizedBox(height: 18),
            const AuthOrDivider(),
            const SizedBox(height: 18),
            AuthGuestButton(onTap: _guestTapped),
            const SizedBox(height: 16),
            AuthSwitchLink(
              question: 'New to Reperi?',
              action: 'Create an account',
              onTap: _openSignup,
            ),
            const SizedBox(height: 10),
            const AuthLegalNote(),
          ],
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthField(
          label: isClient ? 'Email' : 'Garage username',
          controller: usernameController,
          hint: isClient ? 'you@example.com' : 'Your garage username',
          icon: isClient ? Icons.alternate_email_rounded : Icons.storefront_rounded,
          keyboardType: isClient ? TextInputType.emailAddress : TextInputType.text,
          autofillHints: isClient ? const [AutofillHints.email] : const [AutofillHints.username],
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),

        // CLIENT-only: password vs one-time email code. Garage login never
        // sees this — it always gets the plain password field.
        if (isClient) ...[
          _buildClientLoginModeToggle(),
          const SizedBox(height: 14),
        ],

        if (!isClient || !_clientOtpMode) ...[
          AuthField(
            label: 'Password',
            controller: passwordController,
            hint: 'Your password',
            icon: Icons.lock_outline_rounded,
            obscure: _obscurePassword,
            onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!_isLoading) _handleLogin();
            },
          ),
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
                foregroundColor: AppColors.txt,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Forgot password?',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 4),
          AuthPrimaryButton(label: 'Log in', loading: _isLoading, onTap: _handleLogin),
        ] else
          _buildClientOtpLoginSection(),
      ],
    );
  }

  /// "Use password" / "Email me a code" — CLIENT only. Switching clears any
  /// code in flight, so bouncing back and forth can't leave a stale state.
  Widget _buildClientLoginModeToggle() {
    Widget segment(String label, bool selectedValue) {
      final selected = _clientOtpMode == selectedValue;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_clientOtpMode == selectedValue) return;
            setState(() {
              _clientOtpMode = selectedValue;
              _otpSent = false;
              otpLoginController.clear();
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.surfaceRaised : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: selected
                  ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))]
                  : null,
            ),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: selected ? AppColors.txt : AppColors.mut,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          segment('Use password', false),
          segment('Email me a code', true),
        ],
      ),
    );
  }

  /// CLIENT code login — the email field is already above, so this is the
  /// code field (once sent) plus the send / verify button.
  Widget _buildClientOtpLoginSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_otpSent) ...[
          AuthField(
            label: 'Code from your email',
            controller: otpLoginController,
            hint: '6-digit code',
            icon: Icons.mark_email_read_outlined,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!_otpLoading) _verifyClientLoginOtp();
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _otpLoading ? null : _sendClientLoginOtp,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.txt,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Resend code', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 4),
        ] else ...[
          Text(
            "We'll email you a one-time code — no password needed.",
            style: TextStyle(color: AppColors.mut, fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
          ),
          const SizedBox(height: 14),
        ],
        AuthPrimaryButton(
          label: _otpSent ? 'Verify & log in' : 'Send me a code',
          loading: _otpLoading,
          onTap: _otpSent ? _verifyClientLoginOtp : _sendClientLoginOtp,
        ),
      ],
    );
  }

  Widget _buildLoginAsSection() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(child: _toggleButton(true, Icons.person_rounded, "I'm a customer")),
          const SizedBox(width: 4),
          Expanded(child: _toggleButton(false, Icons.storefront_rounded, "I'm a garage")),
        ],
      ),
    );
  }

  Widget _toggleButton(bool value, IconData icon, String label) {
    final isSelected = isClient == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        isClient = value;
        // Garage never shows code login — reset so switching back to
        // customer always starts fresh in password mode.
        _clientOtpMode = false;
        _otpSent = false;
        otpLoginController.clear();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.txt : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: isSelected ? AppColors.ink : AppColors.mut),
              const SizedBox(width: 8),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: isSelected ? AppColors.ink : AppColors.mut,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
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
    authOptions: AuthClientOptions(authFlowType: AuthFlowType.implicit),
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
        hintStyle: TextStyle(color: AppColors.mut),
        filled: true,
        fillColor: AppColors.surfaceSunken,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Color(0xFFD4A017), width: 1.4),
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
      backgroundColor: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Color(0xFFD4A017).withOpacity(0.25)),
      ),
      // FIX: scrollable so the dialog no longer overflows ("BOTTOM
      // OVERFLOWED BY 97 PIXELS") when the keyboard shrinks the space
      // available to it on step 1 (code + new password fields).
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 28, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFD4A017).withOpacity(0.12),
              ),
              child: Icon(Icons.lock_reset_rounded, color: Color(0xFFD4A017), size: 30),
            ),
            SizedBox(height: 18),
            Text(
              _step == 0 ? 'Reset Your Password' : 'Enter Code & New Password',
              style: TextStyle(
                color: AppColors.txt,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              _step == 0
                  ? 'Enter the email you signed up with — we\'ll send a code to it if it\'s registered.'
                  : 'Enter the code sent to ${_emailController.text.trim()} and choose a new password.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.mut,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            SizedBox(height: 22),
            if (_step == 0) ...[
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                enabled: !_isLoading,
                style: TextStyle(color: AppColors.txt),
                decoration: _fieldDecoration('your@email.com'),
              ),
            ] else ...[
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                enabled: !_isLoading,
                style: TextStyle(color: AppColors.txt),
                decoration: _fieldDecoration('6-digit code'),
              ),
              SizedBox(height: 12),
              TextField(
                controller: _newPasswordController,
                obscureText: true,
                enabled: !_isLoading,
                style: TextStyle(color: AppColors.txt),
                decoration: _fieldDecoration('New password'),
              ),
            ],
            AnimatedSwitcher(
              duration: Duration(milliseconds: 180),
              child: _error == null
                  ? SizedBox.shrink(key: ValueKey('no-error'))
                  : Padding(
                      key: ValueKey('error'),
                      padding: EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, color: Color(0xFFE5484D), size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(color: Color(0xFFE5484D), fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: AppColors.line),
                    ),
                    child: Text('Cancel', style: TextStyle(color: AppColors.mut)),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : (_step == 0 ? _sendCode : _confirmReset),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFD4A017),
                      disabledBackgroundColor: Color(0xFFD4A017).withOpacity(0.5),
                      padding: EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                            ),
                          )
                        : Text(
                            _step == 0 ? 'Send Code' : 'Reset Password',
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
                          ),
                  ),
                ),
              ],
            ),
            if (_step == 1) ...[
              SizedBox(height: 10),
              TextButton(
                onPressed: _isLoading ? null : _sendCode,
                child: Text('Resend code', style: TextStyle(color: Color(0xFFD4A017))),
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
    authOptions: AuthClientOptions(authFlowType: AuthFlowType.implicit),
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
        hintStyle: TextStyle(color: AppColors.mut),
        filled: true,
        fillColor: AppColors.surfaceSunken,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.line),
        ),
      );

  Widget _fieldLabel(String text) => Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.mut,
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
          accent: Color(0xFFE5484D),
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
          accent: Color(0xFFE5484D),
        );
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showPremiumToast(
        context,
        message: 'That code is invalid or expired — request a new one.',
        icon: Icons.error_outline_rounded,
        accent: Color(0xFFE5484D),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reset Password'),
      backgroundColor: AppColors.surfaceRaised,
      titleTextStyle: TextStyle(
        color: AppColors.txt,
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
                    style: TextStyle(color: AppColors.txt),
                    enabled: !_isLoading,
                    decoration: _fieldDecoration('your@email.com'),
                  ),
                  SizedBox(height: 16),
                  _fieldLabel('Username registered with Reperi'),
                  TextField(
                    controller: _usernameController,
                    style: TextStyle(color: AppColors.txt),
                    enabled: !_isLoading,
                    decoration: _fieldDecoration('your_username'),
                  ),
                ]
              : [
                  Text(
                    'We sent a 6-digit code to ${_emailController.text.trim()}',
                    style: TextStyle(color: AppColors.mut, fontSize: 13),
                  ),
                  SizedBox(height: 16),
                  _fieldLabel('Verification Code'),
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: AppColors.txt),
                    enabled: !_isLoading,
                    decoration: _fieldDecoration('123456'),
                  ),
                  SizedBox(height: 16),
                  _fieldLabel('New Password'),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: TextStyle(color: AppColors.txt),
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
          child: Text(
            'Cancel',
            style: TextStyle(color: Color(0xFFD4A017)),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFFD4A017),
          ),
          onPressed: _isLoading ? null : (_step == 0 ? _sendCode : _confirmReset),
          child: _isLoading
              ? SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                  ),
                )
              : Text(
                  _step == 0 ? 'Send Code' : 'Reset Password',
                  style: TextStyle(color: Colors.black),
                ),
        ),
      ],
    );
  }
}
