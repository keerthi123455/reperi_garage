import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/ai_chat_session.dart';
import 'login_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState
    extends State<ResetPasswordScreen> {
  final TextEditingController passwordController =
      TextEditingController();

  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool loading = false;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  String? _error;

  // Clicking the password-reset email link authenticates a real Supabase
  // session on the app-wide client (main.dart's onAuthStateChange listener
  // fires AuthChangeEvent.passwordRecovery and lands here) — that's what
  // lets updateUser() below change the password without re-entering the
  // old one. But if the customer backs out of this screen without ever
  // submitting a new password, that session was otherwise left fully
  // valid: the next app launch (SplashScreen checking currentUser) would
  // log them straight in, password never actually touched. Tracking
  // whether the update actually succeeded is what _abandonAndSignOut
  // below uses to close that hole.
  bool _passwordUpdated = false;

  Future<void> _abandonAndSignOut() async {
    if (_passwordUpdated) return;
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      // Best-effort — if this fails there's nothing more to do here; the
      // customer is leaving this screen either way.
    }
  }

  Future<void> updatePassword() async {
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    if (password.isEmpty || confirmPassword.isEmpty) {
      setState(() => _error = 'Please fill in both fields.');
      return;
    }

    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    if (password != confirmPassword) {
      setState(() => _error = 'Those passwords don\'t match.');
      return;
    }

    setState(() {
      loading = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );

      _passwordUpdated = true;

      if (!mounted) return;
      await _showSuccessDialog();

      await Supabase.instance.client.auth.signOut();
      AiChatSession.clear();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not update your password. Please try again.');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _showSuccessDialog() {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFF262626),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: const Color(0xFF3DD68C).withOpacity(0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                builder: (context, value, child) => Transform.scale(scale: value, child: child),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3DD68C).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Color(0xFF3DD68C), size: 36),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Password Updated',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your password has been changed. Sign in with your new password to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 13.5, height: 1.5),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4A017),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'CONTINUE TO LOGIN',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, letterSpacing: 0.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    passwordController.dispose();
    confirmPasswordController.dispose();
    // Fallback for any exit path that disposes this screen without going
    // through the PopScope handler below (e.g. this widget being removed
    // some other way than a back-button pop) — fire-and-forget is fine
    // since signOut() doesn't depend on this widget still being alive.
    _abandonAndSignOut();
    super.dispose();
  }

  /// Explicit back-button handling — signs out of the recovery session
  /// (only a no-op if the password was actually updated) and lands the
  /// customer back on LoginScreen, rather than letting a back-press just
  /// background/exit the app with that session still fully valid.
  Future<void> _exitAbandoned() async {
    await _abandonAndSignOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60),
      filled: true,
      fillColor: const Color(0xFF1C1C1C),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF333333)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF333333)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD4A017), width: 1.4),
      ),
      suffixIcon: Semantics(
        button: true,
        label: obscure ? 'Show password' : 'Hide password',
        child: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: Colors.white38,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitAbandoned();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1C1C1C),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4A017).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_reset_rounded, color: Color(0xFFD4A017), size: 36),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Set a New Password',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose a new password for your account. Make it something '
                  'you\'ll remember.',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 34),

                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDecoration(
                    label: 'New Password',
                    obscure: obscurePassword,
                    onToggle: () => setState(() => obscurePassword = !obscurePassword),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: obscureConfirmPassword,
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDecoration(
                    label: 'Confirm Password',
                    obscure: obscureConfirmPassword,
                    onToggle: () => setState(() => obscureConfirmPassword = !obscureConfirmPassword),
                  ),
                ),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _error == null
                      ? const SizedBox.shrink(key: ValueKey('no-error'))
                      : Padding(
                          key: const ValueKey('error'),
                          padding: const EdgeInsets.only(top: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFE5484D), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(color: Color(0xFFE5484D), fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),

                const SizedBox(height: 8),
                Text(
                  'Use at least 6 characters.',
                  style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12),
                ),

                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: loading
                          ? null
                          : const LinearGradient(colors: [Color(0xFFD4A017), Color(0xFFF5C842)]),
                      color: loading ? const Color(0xFF3A3A3A) : null,
                    ),
                    child: ElevatedButton(
                      onPressed: loading ? null : updatePassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: loading
                            ? const SizedBox(
                                key: ValueKey('spinner'),
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                                ),
                              )
                            : const Text(
                                'UPDATE PASSWORD',
                                key: ValueKey('label'),
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
