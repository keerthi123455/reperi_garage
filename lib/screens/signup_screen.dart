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

  bool _isLoading = false;
  bool _obscurePassword = true;

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
      final supabase = Supabase.instance.client;

      await supabase.auth.signUp(
        email: email,
        password: password,
        data: {'phone': phone},
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      // pushReplacement only swaps this SignupScreen for HomeScreen —
      // LoginScreen (pushed underneath when the user tapped "Register
      // Now") would stay buried as the stack's first route. The bottom
      // nav's Home button pops back to whatever route is first, so a
      // freshly-registered user tapping Home would get popped all the
      // way back to that buried LoginScreen — looking like a logout.
      // Clearing the whole stack here guarantees Home is the first route.
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
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
      child: Column(
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
      ),
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