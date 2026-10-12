import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

/// WEBSITE ONLY (never compiled into the apps — see
/// web_location_permission.dart).
///
/// Browsers only let a website show their real "Allow location?" popup while
/// the visitor hasn't decided yet. Once they tap Block, the site can never
/// ask again; only the visitor can undo it in the browser's settings. So:
///   - already allowed  -> go ahead silently
///   - not decided yet  -> our branded "soft ask" first (like the
///                         notification primer); "Allow" goes on to the
///                         browser's real popup
///   - blocked          -> short, browser-specific steps to unblock it, with
///                         a "Try Again" button

const _gold = Color(0xFFD4A017);

/// Returns true when the caller should go ahead and request the location
/// (which shows the browser's own popup if it hasn't been decided yet).
/// Returns false if the visitor tapped "Not Now" or location is blocked
/// (they've already been shown why, so the caller should just stop).
Future<bool> askForWebLocation(BuildContext context) async {
  final state = await _permissionState();
  if (state == 'granted') return true;

  // Make sure we're not mid-build (e.g. when called from initState).
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return false;

  if (state == 'denied') {
    return _showBlockedHelp(context);
  }
  // 'prompt', or 'unknown' on browsers without the Permissions API.
  return _showPrimer(context);
}

/// For when the browser itself refused (e.g. location blocked by the phone's
/// own settings, which the permission check can't always see).
Future<void> showWebLocationBlockedHelp(BuildContext context) async {
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return;
  await _showBlockedHelp(context);
}

// --------------------------------------------------------------- dialogs --

Future<bool> _showPrimer(BuildContext context) async {
  final allowed = await showDialog<bool>(
    context: context,
    builder: (ctx) => _DialogShell(
      icon: Symbols.my_location,
      title: 'Use Your Location?',
      children: [
        _body(
          'We use your location only to fill in your pickup address and to '
          'send roadside help to the right spot. Tap Allow, then choose '
          '"Allow" on the next popup.',
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: _SecondaryButton(
                label: 'Not Now',
                onTap: () => Navigator.pop(ctx, false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PrimaryButton(
                label: 'Allow',
                onTap: () => Navigator.pop(ctx, true),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return allowed == true;
}

Future<bool> _showBlockedHelp(BuildContext context) async {
  final steps = _unblockSteps();
  var stillBlocked = false;

  final retry = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => _DialogShell(
        icon: Symbols.location_off,
        title: 'Location Is Blocked',
        children: [
          _body('Your browser is blocking location for reperi.in. '
              'To turn it back on:'),
          const SizedBox(height: 16),
          for (var i = 0; i < steps.length; i++) _Step(n: i + 1, text: steps[i]),
          if (stillBlocked) ...[
            const SizedBox(height: 8),
            Text(
              'Still blocked. If you\'ve changed the setting, refresh the '
              'page once and try again.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFE5484D),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _SecondaryButton(
                  label: 'Close',
                  onTap: () => Navigator.pop(ctx, false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PrimaryButton(
                  label: 'Try Again',
                  onTap: () async {
                    final s = await _permissionState();
                    if (!ctx.mounted) return;
                    if (s == 'denied') {
                      setState(() => stillBlocked = true);
                    } else {
                      Navigator.pop(ctx, true);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return retry == true;
}

List<String> _unblockSteps() {
  final ua = _userAgent();
  final isIOS = RegExp(r'iPhone|iPad|iPod').hasMatch(ua) ||
      (ua.contains('Macintosh') && _maxTouchPoints() > 1);
  final isAndroid = ua.contains('Android');

  if (isIOS && RegExp(r'CriOS|FxiOS|EdgiOS').hasMatch(ua)) {
    return [
      'Open your iPhone Settings and find this browser (e.g. Chrome).',
      'Tap Location and choose "While Using the App".',
      'Come back here and tap Try Again.',
    ];
  }
  if (isIOS) {
    return [
      'Tap the "aA" (or "⋯") button next to the address bar, then '
          '"Website Settings".',
      'Set Location to "Allow".',
      'Come back and tap Try Again. Still not working? In iPhone Settings → '
          'Privacy & Security → Location Services → Safari Websites, choose '
          '"While Using the App".',
    ];
  }
  if (isAndroid) {
    return [
      'Tap the icon at the left of the address bar, then "Permissions".',
      'Turn Location on (or set it to "Allow").',
      'Make sure your phone\'s Location is switched on, then tap Try Again.',
    ];
  }
  return [
    'Click the icon at the left of the address bar.',
    'Set Location to "Allow".',
    'Come back and click Try Again.',
  ];
}

// ------------------------------------------------------ browser helpers --

/// 'granted' | 'prompt' | 'denied' | 'unknown'
Future<String> _permissionState() async {
  try {
    final navigator = globalContext.getProperty<JSObject>('navigator'.toJS);
    final permissions = navigator.getProperty<JSObject?>('permissions'.toJS);
    if (permissions == null) return 'unknown';
    final descriptor = JSObject()
      ..setProperty('name'.toJS, 'geolocation'.toJS);
    final status = await permissions
        .callMethod<JSPromise<JSObject>>('query'.toJS, descriptor)
        .toDart;
    return status.getProperty<JSString>('state'.toJS).toDart;
  } catch (_) {
    return 'unknown';
  }
}

String _userAgent() {
  try {
    final navigator = globalContext.getProperty<JSObject>('navigator'.toJS);
    return navigator.getProperty<JSString>('userAgent'.toJS).toDart;
  } catch (_) {
    return '';
  }
}

int _maxTouchPoints() {
  try {
    final navigator = globalContext.getProperty<JSObject>('navigator'.toJS);
    return navigator.getProperty<JSNumber>('maxTouchPoints'.toJS).toDartInt;
  } catch (_) {
    return 0;
  }
}

// ------------------------------------------- UI (matches notification primer) --

Widget _body(String text) => Text(
      text,
      textAlign: TextAlign.center,
      style: GoogleFonts.manrope(
        fontSize: 13.5,
        height: 1.5,
        color: AppColors.mut,
      ),
    );

class _DialogShell extends StatelessWidget {
  const _DialogShell({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
        child: SingleChildScrollView(
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
                      color: _gold.withOpacity(0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  color: AppColors.onAccentDark,
                  size: 30,
                  fill: 1,
                  weight: 700,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.txt,
                ),
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _gold.withOpacity(0.18),
            ),
            child: Text(
              '$n',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _gold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.45,
                color: AppColors.txt,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: _gold,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontWeight: FontWeight.w800,
          color: AppColors.onAccentDark,
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.line),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontWeight: FontWeight.w700,
          color: AppColors.mut,
        ),
      ),
    );
  }
}
