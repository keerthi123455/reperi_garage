import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

/// WEBSITE ONLY (never compiled into the apps — see
/// web_notification_permission.dart).
///
/// Why the website needs its own version of the notification prompt:
///  1. Browsers only show their real "Allow notifications?" popup if the
///     request happens directly inside the user's tap. The app's prompt
///     closes first and then goes through OneSignal's setup, so the browser
///     no longer treats it as a tap and silently shows nothing. Here, "Allow"
///     calls the browser's Notification.requestPermission() right inside the
///     tap, then tells OneSignal to subscribe.
///  2. If notifications are blocked for reperi.in, browsers refuse silently
///     forever; only the visitor can unblock them. So we show how, instead
///     of a prompt that does nothing.
///  3. iPhone/iPad Safari has NO web notifications in a normal tab — only
///     when Reperi is added to the Home Screen and opened from there. So in a
///     Safari tab we explain that instead.
///
/// Shown at most once per visit, so it doesn't pop up again after every
/// booking.

const _gold = Color(0xFFD4A017);
bool _shownThisVisit = false;

Future<void> showWebNotificationPrompt(BuildContext context) async {
  final permission = _permission();

  if (permission == 'granted') {
    // Already allowed: make sure OneSignal has this browser subscribed.
    _oneSignalOptIn();
    return;
  }

  if (_shownThisVisit) return;

  if (permission == 'unsupported') {
    // Only worth explaining on iPhone/iPad Safari (fixable by adding to the
    // Home Screen). Other browsers without web push: stay quiet.
    if (_isIOS() && !_isInstalled()) {
      _shownThisVisit = true;
      await _showAddToHomeScreen(context);
    }
    return;
  }

  _shownThisVisit = true;
  if (permission == 'denied') {
    await _showBlockedHelp(context);
  } else {
    await _showPrimer(context);
  }
}

// --------------------------------------------------------------- dialogs --

