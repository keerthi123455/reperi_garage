import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../services/push_notification_service.dart';
import '../theme/app_colors.dart';

/// A branded "soft ask" shown right before the OS-level notification
/// permission dialog — explains why the app wants to notify the user
/// (booking/pickup status, not marketing) so they aren't hit with an
/// unexplained system prompt. Only tapping "Allow" here goes on to
/// trigger the real [PushNotificationService.requestPermission] — "Not
/// Now" backs out without spending the one shot Android/iOS gives an app
/// to show its native permission prompt, so the user can still be asked
/// again on a later login.
Future<void> showNotificationPermissionPrimer(BuildContext context) async {
  final allowed = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFE0B02A), Color(0xFFB8860B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFD4A017).withOpacity(0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                Symbols.notifications_active,
                color: AppColors.onAccentDark,
                size: 30,
                fill: 1,
                weight: 700,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Stay Updated',
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.txt,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'We send notifications for booking confirmations, pickup & '
              'delivery status, and service reminders — that\'s it. '
              'No spam, ever.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 13.5,
                height: 1.5,
                color: AppColors.mut,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: AppColors.line),
                      ),
                    ),
                    child: Text(
                      'Not Now',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        color: AppColors.mut,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4A017),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Allow',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w800,
                        color: AppColors.onAccentDark,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (allowed == true) {
    await PushNotificationService.requestPermission();
  }
}
