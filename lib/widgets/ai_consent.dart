import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

/// Explicit opt-in before anything is sent to the third-party AI service
/// (Anthropic's Claude API, via our `ask-ai-chat` function).
///
/// Shown the first time the customer opens Ask AI. Nothing is sent until
/// they tap "Accept & Enable AI Features". "Not now" closes it and the AI
/// chat does not open. The answer is remembered on this device.
const String _kAiConsentKey = 'ai_consent_accepted_v1';

Future<bool> hasAiConsent() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAiConsentKey) ?? false;
  } catch (_) {
    return false;
  }
}

/// Turns AI features off again (e.g. from a settings toggle).
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
                'Get instant help from Ask AI',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.txt, fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'Describe the problem or snap a photo — Ask AI suggests the right fix in seconds. '
                'It\'s powered by our trusted AI partner.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.txt.withOpacity(0.8), fontSize: 13.5, height: 1.45),
              ),
              const SizedBox(height: 18),
              point(Icons.chat_bubble_outline_rounded, AppColors.accent, 'Only this is shared with our AI partner',
                  'Your Ask AI chat, any photo you add, and your vehicle\'s make & model.'),
              point(Icons.lock_rounded, const Color(0xFF1FAA59), 'Your details stay private',
                  'No name, phone, email, address or payment details.'),
              const SizedBox(height: 2),
              Center(
                child: TextButton(
                  onPressed: () => launchUrl(_privacy, mode: LaunchMode.externalApplication),
                  child: Text('Read our Privacy Policy',
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
                    child: Text('Accept & Enable AI Features',
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
