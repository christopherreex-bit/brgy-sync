import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/address_location.dart';

class LocationService {
  static const proxyUrl = String.fromEnvironment(
    'MAPS_PROXY_URL',
    defaultValue: 'https://brgy-sync-maps-proxy.jasonleyva723.workers.dev',
  );
  static const barangayLatitude = 14.533611;
  static const barangayLongitude = 121.079722;
  static const serviceRadiusMeters = 2200.0;

  Future<List<AddressSuggestion>> autocomplete(String text) async {
    if (text.trim().length < 3 || proxyUrl.isEmpty) return const [];
    final response = await http
        .get(
          Uri.parse(proxyUrl).replace(
            path: '/autocomplete',
            queryParameters: {'text': text.trim()},
          ),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == 503) return const [];
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Address lookup is temporarily unavailable.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return ((body['results'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) {
          final data = Map<String, dynamic>.from(item);
          return AddressSuggestion(
            formattedAddress: (data['formatted'] ?? '').toString(),
            latitude: (data['lat'] as num).toDouble(),
            longitude: (data['lon'] as num).toDouble(),
            placeId: data['placeId']?.toString(),
            components: data['components'] is Map
                ? Map<String, dynamic>.from(data['components'] as Map)
                : const {},
          );
        })
        .where((item) => item.formattedAddress.isNotEmpty)
        .toList();
  }

  Future<AddressSuggestion?> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    if (proxyUrl.isEmpty) return null;
    final response = await http
        .get(
          Uri.parse(proxyUrl).replace(
            path: '/reverse',
            queryParameters: {
              'lat': latitude.toString(),
              'lon': longitude.toString(),
            },
          ),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final formatted = body['formatted']?.toString() ?? '';
    if (formatted.isEmpty) return null;
    return AddressSuggestion(
      formattedAddress: formatted,
      latitude: latitude,
      longitude: longitude,
      placeId: body['placeId']?.toString(),
      components: body['components'] is Map
          ? Map<String, dynamic>.from(body['components'] as Map)
          : const {},
    );
  }

  bool isInsideServiceArea(double latitude, double longitude) =>
      distanceMeters(
        latitude,
        longitude,
        barangayLatitude,
        barangayLongitude,
      ) <=
      serviceRadiusMeters;

  double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _radians(lat2 - lat1);
    final dLon = _radians(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _radians(double degrees) => degrees * math.pi / 180;
}
