/// Website-only location permission prompts (a "soft ask" like the
/// notification primer, plus "how to unblock" help).
///
/// Picked AT COMPILE TIME, like geocoding_bridge.dart:
///   - Android / iOS builds get web_location_permission_stub.dart (does
///     nothing), so the apps keep their normal permission flow untouched.
///   - The website build gets web_location_permission_web.dart.
export 'web_location_permission_stub.dart'
    if (dart.library.js_interop) 'web_location_permission_web.dart';
