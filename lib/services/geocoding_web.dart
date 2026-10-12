import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:geocoding/geocoding.dart' show Location, Placemark;

export 'package:geocoding/geocoding.dart' show Location, Placemark;

/// WEBSITE-ONLY replacement for the `geocoding` package's two lookups.
/// Only ever compiled into the web build (see geocoding_bridge.dart); the
/// Android / iOS apps never contain this file.
///
/// Backed by OpenStreetMap's free Nominatim service: no API key, works from
/// the browser. Its fair-use limit is ~1 request per second per user, which
/// normal address entry stays well within. If web traffic grows a lot, swap
/// the URLs below for a paid geocoder (Google / Ola Maps) without touching
/// any screen.
///
/// Uses the browser's built-in fetch() via dart:js_interop, like
/// push_notification_service_web.dart does, so no extra packages are needed.

const _host = 'nominatim.openstreetmap.org';
const _timeout = Duration(seconds: 10);

/// Coordinates -> address (used by "Detect my current location").
Future<List<Placemark>> placemarkFromCoordinates(
  double latitude,
  double longitude,
) async {
  final data = await _getJson(Uri.https(_host, '/reverse', {
    'format': 'jsonv2',
    'lat': '$latitude',
    'lon': '$longitude',
    'addressdetails': '1',
    'zoom': '18',
    'accept-language': 'en',
  }));
  if (data is! Map || data['address'] is! Map) return const [];

  final a = data['address'] as Map;
  String? pick(List<String> keys) {
    for (final k in keys) {
      final v = a[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  final road = pick(['road', 'pedestrian', 'footway', 'street']);
  final houseNo = pick(['house_number']);
  final street = road != null
      ? [if (houseNo != null) houseNo, road].join(' ')
      : pick(['neighbourhood', 'suburb', 'quarter', 'residential',
          'city_district']);

  return [
    Placemark(
      name: pick(['amenity', 'building', 'shop', 'office']) ?? street,
      street: street,
      thoroughfare: road,
      subThoroughfare: houseNo,
      subLocality: pick(['suburb', 'neighbourhood', 'city_district']),
      locality: pick(['city', 'town', 'village', 'municipality', 'county',
          'state_district']),
      subAdministrativeArea: pick(['state_district', 'county']),
      administrativeArea: pick(['state']),
      postalCode: pick(['postcode']),
      country: pick(['country']),
      isoCountryCode: pick(['country_code'])?.toUpperCase(),
    ),
  ];
}

/// Address text -> coordinates (used by "Type address").
///
/// OpenStreetMap often doesn't know office/building names, so if the full
/// address isn't found this falls back to the city + PIN code, then the PIN
/// code alone (both read from the "street, city, 560067, India" text the
/// address screen sends). A valid PIN code therefore always lands the pin in
/// the right area; the address text the customer typed is saved unchanged.
Future<List<Location>> locationFromAddress(String address) async {
  final queries = <String>[address, ..._pinCodeFallbacks(address)];
  for (var i = 0; i < queries.length; i++) {
    // Stay inside Nominatim's 1-request-per-second fair-use limit.
    if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 1100));
    final results = await _search(queries[i]);
    if (results.isNotEmpty) return results;
  }
  return const [];
}

List<String> _pinCodeFallbacks(String address) {
  final parts = address
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  final pinIndex = parts.lastIndexWhere((p) => RegExp(r'^\d{6}$').hasMatch(p));
  if (pinIndex < 0) return const [];
  final pin = parts[pinIndex];
  final city = pinIndex > 0 ? parts[pinIndex - 1] : null;
  return [
    if (city != null) '$city $pin, India',
    '$pin, India',
  ];
}

Future<List<Location>> _search(String query) async {
  final data = await _getJson(Uri.https(_host, '/search', {
    'format': 'jsonv2',
    'q': query,
    'countrycodes': 'in',
    'limit': '1',
    'accept-language': 'en',
  }));
  if (data is! List) return const [];

  final now = DateTime.now();
  final out = <Location>[];
  for (final item in data) {
    if (item is! Map) continue;
    final lat = double.tryParse('${item['lat']}');
    final lng = double.tryParse('${item['lon']}');
    if (lat != null && lng != null) {
      out.add(Location(latitude: lat, longitude: lng, timestamp: now));
    }
  }
  return out;
}

/// GET a URL with the browser's fetch() and return the parsed JSON
/// (Dart Lists / Maps). Throws on network errors, timeouts or non-200s,
/// which the screens already catch and show as their usual error messages.
Future<Object?> _getJson(Uri uri) async {
  Future<Object?> run() async {
    final response = await globalContext
        .callMethod<JSPromise<JSObject>>('fetch'.toJS, uri.toString().toJS)
        .toDart;
    final ok = response.getProperty<JSBoolean>('ok'.toJS).toDart;
    if (!ok) {
      final status = response.getProperty<JSNumber>('status'.toJS).toDartInt;
      throw Exception('Address lookup failed (HTTP $status)');
    }
    final json =
        await response.callMethod<JSPromise<JSAny?>>('json'.toJS).toDart;
    return json.dartify();
  }

  return run().timeout(_timeout);
}
