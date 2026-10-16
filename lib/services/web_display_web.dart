import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// WEBSITE ONLY (never compiled into the apps — see web_display.dart).
///
/// Some phones show reperi.in as a DESKTOP page: Chrome's "Desktop site"
/// setting (also used by links opened from WhatsApp and other apps), some
/// in-app browsers, etc. The page is then laid out ~980px wide and shrunk to
/// fit the phone, so the app looks tiny (and the laptop frame kicks in).
///
/// Returns how much bigger the page is than the phone's real width (e.g.
/// 2.4 = laid out 2.4x too wide), or null on a normal phone, tablet or
/// computer. main.dart uses it to scale the app back up to normal phone size.
double? phoneZoomFactor() {
  try {
    final innerWidth =
        globalContext.getProperty<JSNumber>('innerWidth'.toJS).toDartDouble;
    final key = innerWidth.round();
    if (_cachedFor == key) return _cachedFactor;

    // Phones and tablets only (laptop mice/trackpads report 0 touch points).
    final navigator = globalContext.getProperty<JSObject>('navigator'.toJS);
    final touchPoints =
        navigator.getProperty<JSNumber?>('maxTouchPoints'.toJS)?.toDartInt ?? 0;
    if (touchPoints <= 0) return null;

    double? phoneWidth;

    // 1) The phone's real screen width vs the width the page was laid out at.
    final screen = globalContext.getProperty<JSObject>('screen'.toJS);
    final screenWidth =
        screen.getProperty<JSNumber>('width'.toJS).toDartDouble;
    if (screenWidth > 0 && screenWidth <= 700 && innerWidth > screenWidth * 1.3) {
      phoneWidth = screenWidth;
    } else {
      // 2) Fallback: the browser zoomed the page out to fit the screen.
      final visualViewport =
          globalContext.getProperty<JSObject?>('visualViewport'.toJS);
      final scale =
          visualViewport?.getProperty<JSNumber>('scale'.toJS).toDartDouble;
      if (scale != null && scale > 0 && scale < 0.85 &&
          innerWidth * scale <= 700) {
        phoneWidth = innerWidth * scale;
      }
    }

    if (phoneWidth == null) return null;
    final factor = innerWidth / phoneWidth;
    if (factor < 1.3) return null;

    // Remember it for this page width, so pinch-zooming doesn't make the
    // layout jump around. Recalculated when the width changes (rotation).
    _cachedFor = key;
    _cachedFactor = factor;
    return factor;
  } catch (_) {
    return null;
  }
}

int? _cachedFor;
double? _cachedFactor;
