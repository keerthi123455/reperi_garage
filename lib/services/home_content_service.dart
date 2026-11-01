import 'package:supabase_flutter/supabase_flutter.dart';

/// One image on the home screen (coverflow slide, tile, standalone banner).
/// Mirrors the `home_content` row — see supabase/home_content.sql.
class HomeContentItem {
  const HomeContentItem({
    required this.key,
    required this.section,
    required this.position,
    required this.name,
    required this.width,
    required this.height,
    required this.isActive,
    this.imageUrl,
    this.legacyAsset,
    this.subtitle,
    this.serviceKey,
  });

  final String key;         // 'coverflow:service', 'tile:tyres', …
  final String section;     // 'coverflow' | 'tile' | 'banner' | 'twowheeler'
  final int position;
  final String name;
  final int width;
  final int height;
  final bool isActive;
  final String? imageUrl;   // live CMS image (public bucket)
  final String? legacyAsset; // fallback asset path (bundled with the app)
  final String? subtitle;
  final String? serviceKey;

  /// What the home screen should actually render — the uploaded image if
  /// one exists, otherwise the bundled asset path. Returns null if neither
  /// is set (very rare; the tile just doesn't show).
  String? get displaySrc => (imageUrl?.isNotEmpty ?? false) ? imageUrl : legacyAsset;

  /// True if the display source is a bundled asset (use AssetImage), false
  /// if it's a network URL (use CachedNetworkImage / Image.network).
  bool get isAsset => (imageUrl == null || imageUrl!.isEmpty) && legacyAsset != null;

  factory HomeContentItem.fromJson(Map<String, dynamic> j) => HomeContentItem(
        key: j['key'].toString(),
        section: j['section'].toString(),
        position: int.tryParse('${j['position']}') ?? 0,
        name: (j['name'] ?? '').toString(),
        width: int.tryParse('${j['width']}') ?? 1200,
        height: int.tryParse('${j['height']}') ?? 800,
        isActive: j['is_active'] == true,
        imageUrl: j['image_url']?.toString(),
        legacyAsset: j['legacy_asset']?.toString(),
        subtitle: j['subtitle']?.toString(),
        serviceKey: j['service_key']?.toString(),
      );
}

/// Fetches and caches the home-screen content. The home screen awaits this
/// before building, so tiles taken offline from the CRM never flash on
/// screen first. Cached in memory for the session; call [refresh] to pull
/// again (e.g. after the user comes back from the drawer).
class HomeContentService {
  HomeContentService._();

  static List<HomeContentItem> _items = [];
  static DateTime? _loadedAt;

  /// Everything we have, including hidden items. Rarely used directly —
  /// prefer [forSection] or [byKey].
  static List<HomeContentItem> get all => _items;

  /// Live items in the given section, sorted by position.
  static List<HomeContentItem> forSection(String section) =>
      _items.where((i) => i.section == section && i.isActive).toList()
        ..sort((a, b) => a.position.compareTo(b.position));

  /// Look up by stable key (e.g. 'banner:emergency') — null when hidden.
  static HomeContentItem? byKey(String key) {
    for (final i in _items) {
      if (i.key == key && i.isActive) return i;
    }
    return null;
  }

  /// Call once from the home screen's initState. Safe to call again later.
  static Future<void> ensureLoaded() async {
    if (_items.isNotEmpty && _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 10)) {
      return; // fresh enough
    }
    await refresh();
  }

  /// Force a reload. Swallows errors — the home screen falls back to the
  /// bundled defaults if the network is dead.
  static Future<void> refresh() async {
    try {
      final rows = await Supabase.instance.client
          .from('home_content')
          .select()
          .order('section', ascending: true)
          .order('position', ascending: true);
      final list = <HomeContentItem>[];
      for (final r in (rows as List)) {
        list.add(HomeContentItem.fromJson(Map<String, dynamic>.from(r as Map)));
      }
      _items = list;
      _loadedAt = DateTime.now();
    } catch (_) {
      // Keep whatever was there; home screen falls back to kCoverflowBanners
      // / kServiceBanners constants (the hardcoded asset paths).
    }
  }
}
