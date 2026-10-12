/// Address <-> coordinates lookups, picked per platform AT COMPILE TIME.
///
/// Android / iOS builds: this is literally the `geocoding` package, the same
/// one the screens imported before. The web file below is NOT compiled into
/// the apps at all, so the app binaries contain no new code.
///
/// Website build: `geocoding` has no web implementation (every call throws),
/// so the website uses geocoding_web.dart instead, which offers the same
/// functions (`placemarkFromCoordinates`, `locationFromAddress`) backed by
/// OpenStreetMap.
///
/// Same conditional-import pattern as push_notification_service.dart.
export 'package:geocoding/geocoding.dart'
    if (dart.library.js_interop) 'geocoding_web.dart';
