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

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  // Garage/admin "forgot password" — a two-step, email-verified reset.
  // Step 0 confirms the email+username pair is a real admin account (via
  // the admin-verify-identity edge function, which never exposes the
  // password column) then sends a one-time code to that email through
  // Supabase Auth's own email-OTP delivery. Step 1 verifies that code —
  // proving the requester actually owns the inbox — and only then calls
  // admin-reset-password, which hashes the new password server-side.
  // Nothing here can reset a garage's password from just an email+username
  // guess anymore, unlike the old direct-table-update version.
  Future<void> _forgotPasswordAdmin() async {
    final emailController = TextEditingController();
    final usernameController = TextEditingController();
    final otpController = TextEditingController();
    final passwordController = TextEditingController();

    // A throwaway client, isolated from Supabase.instance.client. The OTP
    // dance below (signInWithOtp/verifyOTP) sets whatever client runs it
    // as "logged in" — running it on the app-wide client would silently
    // replace/destroy a real customer's session if one was active on this
    // device, which is exactly what broke `user_id` on AI-chat reports
    // after someone reset a garage password. This client's session lives
    // only in memory and is disposed with the dialog, so it can never
    // touch the customer-facing auth state.
    final otpClient = SupabaseClient(
      _supabaseUrl,
      _supabaseAnonKey,
      // PKCE (the default flow) needs a persistent storage backend to hold
      // a code verifier across steps — this client never persists
      // anything and never survives a redirect, so implicit flow (which
      // doesn't need that storage) is the right fit here.
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );

    InputDecoration fieldDecoration(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: const Color(0xFF3A3A3A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF333333)),
          ),
        );

    Widget fieldLabel(String text) => Padding(
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

    await showDialog(
      context: context,
      builder: (context) {
        bool isLoading = false;
        int step = 0; // 0 = enter email/username, 1 = enter code + new password

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> sendCode() async {
              final email = emailController.text.trim();
              final username = usernameController.text.trim();

              if (email.isEmpty || username.isEmpty) {
                ErrorDisplay.showPremiumToast(
                  context,
                  message: 'Enter both the registered email and username.',
                  icon: Icons.info_outline_rounded,
                );
                return;
              }

              setDialogState(() => isLoading = true);
              try {
                final verify = await Supabase.instance.client.functions.invoke(
                  'admin-verify-identity',
                  body: {'email': email, 'username': username},
                );
                final verifyData = verify.data as Map<String, dynamic>?;

                if (verifyData?['valid'] != true) {
                  // context.mounted (not the outer LoginScreen's mounted) —
                  // this dialog can be cancelled while this request is
                  // in-flight without LoginScreen itself going anywhere,
                  // and updating a StatefulBuilder/context that's already
                  // been popped is exactly what crashes with a
                  // "deactivated widget" or dependents-not-empty error.
                  if (!context.mounted) return;
                  ErrorDisplay.showPremiumToast(
                    context,
                    message: 'That email and username don\'t match a garage account.',
                    icon: Icons.error_outline_rounded,
                    accent: const Color(0xFFE5484D),
                  );
                  setDialogState(() => isLoading = false);
                  return;
                }

                await otpClient.auth.signInWithOtp(
                  email: email,
                  shouldCreateUser: true,
                );

                if (!context.mounted) return;
                setDialogState(() {
                  isLoading = false;
                  step = 1;
                });
              } catch (e) {
                if (!context.mounted) return;
                ErrorDisplay.showPremiumError(context, error: e);
                setDialogState(() => isLoading = false);
              }
            }

            Future<void> confirmReset() async {
              final email = emailController.text.trim();
              final username = usernameController.text.trim();
              final code = otpController.text.trim();
              final newPassword = passwordController.text.trim();

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

              setDialogState(() => isLoading = true);
              try {
                final verifyResponse = await otpClient.auth.verifyOTP(
                  email: email,
                  token: code,
                  type: OtpType.email,
                );

                final accessToken = verifyResponse.session?.accessToken;
                if (accessToken == null) {
                  throw Exception('No session returned for that code');
                }

                // Passed explicitly rather than relying on the app-wide
                // client's current session — that session was never
                // touched by this flow in the first place (see otpClient
                // above), so it wouldn't have this OTP session anyway.
                final reset = await Supabase.instance.client.functions.invoke(
                  'admin-reset-password',
                  body: {'username': username, 'newPassword': newPassword},
                  headers: {'Authorization': 'Bearer $accessToken'},
                );

                final resetData = reset.data as Map<String, dynamic>?;
                if (!context.mounted) return;

                if (resetData?['success'] == true) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.pop(context);
                  ErrorDisplay.showPremiumToast(
                    context,
                    message: 'Password reset — sign in with your new one.',
                    icon: Icons.check_circle_rounded,
                    accent: const Color(0xFF3DD68C),
                  );
                } else {
                  ErrorDisplay.showPremiumToast(
                    context,
                    message: '${resetData?['error'] ?? 'Could not reset password — please try again.'}',
                    icon: Icons.error_outline_rounded,
                    accent: const Color(0xFFE5484D),
                  );
                  setDialogState(() => isLoading = false);
                }
              } catch (e) {
                if (!context.mounted) return;
                ErrorDisplay.showPremiumToast(
                  context,
                  message: 'That code is invalid or expired — request a new one.',
                  icon: Icons.error_outline_rounded,
                  accent: const Color(0xFFE5484D),
                );
                setDialogState(() => isLoading = false);
              }
            }

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
                  children: step == 0
                      ? [
                          fieldLabel('Email registered with Reperi'),
                          TextField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: Colors.white),
                            enabled: !isLoading,
                            decoration: fieldDecoration('your@email.com'),
                          ),
                          const SizedBox(height: 16),
                          fieldLabel('Username registered with Reperi'),
                          TextField(
                            controller: usernameController,
                            style: const TextStyle(color: Colors.white),
                            enabled: !isLoading,
                            decoration: fieldDecoration('your_username'),
                          ),
                        ]
                      : [
                          Text(
                            'We sent a 6-digit code to ${emailController.text.trim()}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          fieldLabel('Verification Code'),
                          TextField(
                            controller: otpController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            enabled: !isLoading,
                            decoration: fieldDecoration('123456'),
                          ),
                          const SizedBox(height: 16),
                          fieldLabel('New Password'),
                          TextField(
                            controller: passwordController,
                            obscureText: true,
                            style: const TextStyle(color: Colors.white),
                            enabled: !isLoading,
                            decoration: fieldDecoration('Enter new password'),
                          ),
                        ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          // Dropping focus before popping avoids a rare
                          // Flutter crash ('_dependents.isEmpty' assertion)
                          // that can fire if this dialog's TextField still
                          // has focus (and the keyboard is mid-animation)
                          // when its route gets torn down.
                          FocusManager.instance.primaryFocus?.unfocus();
                          Navigator.pop(context);
                        },
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFFD4A017)),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4A017),
                  ),
                  onPressed: isLoading ? null : (step == 0 ? sendCode : confirmReset),
                  child: isLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                          ),
                        )
                      : Text(
                          step == 0 ? 'Send Code' : 'Reset Password',
                          style: const TextStyle(color: Colors.black),
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
    otpController.dispose();
    passwordController.dispose();
    otpClient.dispose();
  }

  Future<void> _forgotPassword() async {
    final emailController = TextEditingController();

    InputDecoration fieldDecoration(String hint) => InputDecoration(
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

    await showDialog(
      context: context,
      builder: (context) {
        bool isLoading = false;
        bool sent = false;
        String? error;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> send() async {
              final email = emailController.text.trim();

              if (email.isEmpty) {
                setDialogState(() => error = 'Enter the email you signed up with.');
                return;
              }
              if (!email.contains('@')) {
                setDialogState(() => error = 'That doesn\'t look like a valid email address.');
                return;
              }

              setDialogState(() {
                isLoading = true;
                error = null;
              });

              try {
                // resetPasswordForEmail always resolves successfully
                // regardless of whether the email is actually registered —
                // that's Supabase's deliberate anti-enumeration behavior,
                // not a bug — so a customer who deleted their account
                // (which really does remove the auth user; see
                // delete-account/index.ts) would still see "check your
                // email" here forever, with no email ever arriving.
                // customer-verify-email checks first, the same "verify
                // then send" shape the garage/admin forgot-password flow
                // already uses via admin-verify-identity.
                final verifyResponse = await Supabase.instance.client.functions.invoke(
                  'customer-verify-email',
                  body: {'email': email},
                );
                final registered = (verifyResponse.data as Map?)?['registered'] == true;

                if (!registered) {
                  if (!context.mounted) return;
                  setDialogState(() {
                    isLoading = false;
                    error = 'No account found with that email.';
                  });
                  return;
                }

                final redirectUrl = kIsWeb
                    ? 'https://reperi.in/reset-password'
                    : 'reperi://reset-password';

                await Supabase.instance.client.auth.resetPasswordForEmail(
                  email,
                  redirectTo: redirectUrl,
                );

                // context.mounted, not the outer LoginScreen's mounted —
                // this dialog can be cancelled mid-request without
                // LoginScreen itself going anywhere.
                if (!context.mounted) return;
                setDialogState(() {
                  isLoading = false;
                  sent = true;
                });
              } catch (e) {
                if (!context.mounted) return;
                setDialogState(() {
                  isLoading = false;
                  error = 'Could not send the reset link. Please try again.';
                });
              }
            }

            void close() {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(context);
            }

            return Dialog(
              backgroundColor: const Color(0xFF262626),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: const Color(0xFFD4A017).withOpacity(0.25)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(scale: anim, child: child),
                      ),
                      child: Container(
                        key: ValueKey(sent),
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sent
                              ? const Color(0xFF3DD68C).withOpacity(0.12)
                              : const Color(0xFFD4A017).withOpacity(0.12),
                        ),
                        child: Icon(
                          sent ? Icons.mark_email_read_rounded : Icons.lock_reset_rounded,
                          color: sent ? const Color(0xFF3DD68C) : const Color(0xFFD4A017),
                          size: 30,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: sent
                          ? Column(
                              key: const ValueKey('sent-text'),
                              children: [
                                const Text(
                                  'Check Your Email',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'We sent a reset link to ${emailController.text.trim()} — '
                                  'tap it to choose a new password.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 13.5,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              key: const ValueKey('form-text'),
                              children: [
                                const Text(
                                  'Reset Your Password',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Enter the email you signed up with and we\'ll '
                                  'send you a link to pick a new password.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 22),
                    if (!sent) ...[
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !isLoading,
                        style: const TextStyle(color: Colors.white),
                        decoration: fieldDecoration('your@email.com'),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: error == null
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
                                        error!,
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
                              onPressed: isLoading ? null : close,
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
                              onPressed: isLoading ? null : send,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD4A017),
                                disabledBackgroundColor: const Color(0xFFD4A017).withOpacity(0.5),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                      ),
                                    )
                                  : const Text(
                                      'Send Link',
                                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ] else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: close,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD4A017),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text(
                            'GOT IT',
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    emailController.dispose();
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
        onRetry: _handleLogin,
      );

      setState(() => _isLoading = false);
    } catch (e) {
      if (!context.mounted) return;

      ErrorDisplay.showPremiumError(
        context,
        error: e,
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

          const SizedBox(height: 18),

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