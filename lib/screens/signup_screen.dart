import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/error_display.dart';
import 'home_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0C),
      body: Stack(
        children: [
          /// ── BACKGROUND GLOW ───────────────────────────────────────
          Positioned(
            bottom: 120,
            left: -100,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD4A017).withOpacity(0.06),
              ),
            ),
          ),

          /// ── CONTENT ───────────────────────────────────────────────
         SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [

                    /// ── HERO IMAGE ────────────────────────────────────
                    SizedBox(
                      height: 110,
                      width: double.infinity,
                      child: Image.asset(
                        'assets/images/login.jpeg',
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                      ),
                    ),

                    const SizedBox(height: 10),

                    /// ── HEADLINE ──────────────────────────────────────
                    const Text(
                      'Create Account',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),

                    const SizedBox(height: 16),

                    /// ── SIGNUP CARD ────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _buildSignupCard(),
                    ),

                    const SizedBox(height: 14),

                    /// ── LOGIN LINK ─────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Already have an account?  ',
                          style: TextStyle(
                            color: Color(0xFF777777),
                            fontSize: 14,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            // This screen is only ever reached by pushing
                            // on top of LoginScreen (its "Register Now"
                            // link), so the one already underneath is
                            // right there — pop back to it instead of
                            // pushReplacement, which would leave a
                            // second, redundant LoginScreen stacked below
                            // the original one.
                            Navigator.pop(context);
                          },
                          child: const Text(
                            'Sign In',
                            style: TextStyle(
                              color: Color(0xFFD4A017),
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),

                   const SizedBox(height: 16),
                      ],
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
  

  // ── HELPERS ────────────────────────────────────────────────────────────────

  Widget _goldLine({double width = 36}) => Container(
        width: width,
        height: 1,
        color: const Color(0xFFD4A017),
      );

  // ── SIGNUP CARD ────────────────────────────────────────────────────────────
  Widget _buildSignupCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
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
      child: _awaitingOtp ? _buildOtpVerifyStep() : _buildSignupFormStep(),
    );
  }

  Widget _buildSignupFormStep() {
    return Column(
      children: [
        /// EMAIL
        _buildInputField(
          controller: usernameController,
          hint: 'Email',
          icon: Icons.person_outline_rounded,
          keyboardType: TextInputType.emailAddress,
        ),

        const SizedBox(height: 14),

        /// PHONE
        _buildInputField(
          controller: phoneController,
          hint: 'Phone Number',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
        ),

        const SizedBox(height: 14),

        /// PASSWORD
        _buildPasswordField(),

        const SizedBox(height: 22),

        /// SIGN UP BUTTON
        _buildSignUpButton(),

        const SizedBox(height: 28),

        /// DIVIDER
        Row(
          children: [
            Expanded(
                child: Container(height: 1, color: const Color(0xFF222222))),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'secure sign up',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
            Expanded(
                child: Container(height: 1, color: const Color(0xFF222222))),
          ],
        ),
      ],
    );
  }

  /// Shown once signUp() sends a confirmation code instead of returning a
  /// session directly (see _handleSignUp's response.session check).
  Widget _buildOtpVerifyStep() {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFD4A017).withOpacity(0.12),
          ),
          child: const Icon(Icons.mark_email_read_rounded, color: Color(0xFFD4A017), size: 30),
        ),
        const SizedBox(height: 16),
        const Text(
          'Verify Your Email',
          style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the code we sent to ${usernameController.text.trim()}.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 20),
        _buildInputField(
          controller: otpController,
          hint: '6-digit code',
          icon: Icons.password_rounded,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _verifyingOtp ? null : _verifySignupOtp,
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
              child: _verifyingOtp
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                    )
                  : const Text(
                      'VERIFY & CONTINUE',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _verifyingOtp ? null : _resendSignupOtp,
              child: const Text('Resend code', style: TextStyle(color: Color(0xFFD4A017), fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: _verifyingOtp
                  ? null
                  : () => setState(() {
                        _awaitingOtp = false;
                        otpController.clear();
                      }),
              child: const Text('Change email', style: TextStyle(color: Colors.white54)),
            ),
          ],
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

  Widget _buildSignUpButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _handleSignUp,
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
                  'SIGN UP',
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
}