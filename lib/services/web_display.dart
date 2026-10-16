/// Website-only display helpers, picked AT COMPILE TIME like
/// geocoding_bridge.dart:
///   - Android / iOS builds get web_display_stub.dart (always "no fix needed").
///   - The website build gets web_display_web.dart.
export 'web_display_stub.dart'
    if (dart.library.js_interop) 'web_display_web.dart';
