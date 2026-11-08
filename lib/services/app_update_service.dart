import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import 'app_update_play_stub.dart' if (dart.library.io) 'app_update_play.dart';

/// "A new version of Reperi is ready" — shown when the app opens.
///
/// How it decides:
///  * **Newer version in the store** (found automatically):
///      Android — Google Play's in-app update check (only for installs
///                from the Play Store).
///      iOS     — the App Store lookup for com.reperi.autocare.app.
///    → popup with **Later**. Later hides it until the next app open.
///  * **Below the minimum version** set in the CRM ("App update" tab →
///    app_settings.app_min_version, e.g. "2.2.0")
///    → popup with **no Later** — the app can't be used until updated.
///  * The "What's new" lines come from the CRM (app_settings.app_update_notes,
///    one per line). Empty → a short generic line.
///
/// "Update" opens the Play Store / App Store page. Nothing runs on the web.
class AppUpdateService {
  AppUpdateService._();

  static const _androidPackage = 'com.reperi.autocare.app';
  static const _iosBundleId = 'com.reperi.autocare.app';

  /// Starts the first check once the splash screen has handed over to the
  /// next screen (so the popup never sits under a splash redirect).
  static final NavigatorObserver observer = _FirstScreenObserver();

  static GlobalKey<NavigatorState>? _navigatorKey;
  static bool _sheetOpen = false;
  static bool _snoozedThisSession = false;
  static DateTime? _lastCheck;
  static _Lifecycle? _lifecycle;

  /// Call once from main() with the app's navigator key.
  static void init(GlobalKey<NavigatorState> navigatorKey) {
    if (kIsWeb) return;
    _navigatorKey = navigatorKey;
    _lifecycle ??= _Lifecycle()..attach();
  }

  static void _onFirstScreen() {
    Future.delayed(const Duration(milliseconds: 700), check);
  }

  /// Runs the check (at most once every 30 minutes).
  static Future<void> check({bool force = false}) async {
    if (kIsWeb || _navigatorKey == null || _sheetOpen) return;
    final now = DateTime.now();
    if (!force && _lastCheck != null && now.difference(_lastCheck!) < const Duration(minutes: 30)) return;
    _lastCheck = now;

    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version; // e.g. "2.1.0"
      final settings = await _loadSettings();
      final minVersion = settings.minVersion;
      final mustUpdate = minVersion != null && _compare(current, minVersion) < 0;

      _StoreUpdate? store;
      if (!mustUpdate && _snoozedThisSession) return;
      store = await _storeUpdate(info);

      if (!mustUpdate && store == null) return;

      final ctx = _navigatorKey!.currentState?.overlay?.context;
      if (ctx == null || !ctx.mounted) return;

      _sheetOpen = true;
      await showModalBottomSheet<void>(
        context: ctx,
        isDismissible: !mustUpdate,
        enableDrag: !mustUpdate,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _UpdateSheet(
          currentVersion: current,
          newVersion: store?.version ?? (mustUpdate ? minVersion : null),
          notes: settings.notes,
          mustUpdate: mustUpdate,
          storeName: defaultTargetPlatform == TargetPlatform.iOS ? 'App Store' : 'Play Store',
          onUpdate: () => _openStore(store?.storeUrl),
          onLater: () => _snoozedThisSession = true,
        ),
      );
      _sheetOpen = false;
      if (!mustUpdate) _snoozedThisSession = true;
    } catch (e) {
      _sheetOpen = false;
      debugPrint('AppUpdateService: $e');
    }
  }

  // ── CRM settings ───────────────────────────────────────────────────
  static Future<_Settings> _loadSettings() async {
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('app_settings')
          .select('key, value')
          .inFilter('key', ['app_min_version', 'app_update_notes'])
          .timeout(const Duration(seconds: 8));
      String? minVersion;
      var notes = <String>[];
      for (final r in rows) {
        final key = r['key'];
        final v = r['value'];
        final text = v == null ? '' : (v is String ? v : v.toString());
        if (key == 'app_min_version') {
          final t = text.trim();
          if (RegExp(r'^\d+(\.\d+){0,3}$').hasMatch(t) && t != '0.0.0') minVersion = t;
        } else if (key == 'app_update_notes') {
          notes = text
              .split('\n')
              .map((l) => l.trim().replaceFirst(RegExp(r'^[-•*]\s*'), ''))
              .where((l) => l.isNotEmpty)
              .take(5)
              .toList();
        }
      }
      return _Settings(minVersion, notes);
    } catch (_) {
      return const _Settings(null, []);
    }
  }

  // ── Store checks ───────────────────────────────────────────────────
  static Future<_StoreUpdate?> _storeUpdate(PackageInfo info) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final storeBuild = await playStoreUpdateVersionCode();
        if (storeBuild == null) return null;
        final installedBuild = int.tryParse(info.buildNumber) ?? 0;
        if (storeBuild == 0 || storeBuild > installedBuild) return const _StoreUpdate(null, null);
        return null;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final uri = Uri.parse(
            'https://itunes.apple.com/lookup?bundleId=$_iosBundleId&country=in&t=${DateTime.now().millisecondsSinceEpoch}');
        final res = await http.get(uri).timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) return null;
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final results = body['results'];
        if (results is! List || results.isEmpty) return null;
        final r = results.first as Map<String, dynamic>;
        final storeVersion = r['version']?.toString();
        if (storeVersion == null || _compare(info.version, storeVersion) >= 0) return null;
        return _StoreUpdate(storeVersion, r['trackViewUrl']?.toString());
      }
    } catch (_) {
      // Not installed from the store, offline, etc. — no popup.
    }
    return null;
  }

  static Future<void> _openStore(String? storeUrl) async {
    final candidates = <Uri>[
      if (defaultTargetPlatform == TargetPlatform.android) ...[
        Uri.parse('market://details?id=$_androidPackage'),
        Uri.parse('https://play.google.com/store/apps/details?id=$_androidPackage'),
      ] else ...[
        if (storeUrl != null && storeUrl.isNotEmpty) Uri.parse(storeUrl),
        Uri.parse('https://apps.apple.com/in/search?term=Reperi'),
      ],
    ];
    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {}
    }
  }

  /// "2.10.0" vs "2.9.1" → 1. Missing parts count as 0.
  static int _compare(String a, String b) {
    List<int> parts(String v) =>
        v.split('+').first.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 4; i++) {
      final p = i < x.length ? x[i] : 0;
      final q = i < y.length ? y[i] : 0;
      if (p != q) return p < q ? -1 : 1;
    }
    return 0;
  }
}

