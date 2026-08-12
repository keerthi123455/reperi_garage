import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'home_screen.dart';
import 'signup_screen.dart';
import 'admin_dashboard_screen.dart';
import 'package:reperi_garage/services/error_handler.dart';
import 'package:reperi_garage/widgets/error_display.dart';

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

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  Future<void> _forgotPasswordAdmin() async {
    final emailController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        bool isLoading = false;
        
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Reset Password'),
              backgroundColor: const Color(0xFF1A1A1A),
              titleTextStyle: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Email field
                    const Text(
                      'Email registered with Reperi',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white),
                      enabled: !isLoading,
                      decoration: InputDecoration(
                        hintText: 'your@email.com',
                        hintStyle: const TextStyle(color: Color(0xFF444444)),
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF333333)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Username field
                    const Text(
                      'Username registered with Reperi',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: usernameController,
                      style: const TextStyle(color: Colors.white),
                      enabled: !isLoading,
                      decoration: InputDecoration(
                        hintText: 'your_username',
                        hintStyle: const TextStyle(color: Color(0xFF444444)),
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF333333)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // New password field
                    const Text(
                      'New Password',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      enabled: !isLoading,
                      decoration: InputDecoration(
                        hintText: 'Enter new password',
                        hintStyle: const TextStyle(color: Color(0xFF444444)),
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF333333)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFFD4A017)),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4A017),
                  ),
                  onPressed: isLoading
                      ? null
                      : () async {
                          setDialogState(() => isLoading = true);

                          try {
                            final email = emailController.text.trim();
                            final username = usernameController.text.trim();
                            final newPassword = passwordController.text.trim();

                            // Validate inputs
                            if (email.isEmpty || username.isEmpty || newPassword.isEmpty) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('All fields are required'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              setDialogState(() => isLoading = false);
                              return;
                            }

                            // Find admin with matching email AND username
                            final response = await Supabase.instance.client
                                .from('admin')
                                .select()
                                .eq('email', email)
                                .eq('username', username)
                                .maybeSingle();

                            if (!mounted) return;

                            if (response == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Email and Username do not match. Please check and try again.',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              setDialogState(() => isLoading = false);
                              return;
                            }

                            // Update password
                            await Supabase.instance.client
                                .from('admin')
                                .update({'password': newPassword})
                                .eq('id', response['id']);

                            if (!mounted) return;

                            Navigator.pop(context);

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Row(
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.green),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Password reset successfully! Please login with your new password.',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: Colors.green.shade700,
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            setDialogState(() => isLoading = false);
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                          ),
                        )
                      : const Text(
                          'Reset Password',
                          style: TextStyle(color: Colors.black),
                        ),
                ),
              ],
            );
          },
        );
      },
    );

    emailController.dispose();
    usernameController.dispose();
    passwordController.dispose();
  }

  Future<void> _forgotPassword() async {
  final emailController = TextEditingController();

  await showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Reset Password'),
        content: TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: 'Enter your email',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            child: const Text('Send'),
            onPressed: () async {
              try {
                final email = emailController.text.trim();

                // Validate email
                if (email.isEmpty) {
                  ErrorDisplay.showErrorSnackBar(
                    context,
                    message: 'Please enter your email address.',
                  );
                  return;
                }

                if (!email.contains('@')) {
                  ErrorDisplay.showErrorSnackBar(
                    context,
                    message: 'Please enter a valid email address.',
                  );
                  return;
                }

                final redirectUrl = kIsWeb
                    ? 'https://reperi.in/reset-password'
                    : 'reperi://reset-password';

                await Supabase.instance.client.auth
                    .resetPasswordForEmail(
                  email,
                  redirectTo: redirectUrl,
                );

                if (!mounted) return;

                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.check_circle_outline_rounded, color: Colors.green),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Password reset email sent to your inbox. Please check and follow the link to reset your password.',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.green.shade700,
                    elevation: 6,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    margin: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 5),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                
                final errorMessage = ErrorHandler.getUserMessage(e);
                ErrorDisplay.showErrorSnackBar(
                  context,
                  message: errorMessage,
                );
              }
            },
          )
        ],
      );
    },
  );
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
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = usernameController.text.trim();
    final password = passwordController.text.trim();

    // ── Client-side validation ──
    if (email.isEmpty) {
      ErrorDisplay.showErrorSnackBar(
        context,
        message: isClient ? 'Please enter your email address.' : 'Please enter your username.',
      );
      return;
    }

    if (isClient && (!email.contains('@') || !email.contains('.'))) {
      ErrorDisplay.showErrorSnackBar(
        context,
        message: 'Please enter a valid email address.',
      );
      return;
    }

    if (password.isEmpty) {
      ErrorDisplay.showErrorSnackBar(
        context,
        message: 'Please enter your password.',
      );
      return;
    }

    if (password.length < 6) {
      ErrorDisplay.showErrorSnackBar(
        context,
        message: 'Password must be at least 6 characters long.',
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
        );

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        // Admin login via local database
        final response = await supabase
            .from('admin')
            .select()
            .eq('username', email)
            .eq('password', password);

        if (!mounted) return;

        if (response.isNotEmpty) {
          final adminId = response[0]['id'];
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => AdminDashboardScreen(adminId: adminId),
            ),
          );
        } else {
          ErrorDisplay.showErrorSnackBar(
            context,
            message: 'Garage username or password is incorrect. Please try again.',
          );
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (!context.mounted) return;

      // Map technical error to user-friendly message
      final errorMessage = ErrorHandler.getUserMessage(e);

      ErrorDisplay.showErrorSnackBar(
        context,
        message: errorMessage,
        onRetry: _handleLogin,
      );

      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Detect if we're on a wide screen (web/tablet)
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0C),
      body: Stack(
        children: [
          /// ── BACKGROUND GLOW ORBS ──────────────────────────────────
          Positioned(
            bottom: 120,
            right: isWide ? (screenWidth / 2 - 140) : -100,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD4A017).withOpacity(0.06),
              ),
            ),
          ),

          Positioned(
            top: -60,
            left: isWide ? (screenWidth / 2 - 160) : -80,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD4A017).withOpacity(0.04),
              ),
            ),
          ),

          /// ── CONTENT ───────────────────────────────────────────────
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Center(
                child: ConstrainedBox(
                  // KEY FIX: cap width at 480px so it doesn't stretch on web
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 0 : 0,
                      vertical: isWide ? 24 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        /// ── HERO IMAGE ──────────────────────────────
                        SizedBox(
                          height: isWide ? 160 : 220,
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

                        /// ── PARTNER NETWORK ─────────────────────────
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

                        /// ── HEADLINE ────────────────────────────────
                        const Text(
                          'Welcome Back',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Your vehicle's next service\nis just a tap away.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF888888),
                            fontSize: 15,
                            height: 1.55,
                          ),
                        ),

                        const SizedBox(height: 28),

                        /// ── LOGIN CARD ──────────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _buildLoginCard(),
                        ),

                        const SizedBox(height: 24),

                        /// ── REGISTER LINK ───────────────────────────
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

  // ── LOGIN CARD ─────────────────────────────────────────────────────────────
  Widget _buildLoginCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
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

          const SizedBox(height: 14),

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

          const SizedBox(height: 18),

          /// SIGN IN BUTTON
          _buildSignInButton(),

          const SizedBox(height: 24),

          /// LOGIN AS TOGGLE
          _buildLoginAsSection(),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(icon, color: const Color(0xFFD4A017), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
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
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A2A)),
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
      onTap: () => setState(() => isClient = value),
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
                : const Color(0xFF2A2A2A),
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