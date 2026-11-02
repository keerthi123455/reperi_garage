import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

/// Explicit opt-in before anything is sent to the third-party AI service.
///
/// This file is written to satisfy App Store Review Guidelines 5.1.1(i)
/// and 5.1.2(i): the dialog must NAME the third party (not "our AI
/// partner"), say WHAT is sent, confirm WHAT ISN'T sent, and link to the
/// Privacy Policy — all BEFORE the Accept button. The choice is remembered
/// per device and can be revoked from the drawer / Settings.
///
/// Bumped from v1 to v2 the day we changed the dialog to NAME Anthropic
/// (Claude) explicitly, so every existing user is re-prompted with the
/// new, Apple-compliant wording even if they'd already accepted v1.
const String _kAiConsentKey = 'ai_consent_accepted_v2';

Future<bool> hasAiConsent() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAiConsentKey) ?? false;
  } catch (_) {
    return false;
  }
}

/// Turns AI features off again (e.g. from the drawer / a settings toggle).
/// After this the next Ask AI tap shows the consent dialog again.
Future<void> revokeAiConsent() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAiConsentKey);
  } catch (_) {}
}

/// Returns true if the customer has agreed (now or before).
Future<bool> ensureAiConsent(BuildContext context) async {
  if (await hasAiConsent()) return true;
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _AiConsentDialog(),
  );
  if (ok == true) {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAiConsentKey, true);
    } catch (_) {}
    return true;
  }
  return false;
}

class _AiConsentDialog extends StatelessWidget {
  const _AiConsentDialog();

  static final Uri _privacy = Uri.parse('https://reperi.in/privacy-policy.html');
  static final Uri _anthropicPrivacy = Uri.parse('https://www.anthropic.com/legal/privacy');

  @override
  Widget build(BuildContext context) {
    Widget point(IconData icon, Color color, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: AppColors.txt, fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(body, style: TextStyle(color: AppColors.txt.withOpacity(0.75), fontSize: 13, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        );

    return Dialog(
      backgroundColor: AppColors.surfaceRaised,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.15), shape: BoxShape.circle),
                  child: Icon(Icons.auto_awesome_rounded, color: AppColors.accent, size: 26),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Enable Ask AI',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.txt, fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                "Describe the problem or snap a photo and Ask AI will suggest the right fix in seconds.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.txt.withOpacity(0.8), fontSize: 13.5, height: 1.45),
              ),
              // ── Named recipient — the Apple-required bit ──────────────
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accent.withOpacity(0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.send_rounded, size: 18, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Where this goes',
                            style: TextStyle(color: AppColors.txt, fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 0.3)),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      "Your Ask AI messages are sent to Anthropic (makers of Claude), which generates the reply using the Claude Haiku model. "
                      "Anthropic does not use your messages to train its models.",
                      style: TextStyle(color: AppColors.txt.withOpacity(0.9), fontSize: 13, height: 1.5),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => launchUrl(_anthropicPrivacy, mode: LaunchMode.externalApplication),
                      child: Text("Read Anthropic's privacy policy",
                          style: TextStyle(color: AppColors.accent, fontSize: 12.5, fontWeight: FontWeight.w800, decoration: TextDecoration.underline)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              point(Icons.chat_bubble_outline_rounded, AppColors.accent, 'What Anthropic receives',
                  "Your Ask AI chat text, any photo you choose to add, and your vehicle's make and model."),
              point(Icons.lock_rounded, const Color(0xFF1FAA59), 'What is NEVER sent',
                  'Your name, phone number, email address, home address, vehicle number, or any payment details.'),
              point(Icons.toggle_off_outlined, AppColors.mut, 'You can turn this off any time',
                  'Side menu → "Disable Ask AI" removes the opt-in on this device.'),
              const SizedBox(height: 2),
              Center(
                child: TextButton(
                  onPressed: () => launchUrl(_privacy, mode: LaunchMode.externalApplication),
                  child: Text("Read Reperi's Privacy Policy",
                      style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccentDark,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('I agree',
                        maxLines: 1, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Not now', style: TextStyle(color: AppColors.mut, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
