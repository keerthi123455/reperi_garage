import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'reset_password_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import '../main.dart' show isPasswordRecoveryInProgress;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Total time the splash screen stays up — covers cold launch, Supabase
  // init (already done by the time this widget builds, since main()
  // awaits it before runApp), the auth-session check below, and the
  // fade/progress-bar animation all playing out.
  static const _splashDuration = Duration(milliseconds: 1200);

  late AnimationController _fadeController;
  late AnimationController _progressController;
  late Animation<double> _fadeAnim;

  StreamSubscription<AuthState>? _authSubscription;
  bool _handledRecovery = false;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();

    _progressController = AnimationController(
      vsync: this,
      duration: _splashDuration,
    )..forward();

    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

// This listener handles the case where the recovery deep link arrives
// while SplashScreen is already mounted. For app cold-starts directly
// from the recovery link, see main.dart's listener + the
// isPasswordRecoveryInProgress flag checked in _navigate() below —
// that one is attached before this screen exists and can't miss it.
_authSubscription =
    Supabase.instance.client.auth.onAuthStateChange.listen(
  (data) {
    if (data.event == AuthChangeEvent.passwordRecovery) {

      _handledRecovery = true;

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const ResetPasswordScreen(),
        ),
      );
    }
  },
);

_navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(_splashDuration);

    if (!mounted) return;

    // The recovery flag is set in main.dart's listener, which is
    // attached right after Supabase.initialize() resolves — before
    // this screen even exists. That's the only listener guaranteed
    // to catch a password-recovery deep link on a cold app start.
    // _handledRecovery (set below) covers the case where the event
    // arrives while this screen is already mounted and alive.
    if (_handledRecovery || isPasswordRecoveryInProgress) return;

    final user = Supabase.instance.client.auth.currentUser;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            user != null
                ? const HomeScreen()
                : const LoginScreen(),
      ),
    );
  }

  @override
void dispose() {
  _authSubscription?.cancel();

  _fadeController.dispose();
  _progressController.dispose();

  super.dispose();
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: Stack(
        children: [
          // Splash artwork — sized to fit any screen instead of a
          // full-bleed cover, since the artwork itself is a tall
          // portrait image. On a wide laptop window, `cover` was
          // zooming in so far that only a sliver of the gold border
          // lines were visible. `contain` inside a capped box keeps it
          // looking right on phones, tablets, laptops, and desktops.
          Center(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420,
                  maxHeight: MediaQuery.sizeOf(context).height * 0.85,
                ),
                child: Image.asset(
                  "assets/images/splash_screen.png",
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          // Small loading bar
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: AnimatedBuilder(
                  animation: _progressController,
                  builder: (_, __) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: _progressController.value,
                        minHeight: 3,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation(
                          Color(0xFFFFD54F),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}