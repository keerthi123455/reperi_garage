import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_dashboard_screen.dart';
import 'fleet_dashboard_screen.dart';
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

    // Garage/fleet logins never touch Supabase Auth (they're checked
    // against their own bcrypt-hashed tables via edge functions), so a
    // Supabase session check alone would never see them. Checked BEFORE
    // the customer session below on purpose: fleet login in particular is
    // only ever reached from inside the customer-facing HomeScreen (see
    // home_screen.dart's _openFleetLogin), so a device with a completed
    // fleet login has an active customer session too almost every time —
    // checking customer first would always win and land a fleet operator
    // on HomeScreen instead of their own dashboard. Both screens' own
    // _logout() clears these same keys, so a real sign-out still lands on
    // LoginScreen as expected.
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    if (prefs.getBool('admin_logged_in') == true) {
      final adminId = prefs.getString('admin_id');
      if (adminId != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => AdminDashboardScreen(adminId: adminId)),
        );
        return;
      }
    }

    if (prefs.getBool('fleet_logged_in') == true) {
      final fleetUserId = prefs.getString('fleet_user_id');
      if (fleetUserId != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FleetDashboardScreen(
              fleetUser: {
                'id': fleetUserId,
                'company_name': prefs.getString('fleet_company') ?? 'N/A',
                'username': prefs.getString('fleet_username') ?? '',
              },
            ),
          ),
        );
        return;
      }
    }

    // Customer login goes through Supabase Auth, which already persists
    // its own session locally — currentUser is non-null here on a cold
    // start as long as that session hasn't expired or been signed out.
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
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
    // Measured directly from the device rather than relying on a fixed
    // aspect ratio — the artwork itself is a 720x1280 portrait image, but
    // this makes it fill the actual screen edge-to-edge on any phone,
    // whatever its real aspect ratio happens to be.
    final screenSize = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: Stack(
        children: [
          // Splash artwork — sized to the device's own measured
          // dimensions and BoxFit.cover, so it fills the entire screen
          // (including behind the status bar/notch) instead of floating
          // centered in a letterboxed box. BoxFit.cover crops whatever
          // sliver doesn't match the device's exact aspect ratio, which
          // is the right tradeoff here — full-bleed beats uncropped.
          FadeTransition(
            opacity: _fadeAnim,
            child: SizedBox(
              width: screenSize.width,
              height: screenSize.height,
              child: Image.asset(
                "assets/images/splash_screen.png",
                fit: BoxFit.cover,
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