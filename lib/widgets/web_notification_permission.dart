/// Website-only notification prompt.
///
/// Picked AT COMPILE TIME, like geocoding_bridge.dart:
///   - Android / iOS builds get web_notification_permission_stub.dart (does
///     nothing), so the apps keep notification_permission_dialog.dart and
///     their normal OneSignal flow untouched.
///   - The website build gets web_notification_permission_web.dart.
export 'web_notification_permission_stub.dart'
    if (dart.library.js_interop) 'web_notification_permission_web.dart';
