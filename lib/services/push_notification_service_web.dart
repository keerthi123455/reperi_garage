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

  static Future<void> init() async {
    if (_initStarted) return;
    _initStarted = true;

    // OneSignal.init() itself now runs directly from web/index.html,
    // immediately on page load — not delayed until Flutter boots and
    // this Dart code runs. That matches OneSignal's own Custom Code
    // integration snippet and avoids double-initializing the SDK.
    //
    // This just handles the one remaining step: explicitly asking for
    // notification permission, which init() does not do by itself.
    _runWhenReady((oneSignal) {
      final notifications = oneSignal.getProperty('Notifications'.toJS);
      if (notifications != null && !notifications.isUndefinedOrNull) {
        (notifications as JSObject).callMethod('requestPermission'.toJS);
      }
    });
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