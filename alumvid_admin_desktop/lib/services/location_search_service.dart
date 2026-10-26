import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlaceSearchResult {
  final String name;
  final String address;
  final LatLng location;
  final String source; // 'Google Places (New)' o 'Photon / OpenStreetMap'

  PlaceSearchResult({
    required this.name,
    required this.address,
    required this.location,
    required this.source,
  });
}

/// Servicio inteligente de búsqueda de lugares y geocodificación para AlumVid.
/// Implementa Google Places API (New) con polarización geográfica hacia Quito / Ecuador,
/// y un mecanismo de respaldo automático hacia Photon / OpenStreetMap para máxima resiliencia.
class LocationSearchService {
  static const String _prefGoogleKey = 'google_maps_api_key_custom';
  static const String defaultGoogleKey = 'AIzaSyDYqJ2TbM6UD5GIHt6wTDRrhpzdQx2QsmQ';

  static Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_prefGoogleKey);
    if (custom != null && custom.trim().isNotEmpty) {
      return custom.trim();
    }
    return defaultGoogleKey;
  }

  static Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefGoogleKey, key.trim());
  }

  /// Búsqueda inteligente de lugares, comercios (ej. "Listo"), ciudadelas y conjuntos residenciales
  static Future<List<PlaceSearchResult>> searchPlaces(
    String query, {
    LatLng center = const LatLng(-0.1807, -78.4678), // Quito centro por defecto
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final apiKey = await getApiKey();

    // 1. Intento con Google Places API (New)
    try {
      final googleResults = await _searchGooglePlacesNew(cleanQuery, apiKey, center);
      if (googleResults.isNotEmpty) {
        return googleResults;
      }
    } catch (e) {
      debugPrint('[LocationSearchService] Google Places API (New) no disponible o bloqueado: $e');
    }

    // 2. Respaldo inteligente con Photon (Elasticsearch sobre OSM enfocado en POIs)
    try {
      final photonResults = await _searchPhoton(cleanQuery, center);
      if (photonResults.isNotEmpty) {
        return photonResults;
      }
    } catch (e) {
      debugPrint('[LocationSearchService] Fallback Photon falló: $e');
    }

    // 3. Respaldo secundario con Nominatim (OSM estándar)
    try {
      return await _searchNominatim(cleanQuery, center);
    } catch (e) {
      debugPrint('[LocationSearchService] Fallback Nominatim falló: $e');
      return [];
    }
  }

  /// Google Places API (New) - Text Search
  static Future<List<PlaceSearchResult>> _searchGooglePlacesNew(
    String query,
    String apiKey,
    LatLng center,
  ) async {
    final url = Uri.parse('https://places.googleapis.com/v1/places:searchText');
    final body = jsonEncode({
      'textQuery': query,
      'locationBias': {
        'circle': {
          'center': {
            'latitude': center.latitude,
            'longitude': center.longitude,
          },
          'radius': 45000.0, // 45km alrededor de Quito / Valle
        }
      },
    });

    final response = await http
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': apiKey,
            'X-Goog-FieldMask': 'places.displayName,places.formattedAddress,places.location',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 4));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final places = data['places'] as List<dynamic>?;
      if (places != null && places.isNotEmpty) {
        return places.map((p) {
          final name = p['displayName'] != null ? p['displayName']['text']?.toString() ?? '' : '';
          final address = p['formattedAddress']?.toString() ?? name;
          final loc = p['location'] as Map<String, dynamic>?;
          final lat = loc != null ? (loc['latitude'] as num).toDouble() : 0.0;
          final lon = loc != null ? (loc['longitude'] as num).toDouble() : 0.0;

          return PlaceSearchResult(
            name: name.isNotEmpty ? name : address,
            address: address,
            location: LatLng(lat, lon),
            source: 'Google Places (New)',
          );
        }).where((r) => r.location.latitude != 0.0).toList();
      }
    } else {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    return [];
  }

  /// Motor Photon (Komoot) enfocado en POIs locales (tiendas de conveniencia Listo, conjuntos, etc.)
  static Future<List<PlaceSearchResult>> _searchPhoton(String query, LatLng center) async {
    final encoded = Uri.encodeComponent(query);
    final url = Uri.parse(
      'https://photon.komoot.io/api/?q=$encoded&lat=${center.latitude}&lon=${center.longitude}&limit=12',
    );

    final response = await http
        .get(url, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 4));

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final features = data['features'] as List<dynamic>?;
      if (features != null && features.isNotEmpty) {
        final List<PlaceSearchResult> list = [];
        for (final f in features) {
          final props = f['properties'] as Map<String, dynamic>?;
          final geom = f['geometry'] as Map<String, dynamic>?;
          if (props == null || geom == null) continue;

          final coords = geom['coordinates'] as List<dynamic>?;
          if (coords == null || coords.length < 2) continue;
          final lon = (coords[0] as num).toDouble();
          final lat = (coords[1] as num).toDouble();

          final name = props['name']?.toString() ?? '';
          final street = props['street']?.toString() ?? '';
          final housenumber = props['housenumber']?.toString() ?? '';
          final district = props['district']?.toString() ?? props['suburb']?.toString() ?? '';
          final city = props['city']?.toString() ?? 'Quito';
          final country = props['country']?.toString() ?? 'Ecuador';

          // Filtrar resultados fuera de Ecuador si el usuario busca localmente
          if (country.toLowerCase() != 'ecuador' && !country.toLowerCase().contains('ec')) {
            continue;
          }

          final addressParts = [
            if (street.isNotEmpty) ...[street, if (housenumber.isNotEmpty) housenumber],
            if (district.isNotEmpty) district,
            city,
            country
          ];

          final formattedAddress = addressParts.join(', ');
          list.add(PlaceSearchResult(
            name: name.isNotEmpty ? name : formattedAddress,
            address: formattedAddress.isNotEmpty ? formattedAddress : name,
            location: LatLng(lat, lon),
            source: 'Photon POI',
          ));
        }
        if (list.isNotEmpty) return list;
      }
    }
    return [];
  }

  /// Respaldo Nominatim (OpenStreetMap)
  static Future<List<PlaceSearchResult>> _searchNominatim(String query, LatLng center) async {
    final encoded = Uri.encodeComponent(query);
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=$encoded&format=json&addressdetails=1&countrycodes=ec&viewbox=-78.65,-0.40,-78.35,-0.05&bounded=0&limit=8',
    );

    final response = await http.get(url, headers: {
      'User-Agent': 'AlumVidLogistics/1.0 (soporte@alumvid.com)',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 4));

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((item) {
        final lat = double.tryParse(item['lat']?.toString() ?? '') ?? 0.0;
        final lon = double.tryParse(item['lon']?.toString() ?? '') ?? 0.0;
        final displayName = item['display_name']?.toString() ?? query;
        final name = item['name']?.toString() ?? displayName.split(',').first.trim();

        return PlaceSearchResult(
          name: name.isNotEmpty ? name : displayName,
          address: displayName,
          location: LatLng(lat, lon),
          source: 'Nominatim OSM',
        );
      }).where((m) => m.location.latitude != 0.0).toList();
    }
    return [];
  }

  /// Geocodificación inversa: Coordenada -> Dirección entendible
  static Future<String> reverseGeocode(LatLng point) async {
    final apiKey = await getApiKey();

    // 1. Intentar con Google Geocoding API
    try {
      final gUrl = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=${point.latitude},${point.longitude}&key=$apiKey&language=es',
      );
      final gRes = await http.get(gUrl).timeout(const Duration(seconds: 3));
      if (gRes.statusCode == 200) {
        final gData = jsonDecode(gRes.body);
        if (gData['status'] == 'OK' && gData['results'] != null && (gData['results'] as List).isNotEmpty) {
          final formatted = gData['results'][0]['formatted_address']?.toString();
          if (formatted != null && formatted.isNotEmpty) {
            return formatted;
          }
        }
      }
    } catch (_) {}

    // 2. Respaldo con Nominatim
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=${point.latitude}&lon=${point.longitude}&format=json&addressdetails=1',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'AlumVidLogistics/1.0 (soporte@alumvid.com)',
      }).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['display_name']?.toString();
        if (address != null && address.isNotEmpty) {
          return address;
        }
      }
    } catch (_) {}

    return 'Lat: ${point.latitude.toStringAsFixed(5)}, Lon: ${point.longitude.toStringAsFixed(5)}';
  }
}
