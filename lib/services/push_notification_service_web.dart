import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Web implementation, built directly against OneSignal's JavaScript Web
/// SDK via its deferred-command queue (`window.OneSignalDeferred`), since
/// the official `onesignal_flutter` package does not support Flutter Web.
///
/// Relies on web/index.html having set up:
///   window.OneSignalDeferred = window.OneSignalDeferred || [];
/// and loaded https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.page.js
class PushNotificationService {
  PushNotificationService._();

  static bool _initStarted = false;

  /// Queues a callback to run once OneSignal's web SDK has finished
  /// loading. Safe to call any time, including before the SDK script
  /// tag has finished downloading — that's the whole point of the
  /// deferred queue.
  static void _runWhenReady(void Function(JSObject oneSignal) callback) {
    final deferred = globalContext.getProperty('OneSignalDeferred'.toJS);
    if (deferred == null || deferred.isUndefinedOrNull) {
      // The loader script tag in index.html is missing or didn't run
      // (e.g. blocked by an ad/privacy blocker) — fail silently rather
      // than crash the app.
      return;
    }

    (deferred as JSObject).callMethod('push'.toJS, callback.toJS);
  }

  /// OneSignal.init() itself runs directly from web/index.html,
  /// immediately on page load — not delayed until Flutter boots and this
  /// Dart code runs. That matches OneSignal's own Custom Code integration
  /// snippet and avoids double-initializing the SDK. This just marks
  /// that init has happened; the permission prompt is a separate,
  /// explicit step (requestPermission below).
  static Future<void> init() async {
    _initStarted = true;
  }

  /// Explicitly asks for notification permission — fired later from a
  /// "soft ask" screen rather than automatically here, so the user sees
  /// why the app wants to notify them before the native browser prompt
  /// appears.
  static Future<void> requestPermission() async {
    _runWhenReady((oneSignal) {
      final notifications = oneSignal.getProperty('Notifications'.toJS);
      if (notifications != null && !notifications.isUndefinedOrNull) {
        (notifications as JSObject).callMethod('requestPermission'.toJS);
      }
    });
  }

  /// Whether the browser has actually granted notification permission
  /// right now, read straight from the standard `Notification.permission`
  /// API rather than anything OneSignal-specific. The "soft ask" primer
  /// checks this — not a one-time "have we shown it" flag — so declining
  /// once doesn't permanently block every future notification.
  static bool hasPermission() {
    final notificationCtor = globalContext.getProperty('Notification'.toJS);
    if (notificationCtor == null || notificationCtor.isUndefinedOrNull) {
      return false;
    }
    final permission =
        (notificationCtor as JSObject).getProperty('permission'.toJS) as JSString?;
    return permission?.toDart == 'granted';
  }

  static void loginAsCustomer(String supabaseUserId) {
    _login('customer_$supabaseUserId');
  }

  static void loginAsFleet(String fleetUserId) {
    _login('fleet_$fleetUserId');
  }

  static void loginAsAdmin() {
    _login('admin');
  }

  static void _login(String externalId) {
    _runWhenReady((oneSignal) {
      oneSignal.callMethod('login'.toJS, externalId.toJS);
    });
  }

  /// Call on logout for any of the three roles, so this device/browser
  /// stops being targeted as that identity once they've signed out.
  static void logout() {
    _runWhenReady((oneSignal) {
      oneSignal.callMethod('logout'.toJS);
    });
  }
}