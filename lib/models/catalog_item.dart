/// One row of the Supabase `services` table — every package the app sells.
///
/// Names, prices, features and badges all come from here, so they can be
/// changed in Supabase without shipping an app update. Who a booking is
/// assigned to, and what it costs, is decided on the server (booking-api
/// Edge Function) — the app only displays these values.
class CatalogItem {
  final String key;
  final String name;
  final String bookingName;
  final String? category;
  final List<String> screens;
  final String vehicleType; // 'car' | 'bike' | 'any'
  final String tagline;
  final String description;
  final int? price; // rupees; null = quote-based
  final String? priceLabel; // shown instead of price when set
  final String duration;
  final String? badge;
  final bool popular;
  final List<String> features;
  final Map<String, dynamic> details;
  final int sortOrder;
  final bool showInCatalog;
  final bool isAddon;
  final bool bookable;
  final bool vehicleRequired;
  final String pickupMode; // 'optional' | 'none' | 'included' | 'locked'
  final bool allowCod;

  const CatalogItem({
    required this.key,
    required this.name,
    required this.bookingName,
    required this.category,
    required this.screens,
    required this.vehicleType,
    required this.tagline,
    required this.description,
    required this.price,
    required this.priceLabel,
    required this.duration,
    required this.badge,
    required this.popular,
    required this.features,
    required this.details,
    required this.sortOrder,
    required this.showInCatalog,
    required this.isAddon,
    required this.bookable,
    required this.vehicleRequired,
    required this.pickupMode,
    required this.allowCod,
  });

  factory CatalogItem.fromJson(Map<String, dynamic> j) {
    final name = (j['name'] ?? '').toString();
    return CatalogItem(
      key: (j['key'] ?? '').toString(),
      name: name,
      bookingName: '${j['booking_name'] ?? ''}'.isEmpty ? name : '${j['booking_name']}',
      category: j['category']?.toString(),
      screens: _stringList(j['screens']),
      vehicleType: (j['vehicle_type'] ?? 'car').toString(),
      tagline: (j['tagline'] ?? '').toString(),
      description: (j['description'] ?? j['tagline'] ?? '').toString(),
      price: j['price'] is num ? (j['price'] as num).round() : int.tryParse('${j['price'] ?? ''}'),
      priceLabel: (j['price_label'] == null || '${j['price_label']}'.isEmpty) ? null : '${j['price_label']}',
      duration: (j['duration'] ?? '').toString(),
      badge: j['badge']?.toString(),
      popular: j['popular'] == true,
      features: _stringList(j['features']),
      details: j['details'] is Map ? Map<String, dynamic>.from(j['details'] as Map) : <String, dynamic>{},
      sortOrder: j['sort_order'] is num ? (j['sort_order'] as num).toInt() : 0,
      showInCatalog: j['show_in_catalog'] != false,
      isAddon: j['is_addon'] == true,
      bookable: j['bookable'] != false,
      vehicleRequired: j['vehicle_required'] != false,
      pickupMode: (j['pickup_mode'] ?? 'optional').toString(),
      allowCod: j['allow_cod'] != false,
    );
  }

  static List<String> _stringList(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const <String>[];

  /// "₹3,999", or the price label ("Custom Quote", "₹75,000 - ₹1,00,000").
  String get priceText {
    if (priceLabel != null) return priceLabel!;
    if (price == null) return '';
    final prefix = detail('price_prefix') == 'from' ? 'From ' : '';
    return '$prefix${formatRupees(price!)}';
  }

  /// Can be sent straight to checkout (fixed price, bookable).
  bool get isDirectlyPayable => bookable && price != null;

  /// A string from [details], or [fallback].
  String detail(String field, [String fallback = '']) {
    final v = details[field];
    return v == null ? fallback : v.toString();
  }

  bool detailBool(String field) => details[field] == true;

  List<Map<String, dynamic>> detailMaps(String field) {
    final v = details[field];
    if (v is! List) return const [];
    return v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  /// Per-screen wording overrides, e.g. details.display.tyre_care — lets one
  /// service (one price) be described differently on two screens.
  Map<String, dynamic> displayFor(String screen) {
    final display = details['display'];
    if (display is Map && display[screen] is Map) {
      return Map<String, dynamic>.from(display[screen] as Map);
    }
    return const {};
  }

  /// Text from [displayFor] [screen] if present, otherwise [fallback].
  String displayText(String screen, String field, String fallback) {
    final v = displayFor(screen)[field];
    return v == null ? fallback : v.toString();
  }

  List<String> displayFeatures(String screen) {
    final v = displayFor(screen)['features'];
    return v is List ? v.map((e) => e.toString()).toList() : features;
  }

  bool displayBool(String screen, String field, [bool fallback = false]) {
    final v = displayFor(screen)[field];
    return v is bool ? v : fallback;
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'booking_name': bookingName,
        'category': category,
        'screens': screens,
        'vehicle_type': vehicleType,
        'tagline': tagline,
        'description': description,
        'price': price,
        'price_label': priceLabel,
        'duration': duration,
        'badge': badge,
        'popular': popular,
        'features': features,
        'details': details,
        'sort_order': sortOrder,
        'show_in_catalog': showInCatalog,
        'is_addon': isAddon,
        'bookable': bookable,
        'vehicle_required': vehicleRequired,
        'pickup_mode': pickupMode,
        'allow_cod': allowCod,
      };
}

/// ₹1,23,456 — Indian digit grouping.
String formatRupees(int amount) {
  final negative = amount < 0;
  final digits = amount.abs().toString();
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  return '${negative ? '-' : ''}₹$grouped';
}
