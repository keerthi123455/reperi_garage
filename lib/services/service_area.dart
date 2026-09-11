import 'dart:math';

/// Whether a coordinate falls inside the area this app currently serves.
///
/// Deliberately geographic (distance from a center point), not text-based —
/// reverse-geocoded addresses inconsistently say "Bangalore", "Bengaluru",
/// a sub-locality with no city name at all, or nothing usable, so matching
/// on the address string would wrongly reject real Bangalore addresses.
///
/// Uses a center point + radius rather than the city's actual (very
/// irregular) boundary polygon — simple to reason about and tune, and
/// close enough for a serviceability check. Adjust [_radiusKm] to expand
/// or shrink coverage; swap in a polygon/point-in-polygon check later if
/// the business needs the real BBMP boundary instead of a circle.
class ServiceArea {
  ServiceArea._();

  // Central Bangalore (near Majestic/Vidhana Soudha).
  static const double _centerLat = 12.9716;
  static const double _centerLng = 77.5946;

  static const double _radiusKm = 100;

  static const double _earthRadiusKm = 6371;

  static bool isWithinServiceArea(double latitude, double longitude) {
    return _distanceKm(_centerLat, _centerLng, latitude, longitude) <= _radiusKm;
  }

  /// Haversine great-circle distance between two lat/lng points, in km.
  static double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return _earthRadiusKm * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;
}
