import 'dart:async';
import 'dart:math';
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
  late AnimationController _logoController;
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  late AnimationController _progressController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  StreamSubscription<AuthState>? _authSubscription;
  bool _handledRecovery = false;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..forward();

    _logoScale = Tween<double>(
      begin: 0.4,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: Curves.elasticOut,
      ),
    );

    _logoOpacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: Curves.easeOut,
      ),
    );

    _logoController.forward();

// This listener handles the case where the recovery deep link arrives
// while SplashScreen is already mounted. For app cold-starts directly
// from the recovery link, see main.dart's listener + the
// isPasswordRecoveryInProgress flag checked in _navigate() below —
// that one is attached before this screen exists and can't miss it.
_authSubscription =
    Supabase.instance.client.auth.onAuthStateChange.listen(
  (data) {
    print('================================');
    print('AUTH EVENT: ${data.event}');
    print('SESSION: ${data.session}');
    print('================================');

    if (data.event == AuthChangeEvent.passwordRecovery) {
      print('PASSWORD RECOVERY DETECTED');

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
    await Future.delayed(const Duration(milliseconds: 3200));

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

  _logoController.dispose();
  _rotationController.dispose();
  _pulseController.dispose();
  _progressController.dispose();

  super.dispose();
}

  Widget buildPulseRing({
    required double size,
    required double delay,
  }) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) {
        double value = (_pulseController.value + delay) % 1;

        return Transform.scale(
          scale: 1 + value,
          child: Opacity(
            opacity: (1 - value) * 0.5,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFFD54F),
                  width: 2,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  Color(0xFF241600),
                  Color(0xFF0D0D0D),
                  Color(0xFF000000),
                ],
              ),
            ),
          ),

          // Top Glow
          Positioned(
            top: -150,
            left: -120,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFD54F).withOpacity(.12),
              ),
            ),
          ),

          // Bottom Glow
          Positioned(
            bottom: -180,
            right: -120,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFB300).withOpacity(.18),
              ),
            ),
          ),

          // Floating particles
          const Positioned.fill(
            child: ParticleLayer(),
          ),

          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 340,
                  height: 340,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      buildPulseRing(
                        size: 180,
                        delay: 0,
                      ),

                      buildPulseRing(
                        size: 180,
                        delay: .33,
                      ),

                      buildPulseRing(
                        size: 180,
                        delay: .66,
                      ),

                      // Gold Glow
                      Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFFFD54F,
                              ).withOpacity(.7),
                              blurRadius: 120,
                              spreadRadius: 25,
                            ),
                          ],
                        ),
                      ),

                      // Rotating Ring
                      AnimatedBuilder(
                        animation: _rotationController,
                        builder: (_, __) {
                          return Transform.rotate(
                            angle:
                                _rotationController.value * 2 * pi,
                            child: Container(
                              width: 270,
                              height: 270,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(
                                    0xFFFFD54F,
                                  ).withOpacity(.3),
                                  width: 2,
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      // Logo
                      FadeTransition(
                        opacity: _logoOpacity,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: Hero(
                            tag: "reperi_logo",
                            child: Image.asset(
                              "assets/images/login.png",
                              width: 240,
                              height: 240,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 25),

                TweenAnimationBuilder(
                  duration: const Duration(milliseconds: 1800),
                  tween: Tween<double>(
                    begin: 40,
                    end: 0,
                  ),
                  builder: (_, value, child) {
                    return Transform.translate(
                      offset: Offset(0, value),
                      child: Opacity(
                        opacity: 1 - (value / 40),
                        child: child,
                      ),
                    );
                  },
                  child: const Text(
                    "PREMIUM VEHICLE CARE",
                    style: TextStyle(
                      color: Color(0xFFFFD54F),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Premium Loading Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _progressController,
              builder: (_, __) {
                return Container(
                  height: 4,
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: const Color(
                          0xFFFFD54F,
                        ).withOpacity(.7),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                  child: LinearProgressIndicator(
                    value: _progressController.value,
                    backgroundColor: Colors.white10,
                    valueColor:
                        const AlwaysStoppedAnimation(
                      Color(0xFFFFD54F),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ParticleLayer extends StatelessWidget {
  const ParticleLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: ParticlePainter(),
      ),
    );
  }
}

class ParticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    for (int i = 0; i < 35; i++) {
      final x = (size.width / 35) * i;
      final y = (size.height * ((i * 37) % 100)) / 100;

      paint.color =
          const Color(0xFFFFD54F).withOpacity(.12);

      canvas.drawCircle(
        Offset(x, y),
        2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}