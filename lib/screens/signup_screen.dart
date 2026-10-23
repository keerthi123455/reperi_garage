import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/guest_mode.dart';
import '../theme/app_colors.dart';
import '../widgets/auth_ui.dart';
import '../widgets/error_display.dart';
import '../widgets/guest_sheets.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  final usernameController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final otpController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  // Set once signUp() succeeds without immediately returning a session —
  // that means the Supabase project has "Confirm email" turned on, so a
  // verification code was sent and this screen has to collect it before
  // the account is actually usable. If a session comes back right away
  // instead (confirmation disabled project-side), this never gets set and
  // signup goes straight to Home exactly as before this feature existed.
  bool _awaitingOtp = false;
  bool _verifyingOtp = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

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
      showGuestInvite(context, screen: 'signup', onGuest: _continueAsGuest);
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
    phoneController.dispose();
    passwordController.dispose();
    otpController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    final email = usernameController.text.trim();
    final phone = phoneController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || phone.isEmpty || password.isEmpty) {
      ErrorDisplay.showPremiumToast(
        context,
        message: 'Fill in your email, phone, and password to create an account.',
        icon: Icons.info_outline_rounded,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Sends the code through Supabase's regular email-OTP delivery (the
      // same "Magic Link" template the garage/admin reset flow and this
      // screen's own login-OTP option use) rather than calling
      // auth.signUp() and depending on a separate "Confirm signup"
      // template. shouldCreateUser: true creates the auth user right now,
      // with no password set yet — verifying the code below (see
      // _verifySignupOtp for why that verify uses OtpType.signup, not
      // .email, despite the send call being identical either way) both
      // confirms the email and returns a session, which is what then lets
      // _verifySignupOtp actually set the password.
      await Supabase.instance.client.auth
          .signInWithOtp(email: email, shouldCreateUser: true)
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      setState(() {
        _awaitingOtp = true;
        _isLoading = false;
      });
      ErrorDisplay.showPremiumToast(
        context,
        message: 'We sent a code to $email — enter it below to finish signing up.',
        icon: Icons.mark_email_read_rounded,
      );
      return;
    } on TimeoutException {
      if (!mounted) return;
      ErrorDisplay.showPremiumError(
        context,
        error: 'timeout',
        customMessage: 'That took too long — check your internet connection and try again.',
      );
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showPremiumError(context, error: e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // pushReplacement only swaps this SignupScreen for HomeScreen —
  // LoginScreen (pushed underneath when the user tapped "Register Now")
  // would stay buried as the stack's first route. The bottom nav's Home
  // button pops back to whatever route is first, so a freshly-registered
  // user tapping Home would get popped all the way back to that buried
  // LoginScreen — looking like a logout. Clearing the whole stack here
  // guarantees Home is the first route.
  void _goHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  Future<void> _verifySignupOtp() async {
    final email = usernameController.text.trim();
    final phone = phoneController.text.trim();
    final password = passwordController.text.trim();
    // Strip anything but digits — some OTP email templates format the
    // code with a space or dash for readability (e.g. "123 456"), and a
    // straight copy-paste would otherwise send that exact string to
    // verifyOTP, which fails as "invalid" even though the digits
    // themselves are correct.
    final code = otpController.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (code.isEmpty) {
      ErrorDisplay.showPremiumToast(
        context,
        message: 'Enter the code we sent to your email.',
        icon: Icons.info_outline_rounded,
      );
      return;
    }

    setState(() => _verifyingOtp = true);

    try {
      // type: OtpType.signup, not .email — GoTrue categorizes a brand-new
      // account's first confirmation code differently server-side from an
      // existing account's login/reset code, even though signInWithOtp
      // sends both through the identical "Magic Link" email template.
      // Verifying a new account's code with .email produces a generic
      // "token has expired or is invalid" / otp_expired error every time,
      // regardless of how fast or correctly the code is typed — that
      // mismatch, not a real formatting or expiry issue, was the actual
      // cause of repeated "expired" failures here.
      final response = await Supabase.instance.client.auth
          .verifyOTP(email: email, token: code, type: OtpType.signup)
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.session == null) {
        setState(() => _verifyingOtp = false);
        ErrorDisplay.showPremiumError(
          context,
          error: 'invalid otp',
          customMessage: 'That code is invalid or expired — request a new one.',
        );
        return;
      }

      // The OTP-created account has no password yet (signInWithOtp never
      // takes one) — now that verifyOTP has authenticated this session,
      // set the real password and phone the person entered on the form.
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password, data: {'phone': phone}),
      );

      if (!mounted) return;
      _goHome();
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _verifyingOtp = false);
      ErrorDisplay.showPremiumError(
        context,
        error: 'timeout',
        customMessage: 'That took too long — check your internet connection and try again.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _verifyingOtp = false);
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'That code is invalid or expired — request a new one.',
      );
    }
  }

  Future<void> _resendSignupOtp() async {
    final email = usernameController.text.trim();
    setState(() => _verifyingOtp = true);
    try {
      // Re-sending is just another signInWithOtp call, same as sending the
      // first one — Supabase's own rate-limiting is what stops this being
      // spammed, not anything this app needs to track itself.
      await Supabase.instance.client.auth
          .signInWithOtp(email: email, shouldCreateUser: true)
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      ErrorDisplay.showPremiumToast(
        context,
        message: 'Code resent to $email.',
        icon: Icons.mark_email_read_rounded,
      );
    } catch (e) {
      if (!mounted) return;
      ErrorDisplay.showPremiumError(
        context,
        error: e,
        customMessage: 'Could not resend the code. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _verifyingOtp = false);
    }
  }

  /// Guest button on this screen.
  Future<void> _guestTapped() async {
    await GuestMode.enable(source: 'signup_button');
    _continueAsGuest();
  }

  /// "Already have an account? Log in". This is now the first screen the
  /// app opens on, so Login usually isn't underneath — push it. If this
  /// screen was opened from Login ("Create an account"), just go back.
  void _openLogin() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.push(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: AuthPage(
        topBar: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
          child: Row(
            children: [
              if (Navigator.of(context).canPop())
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.arrow_back_rounded, color: AppColors.txt),
                ),
              const Spacer(),
              TextButton(
                onPressed: _openLogin,
                style: TextButton.styleFrom(foregroundColor: AppColors.txt),
                child: const Text('Log in', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
        children: [
          const Center(child: AuthWordmark()),
          const SizedBox(height: 18),
          const Center(child: AuthHero()),
          const SizedBox(height: 16),
          AuthTitle(
            title: _awaitingOtp ? 'Check your email' : 'Car & bike care\nat your doorstep',
            subtitle: _awaitingOtp
                ? 'Enter the code we sent to ${usernameController.text.trim()}.'
                : 'Create your free account — it takes a minute.',
          ),
          const SizedBox(height: 20),
          AuthCard(child: _awaitingOtp ? _buildOtpVerifyStep() : _buildSignupFormStep()),
          if (!_awaitingOtp) ...[
            const SizedBox(height: 18),
            const AuthOrDivider(),
            const SizedBox(height: 18),
            AuthGuestButton(onTap: _guestTapped),
            const SizedBox(height: 16),
            AuthSwitchLink(
              question: 'Already have an account?',
              action: 'Log in',
              onTap: _openLogin,
            ),
          ],
          const SizedBox(height: 10),
          const AuthLegalNote(),
        ],
      ),
    );
  }

  Widget _buildSignupFormStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthField(
          label: 'Email',
          controller: usernameController,
          hint: 'you@example.com',
          icon: Icons.alternate_email_rounded,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        AuthField(
          label: 'Phone number',
          controller: phoneController,
          hint: '98765 43210',
          icon: Icons.phone_rounded,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        AuthField(
          label: 'Create a password',
          controller: passwordController,
          hint: 'At least 6 characters',
          icon: Icons.lock_outline_rounded,
          obscure: _obscurePassword,
          onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!_isLoading) _handleSignUp();
          },
        ),
        const SizedBox(height: 18),
        AuthPrimaryButton(
          label: 'Create account',
          loading: _isLoading,
          onTap: _handleSignUp,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mark_email_read_outlined, size: 16, color: AppColors.mut),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                "We'll email you a code to confirm.",
                style: TextStyle(color: AppColors.mut, fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Shown once the confirmation code has been sent (see _handleSignUp).
  Widget _buildOtpVerifyStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthField(
          label: 'Code from your email',
          controller: otpController,
          hint: '6-digit code',
          icon: Icons.password_rounded,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!_verifyingOtp) _verifySignupOtp();
          },
        ),
        const SizedBox(height: 18),
        AuthPrimaryButton(
          label: 'Verify & continue',
          loading: _verifyingOtp,
          onTap: _verifySignupOtp,
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: _verifyingOtp ? null : _resendSignupOtp,
              style: TextButton.styleFrom(foregroundColor: AppColors.txt),
              child: const Text('Resend code', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            TextButton(
              onPressed: _verifyingOtp
                  ? null
                  : () => setState(() {
                        _awaitingOtp = false;
                        otpController.clear();
                      }),
              style: TextButton.styleFrom(foregroundColor: AppColors.mut),
              child: const Text('Change email', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ],
    );
  }
}
