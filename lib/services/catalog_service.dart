import 'package:supabase_flutter/supabase_flutter.dart';

/// Fetches service package/pricing data from the `service_packages` table
/// instead of relying on hardcoded values in each screen.
class CatalogService {
  static final _client = Supabase.instance.client;

  /// Fetches all active packages for a given category (e.g. 'Maintenance',
  /// 'Car Spa', 'Tyre Care', 'Paint Care', 'Denting & Tinkering', 'Book Service'),
  /// ordered the same way they appear in the app today.
  static Future<List<Map<String, dynamic>>> fetchByCategory(
    String category,
  ) async {
    final response = await _client
        .from('service_packages')
        .select()
        .eq('category', category)
        .eq('active', true)
        .order('sort_order', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Fetches every active package across every category — used by the
  /// AI advisor to compute "cheapest tier" prices live instead of guessing.
  static Future<List<Map<String, dynamic>>> fetchAll() async {
    final response = await _client
        .from('service_packages')
        .select()
        .eq('active', true);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Fetches every active package across all categories, useful for
  /// home_screen.dart's slider which mixes packages from multiple categories.
  static Future<List<Map<String, dynamic>>> fetchByKeys(
    List<String> keys,
  ) async {
    final response = await _client
        .from('service_packages')
        .select()
        .inFilter('key', keys)
        .eq('active', true);

    final rows = List<Map<String, dynamic>>.from(response);
    // Preserve the exact order of `keys` since Supabase doesn't guarantee it.
    rows.sort((a, b) => keys.indexOf(a['key']).compareTo(keys.indexOf(b['key'])));
    return rows;
  }
}