Future<void> _showPrimer(BuildContext context) async {
  final request = await showDialog<Future<String>>(
    context: context,
    builder: (ctx) => _DialogShell(
      icon: Symbols.notifications_active,
      title: 'Stay Updated',
      children: [
        _body(
          'We send notifications for booking confirmations, pickup & '
          'delivery status, and service reminders — that\'s it. '
          'No spam, ever.',
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: _SecondaryButton(
                label: 'Not Now',
                onTap: () => Navigator.pop(ctx),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PrimaryButton(
                label: 'Allow',
                // The browser request MUST start right here, inside the tap,
                // or the browser silently ignores it.
                onTap: () => Navigator.pop(ctx, _requestPermissionNow()),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  if (request == null) return; // Not Now
  final result = await request;
  if (result == 'granted') {
    _oneSignalOptIn();
  } else if (result == 'denied' && context.mounted) {
    await _showBlockedHelp(context);
  }
}

Future<void> _showBlockedHelp(BuildContext context) async {
  final steps = _unblockSteps();
  var stillBlocked = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => _DialogShell(
        icon: Symbols.notifications_off,
        title: 'Notifications Are Blocked',
        children: [
          _body('Turn them on to get booking, pickup and delivery updates:'),
          const SizedBox(height: 16),
          for (var i = 0; i < steps.length; i++) _Step(n: i + 1, text: steps[i]),
          if (stillBlocked) ...[
            const SizedBox(height: 8),
            _warning('Still blocked. If you\'ve changed the setting, refresh '
                'the page once.'),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _SecondaryButton(
                  label: 'Close',
                  onTap: () => Navigator.pop(ctx),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PrimaryButton(
                  label: 'Done',
                  onTap: () {
                    final p = _permission();
                    if (p == 'granted') {
                      _oneSignalOptIn();
                      Navigator.pop(ctx);
                    } else if (p == 'default') {
                      // Unblocked but not yet allowed: ask right now (still
                      // inside this tap, so the browser shows its popup).
                      _requestPermissionNow().then((r) {
                        if (r == 'granted') _oneSignalOptIn();
                      });
                      Navigator.pop(ctx);
                    } else {
                      setState(() => stillBlocked = true);
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
}

Future<void> _showAddToHomeScreen(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _DialogShell(
      icon: Symbols.add_to_home_screen,
      title: 'Get Booking Updates',
      children: [
        _body('On iPhone, notifications only work when Reperi is on your '
            'Home Screen:'),
        const SizedBox(height: 16),
        const _Step(n: 1, text: 'Tap the Share button (the square with an '
            'arrow) in Safari.'),
        const _Step(n: 2, text: 'Choose "Add to Home Screen", then "Add".'),
        const _Step(n: 3, text: 'Open Reperi from your Home Screen and tap '
            'Allow when asked.'),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: _PrimaryButton(
            label: 'Got It',
            onTap: () => Navigator.pop(ctx),
          ),
        ),
      ],
    ),
  );
}

List<String> _unblockSteps() {
  final ua = _userAgent();
  if (_isIOS()) {
    return [
      'Open your iPhone Settings → Notifications.',
      'Find "Reperi Garage" and turn on Allow Notifications.',
      'Come back here and tap Done.',
    ];
  }
  if (ua.contains('Android')) {
    return [
      'Tap the icon at the left of the address bar, then "Permissions".',
      'Turn Notifications on (or set them to "Allow").',
      'Also check your phone Settings → Apps → your browser → '
          'Notifications are on. Then tap Done.',
    ];
  }
  return [
    'Click the icon at the left of the address bar.',
    'Set Notifications to "Allow".',
    'Come back and click Done.',
  ];
}

// ------------------------------------------------------ browser helpers --

/// 'granted' | 'default' | 'denied' | 'unsupported'
String _permission() {
  try {
    final n = globalContext.getProperty<JSObject?>('Notification'.toJS);
    if (n == null) return 'unsupported';
    return n.getProperty<JSString>('permission'.toJS).toDart;
  } catch (_) {
    return 'unsupported';
  }
}

/// Calls the browser's Notification.requestPermission() IMMEDIATELY (the
/// call happens before this function's first await), so it must be invoked
/// directly from a tap handler. Resolves to the resulting permission.
Future<String> _requestPermissionNow() async {
  try {
    final n = globalContext.getProperty<JSObject?>('Notification'.toJS);
    if (n == null) return 'unsupported';
    final result = n.callMethod<JSPromise<JSString>>('requestPermission'.toJS);
    return (await result.toDart).toDart;
  } catch (_) {
    return _permission();
  }
}

/// Tells OneSignal (initialised in web/index.html) to subscribe this browser.
/// Safe to call repeatedly: does nothing if already subscribed.
void _oneSignalOptIn() {
  try {
    final deferred =
        globalContext.getProperty<JSObject?>('OneSignalDeferred'.toJS);
    if (deferred == null) return;
    void run(JSObject oneSignal) {
      try {
        oneSignal
            .getProperty<JSObject>('User'.toJS)
            .getProperty<JSObject>('PushSubscription'.toJS)
            .callMethod<JSAny?>('optIn'.toJS);
      } catch (_) {}
    }

    deferred.callMethod<JSAny?>('push'.toJS, run.toJS);
  } catch (_) {}
}

String _userAgent() {
  try {
    final nav = globalContext.getProperty<JSObject>('navigator'.toJS);
    return nav.getProperty<JSString>('userAgent'.toJS).toDart;
  } catch (_) {
    return '';
  }
}

bool _isIOS() {
  final ua = _userAgent();
  if (RegExp(r'iPhone|iPad|iPod').hasMatch(ua)) return true;
  try {
    final nav = globalContext.getProperty<JSObject>('navigator'.toJS);
    final touch = nav.getProperty<JSNumber>('maxTouchPoints'.toJS).toDartInt;
    return ua.contains('Macintosh') && touch > 1; // iPadOS "desktop" mode
  } catch (_) {
    return false;
  }
}

/// True when opened from the Home Screen (installed web app).
bool _isInstalled() {
  try {
    final nav = globalContext.getProperty<JSObject>('navigator'.toJS);
    final standalone = nav.getProperty<JSAny?>('standalone'.toJS);
    if (standalone != null && (standalone as JSBoolean).toDart) return true;
    final mq = globalContext.callMethod<JSObject>(
        'matchMedia'.toJS, '(display-mode: standalone)'.toJS);
    return mq.getProperty<JSBoolean>('matches'.toJS).toDart;
  } catch (_) {
    return false;
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

Widget _warning(String text) => Text(
      text,
      textAlign: TextAlign.center,
      style: GoogleFonts.manrope(
        fontSize: 12.5,
        height: 1.4,
        fontWeight: FontWeight.w700,
        color: const Color(0xFFE5484D),
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
