import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import 'vehicle_card.dart' show VehicleCartoonAvatar;

/// Shared look for the sign-up and login screens (light by default, follows
/// the app's light/dark choice through AppColors).

const Color kAuthGold = Color(0xFFD4A017);

/// REPERI wordmark with the gold bar — same as the app header.
class AuthWordmark extends StatelessWidget {
  const AuthWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'REPERI',
          style: GoogleFonts.manrope(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
            color: AppColors.txt,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(color: kAuthGold, borderRadius: BorderRadius.circular(2)),
        ),
      ],
    );
  }
}

/// The cartoon car and scooter side by side, gently floating.
class AuthHero extends StatefulWidget {
  const AuthHero({super.key, this.size = 84});

  final double size;

  @override
  State<AuthHero> createState() => _AuthHeroState();
}

class _AuthHeroState extends State<AuthHero> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      height: s + 12,
      width: s * 1.75,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = reduceMotion ? 0.5 : Curves.easeInOut.transform(_c.value);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 4 + t * 6,
                child: VehicleCartoonAvatar(isBike: false, size: s),
              ),
              Positioned(
                right: 0,
                top: 10 - t * 6,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.ink, width: 3),
                  ),
                  child: VehicleCartoonAvatar(isBike: true, size: s * 0.86),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AuthTitle extends StatelessWidget {
  const AuthTitle({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1.2,
            letterSpacing: -0.4,
            color: AppColors.txt,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.4,
            color: AppColors.mut,
          ),
        ),
      ],
    );
  }
}

/// White card holding the form.
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: child,
    );
  }
}

/// Label above + rounded field. Set [obscure] / [onToggleObscure] for a
/// password field with the eye button.
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.obscure,
    this.onToggleObscure,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.prefixText,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final bool? obscure;
  final VoidCallback? onToggleObscure;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final String? prefixText;

  @override
  Widget build(BuildContext context) {
    final isPassword = obscure != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 7),
          child: Text(
            label,
            style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.txt),
          ),
        ),
        Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(icon, color: kAuthGold, size: 22),
              const SizedBox(width: 10),
              if (prefixText != null) ...[
                Text(
                  prefixText!,
                  style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.txt),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  obscureText: obscure ?? false,
                  autocorrect: false,
                  enableSuggestions: !isPassword,
                  autofillHints: autofillHints,
                  textInputAction: textInputAction,
                  onSubmitted: onSubmitted,
                  style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.txt),
                  cursorColor: kAuthGold,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.mut),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              if (isPassword)
                IconButton(
                  tooltip: obscure! ? 'Show password' : 'Hide password',
                  onPressed: onToggleObscure,
                  icon: Icon(
                    obscure! ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: AppColors.mut,
                    size: 22,
                  ),
                )
              else
                const SizedBox(width: 14),
            ],
          ),
        ),
      ],
    );
  }
}

/// Big dark button (ink on light, light on dark).
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({super.key, required this.label, required this.onTap, this.loading = false});

  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.txt,
          foregroundColor: AppColors.ink,
          disabledBackgroundColor: AppColors.txt.withOpacity(0.7),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: AppColors.ink, strokeWidth: 2.5),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
      ),
    );
  }
}

class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: AppColors.line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.mut),
          ),
        ),
        Expanded(child: Container(height: 1, color: AppColors.line)),
      ],
    );
  }
}

/// "Continue as Guest — look around first".
class AuthGuestButton extends StatelessWidget {
  const AuthGuestButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.txt.withOpacity(0.25), width: 1.4),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: kAuthGold.withOpacity(0.16), shape: BoxShape.circle),
                child: const Icon(Icons.explore_rounded, color: kAuthGold, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Continue as Guest',
                      style: GoogleFonts.manrope(fontSize: 16.5, fontWeight: FontWeight.w800, color: AppColors.txt),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Look around first — sign up only when you book',
                      style: GoogleFonts.manrope(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3, color: AppColors.mut),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward_rounded, color: AppColors.txt, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Already have an account?  Log in" style line.
class AuthSwitchLink extends StatelessWidget {
  const AuthSwitchLink({super.key, required this.question, required this.action, required this.onTap});

  final String question;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '$question  ',
          style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.mut),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              action,
              style: GoogleFonts.manrope(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.txt,
                decoration: TextDecoration.underline,
                decorationColor: kAuthGold,
                decorationThickness: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "By continuing you agree to our Terms and Privacy Policy".
class AuthLegalNote extends StatelessWidget {
  const AuthLegalNote({super.key});

  static final Uri _terms = Uri.parse('https://reperi.in/terms.html');
  static final Uri _privacy = Uri.parse('https://reperi.in/privacy-policy.html');

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.mut, height: 1.5);
    final link = base.copyWith(color: AppColors.txt, fontWeight: FontWeight.w800, decoration: TextDecoration.underline);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('By continuing you agree to our ', style: base),
        GestureDetector(
          onTap: () => launchUrl(_terms, mode: LaunchMode.externalApplication),
          child: Text('Terms', style: link),
        ),
        Text(' and ', style: base),
        GestureDetector(
          onTap: () => launchUrl(_privacy, mode: LaunchMode.externalApplication),
          child: Text('Privacy Policy', style: link),
        ),
        Text('.', style: base),
      ],
    );
  }
}

/// Page frame: light background, safe area, centred column (max 460 wide),
/// scrolls with the keyboard.
class AuthPage extends StatelessWidget {
  const AuthPage({super.key, required this.children, this.topBar});

  final List<Widget> children;
  final Widget? topBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Column(
          children: [
            if (topBar != null) topBar!,
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