class _Settings {
  const _Settings(this.minVersion, this.notes);
  final String? minVersion;
  final List<String> notes;
}

class _StoreUpdate {
  const _StoreUpdate(this.version, this.storeUrl);
  final String? version;
  final String? storeUrl;
}

/// Fires the first check when the splash screen is replaced.
class _FirstScreenObserver extends NavigatorObserver {
  bool _fired = false;

  void _maybeFire(Route<dynamic>? route) {
    if (_fired || route is PopupRoute) return;
    _fired = true;
    AppUpdateService._onFirstScreen();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _maybeFire(newRoute);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // The very first push is the splash screen itself — skip it.
    if (previousRoute == null) return;
    _maybeFire(route);
  }
}

/// Re-checks when the app comes back to the foreground (e.g. after the
/// customer returns from the store without updating).
class _Lifecycle with WidgetsBindingObserver {
  void attach() => WidgetsBinding.instance.addObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && AppUpdateService.observer is _FirstScreenObserver &&
        (AppUpdateService.observer as _FirstScreenObserver)._fired) {
      AppUpdateService.check();
    }
  }
}

// ── The popup ────────────────────────────────────────────────────────
class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet({
    required this.currentVersion,
    required this.newVersion,
    required this.notes,
    required this.mustUpdate,
    required this.storeName,
    required this.onUpdate,
    required this.onLater,
  });

  final String currentVersion;
  final String? newVersion;
  final List<String> notes;
  final bool mustUpdate;
  final String storeName;
  final VoidCallback onUpdate;
  final VoidCallback onLater;

  static const _brandYellow = Color(0xFFE3B23C);
  static const _brandBlue = Color(0xFF1E3A8A);

  @override
  Widget build(BuildContext context) {
    final txt = AppColors.txt;
    final mut = AppColors.mut;
    final dark = AppColors.isDark;
    final buttonBg = dark ? _brandYellow : const Color(0xFF12100B);
    final buttonFg = dark ? const Color(0xFF12100B) : Colors.white;

    return PopScope(
      canPop: !mustUpdate,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: _brandYellow, borderRadius: BorderRadius.circular(15)),
                      child: const Icon(Icons.build_rounded, color: _brandBlue, size: 26),
                    ),
                    const Spacer(),
                    if (newVersion != null)
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: Text(
                            'v$currentVersion → v$newVersion',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: mut, fontSize: 11.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'A new version of Reperi is ready',
                  style: TextStyle(color: txt, fontSize: 21, fontWeight: FontWeight.w800, height: 1.2),
                ),
                const SizedBox(height: 6),
                Text(
                  mustUpdate
                      ? 'Please update to keep using Reperi. It takes less than a minute.'
                      : 'Update now to keep booking smoothly. It takes less than a minute.',
                  style: TextStyle(color: mut, fontSize: 13.5, height: 1.5),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final n in notes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            margin: const EdgeInsets.only(top: 1),
                            decoration: BoxDecoration(
                              color: _brandYellow.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check_rounded, size: 12, color: Color(0xFFA9842C)),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(n, style: TextStyle(color: txt, fontSize: 13.5, height: 1.35)),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                Material(
                  color: buttonBg,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: onUpdate,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 52),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                'Update on $storeName',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: buttonFg, fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, color: buttonFg, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (mustUpdate)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'This update is required to continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: mut, fontSize: 12),
                    ),
                  )
                else
                  TextButton(
                    onPressed: () {
                      onLater();
                      Navigator.of(context).pop();
                    },
                    style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    child: Text('Later', style: TextStyle(color: mut, fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
