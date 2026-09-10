import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/custom_textfield.dart';
import '../widgets/notification_permission_dialog.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
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
      );

      // Delivery partner accounts sign up through this same screen —
      // detected purely by email convention (delivery1@reperi.com,
      // delivery2@..., etc., matching the prefix used everywhere else
      // for these accounts). When it matches, also create the
      // delivery_partners profile row so the account can log into
      // web/delivery.html, which looks a partner up by email.
      await _maybeCreateDeliveryPartnerProfile(email);

      if (!mounted) return;

      // Show the branded rationale before the OS permission dialog, now
      // that the user has just taken a deliberate action (signing up) —
      // not at app launch, where there's no context for why. Awaited
      // before navigating so the dialog isn't orphaned by the route swap
      // below.
      await showNotificationPermissionPrimer(context);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Creates the matching `delivery_partners` row for delivery-partner
  /// accounts (email starting with "delivery", e.g. delivery1@reperi.com)
  /// — the same convention web/delivery.html's own register form uses.
  /// `id` is left out entirely so its SERIAL default (1, 2, 3, ...)
  /// applies; it's unrelated to the Supabase Auth user id. Runs quietly:
  /// a failure here (duplicate email, RLS, etc.) doesn't block the normal
  /// signup flow, since this account still works as a regular customer
  /// account either way — it just wouldn't be able to log into
  /// delivery.html until the row exists.
  Future<void> _maybeCreateDeliveryPartnerProfile(String email) async {
    final username = email.split('@').first.toLowerCase();
    if (!username.startsWith('delivery')) return;

    try {
      await Supabase.instance.client.from('delivery_partners').insert({
        'email': email,
        // Supabase Auth already stores the real credential securely
        // server-side — this column is redundant, but NOT NULL in the
        // given schema, so a fixed placeholder satisfies the constraint
        // without duplicating (or exposing) the actual password.
        'password_hash': 'managed_by_supabase_auth',
        'status': 'active',
      });
    } catch (e) {
      // Swallowed deliberately — see doc comment above.
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
                      height: 220,
                      width: double.infinity,
                      child: Image.asset(
                        'assets/images/login.png',
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(
                            Icons.shield_rounded,
                            size: 80,
                            color: Color(0xFFD4A017),
                          ),
                        ),
                      ),
                    ),

                    /// ── PARTNER NETWORK ───────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _goldLine(),
                          const SizedBox(width: 12),
                          const Text(
                            'PARTNER NETWORK',
                            style: TextStyle(
                              color: Color(0xFFD4A017),
                              fontSize: 12,
                              letterSpacing: 3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _goldLine(),
                        ],
                      ),
                    ),

                    const SizedBox(height: 6),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _goldLine(width: 20),
                        const SizedBox(width: 10),
                        const Text(
                          'PREMIUM VEHICLE CARE',
                          style: TextStyle(
                            color: Color(0xFF666666),
                            fontSize: 10,
                            letterSpacing: 2.5,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _goldLine(width: 20),
                      ],
                    ),

                    const SizedBox(height: 28),

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
                    const SizedBox(height: 8),
                    const Text(
                      'Join the premium automotive ecosystem',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 15,
                        height: 1.55,
                      ),
                    ),

                    const SizedBox(height: 28),

                    /// ── SIGNUP CARD ────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _buildSignupCard(),
                    ),

                    const SizedBox(height: 24),

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
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LoginScreen()),
                            );
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

                   const SizedBox(height: 36),
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
          GestureDetector(
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