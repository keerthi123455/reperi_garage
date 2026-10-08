import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/catalog_item.dart';

/// The app's single source of package names, prices and features — the
/// Supabase `services` table, plus the public `app_settings` (pickup fee).
///
/// * Loaded once at startup and kept in memory, so screens read it
///   synchronously ([forScreen], [byKey], [catalog]).
/// * The last good copy is cached on the device, so the app opens with
///   prices even before the network answers (and offline).
/// * Refreshed in the background whenever it's older than [_maxAge], so a
///   price edited in Supabase reaches open apps within minutes.
/// * Screens rebuild through [revision] (see CatalogGate).
///
/// What a booking actually costs is always re-checked by the server
/// (booking-api), so a stale cache can never under-charge.
class CatalogService {
  CatalogService._();

  static const _cacheKey = 'catalog_cache_v1';
  static const _maxAge = Duration(minutes: 5);

  /// Bumps every time new catalog data arrives.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<CatalogItem> _items = const [];
  static Map<String, CatalogItem> _byKey = const {};
  static int _pickupDropFee = 100;
  static bool _loaded = false;
  static DateTime? _fetchedAt;
  static Future<void>? _inflight;
  static Object? _lastError;

  static bool get isLoaded => _loaded;
  static Object? get lastError => _lastError;
  static int get pickupDropFee => _pickupDropFee;

  /// Every active service on [screen] (e.g. 'servicing'), in display order.
  static List<CatalogItem> forScreen(String screen) =>
      _items.where((i) => i.screens.contains(screen)).toList();

  static CatalogItem? byKey(String key) => _byKey[key];

  /// Everything listed on the Services screen.
  static List<CatalogItem> catalog() => _items.where((i) => i.showInCatalog).toList();

  /// Makes sure the catalog is available. Returns quickly when it's
  /// already loaded (refreshing in the background if it's getting old).
  static Future<void> ensureLoaded() {
    if (_loaded) {
      final age = _fetchedAt == null ? _maxAge : DateTime.now().difference(_fetchedAt!);
      if (age >= _maxAge) unawaited(refresh().catchError((_) {}));
      return Future.value();
    }
    return _inflight ??= _initialLoad().whenComplete(() => _inflight = null);
  }

  static Future<void> _initialLoad() async {
    // Cached copy first — instant, and works offline.
    await _loadFromCache();
    if (_loaded) {
      unawaited(refresh().catchError((_) {}));
      return;
    }
    await refresh();
  }

  /// Fetches the latest catalog from Supabase. Throws if that fails and
  /// nothing is loaded yet.
  static Future<void> refresh() async {
    try {
      final client = Supabase.instance.client;
      final fetched = await Future<List<List<dynamic>>>(() async {
        final List<dynamic> serviceRows =
            await client.from('services').select().order('sort_order', ascending: true);
        final List<dynamic> settingRows = await client.from('app_settings').select('key, value');
        return [serviceRows, settingRows];
      }).timeout(const Duration(seconds: 15));

      final rows = fetched[0].map((r) => Map<String, dynamic>.from(r as Map)).toList();
      final settings = fetched[1].map((r) => Map<String, dynamic>.from(r as Map)).toList();
      _apply(rows, settings);
      _fetchedAt = DateTime.now();
      _lastError = null;
      unawaited(_saveToCache(rows, settings));
    } catch (e) {
      _lastError = e;
      if (!_loaded) rethrow;
    }
  }

  static void _apply(List<Map<String, dynamic>> rows, List<Map<String, dynamic>> settings) {
    final items = rows.map(CatalogItem.fromJson).where((i) => i.key.isNotEmpty).toList()
      ..sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    _items = List.unmodifiable(items);
    _byKey = {for (final i in items) i.key: i};

    for (final s in settings) {
      if (s['key'] == 'pickup_drop_fee') {
        final v = s['value'];
        final fee = v is num ? v.round() : int.tryParse('$v');
        if (fee != null && fee >= 0) _pickupDropFee = fee;
      }
    }
    _loaded = true;
    revision.value++;
  }

  static Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _apply(
        List<Map<String, dynamic>>.from(decoded['services'] as List),
        List<Map<String, dynamic>>.from(decoded['settings'] as List),
      );
    } catch (_) {
      // A corrupt cache just means we wait for the network.
    }
  }

  static Future<void> _saveToCache(
    List<Map<String, dynamic>> rows,
    List<Map<String, dynamic>> settings,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode({'services': rows, 'settings': settings}));
    } catch (_) {}
  }
}
