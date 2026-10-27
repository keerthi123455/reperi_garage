import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import '../screens/community_screen.dart';
import 'community_service.dart';

/// Opens shared Community links — https://reperi.in/community/reel/<id> and
/// /community/post/<id> — on the right reel or post.
///
///  • App installed: Android App Links / iOS Universal Links hand the link to
///    the app (verified by web/.well-known/assetlinks.json and
///    apple-app-site-association). Caught here with app_links, on a cold
///    start and while the app is already open.
///  • No app: the link opens reperi.in (this same app, as the website), which
///    reads the address on start-up.
///
/// A link that arrives during the splash screen waits until the splash has
/// moved on (SplashScreen.dispose calls [markReady]), so it opens on top of
/// whichever screen the user lands on.
class CommunityLinks {
  CommunityLinks._();

  static GlobalKey<NavigatorState>? _navigator;
  static CommunityLink? _pending;
  static bool _ready = false;
  // ignore: unused_field
  static StreamSubscription<Uri>? _sub;
  static String? _lastKey;
  static DateTime? _lastAt;

  static final RegExp _uuid = RegExp(r'^[0-9a-fA-F-]{36}$');

  /// The Community link inside [uri], or null when it isn't one.
  static CommunityLink? parse(Uri uri) {
    if (!kIsWeb) {
      final host = uri.host.toLowerCase();
      if (host != 'reperi.in' && host != 'www.reperi.in') return null;
    }
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (seg.isEmpty || seg.first.toLowerCase() != 'community') return null;
    if (seg.length >= 3 && _uuid.hasMatch(seg[2])) {
      switch (seg[1].toLowerCase()) {
        case 'reel':
          return CommunityLink(reelId: seg[2].toLowerCase());
        case 'post':
          return CommunityLink(postId: seg[2].toLowerCase());
      }
    }
    // reperi.in/community — just the page.
    return const CommunityLink();
  }

  /// Called once from main(), before runApp.
  static Future<void> init(GlobalKey<NavigatorState> navigator) async {
    _navigator = navigator;
    if (kIsWeb) {
      final link = parse(Uri.base);
      if (link != null) _pending = link;
      return;
    }
    try {
      final links = AppLinks();
      _sub = links.uriLinkStream.listen(_handle, onError: (_) {});
      final initial = await links.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (_) {
      // No link support on this platform — nothing to open.
    }
  }

  static void _handle(Uri uri) {
    final link = parse(uri);
    if (link == null) return;
    // The link that started the app can arrive twice (initial link + stream).
    final now = DateTime.now();
    final last = _lastAt;
    if (_lastKey == link.key && last != null && now.difference(last) < const Duration(seconds: 3)) return;
    _lastKey = link.key;
    _lastAt = now;
    if (_ready) {
      _open(link);
    } else {
      _pending = link;
    }
  }

  /// The splash screen is gone — open a link that came in during it.
  static void markReady() {
    if (_ready) return;
    _ready = true;
    final link = _pending;
    _pending = null;
    if (link != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(link));
    }
  }

  static void _open(CommunityLink link) {
    final nav = _navigator?.currentState;
    if (nav == null) {
      _pending = link;
      _ready = false;
      return;
    }
    nav.push(CommunityScreen.route(link: link));
  }
}
