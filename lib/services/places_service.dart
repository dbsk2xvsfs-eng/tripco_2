import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

import 'location_service.dart';

class PlacesService {
  final String apiKey;
  PlacesService({required this.apiKey});

  /// PŮVODNÍ METODA – voláš ji když už máš lat/lng.
  /// Přidán parametr rankPreference (DISTANCE/POPULARITY), default DISTANCE.
  Future<List<Map<String, dynamic>>> nearby({
    required double lat,
    required double lng,
    int radiusMeters = 6000,
    int maxResults = 12,
    String rankPreference = "DISTANCE", // ✅ "DISTANCE" | "POPULARITY"
    List<String> includedTypes = const [
      "tourist_attraction",
      "museum",
      "park",
      "art_gallery",
      "hiking_area",
      "zoo",
      "aquarium",
      "amusement_park",
      "historical_landmark",
      "restaurant",
      "cafe",
    ],
  }) async {
    // Google Places API limits:
    // - radius: 0..50000
    // - maxResultCount: 1..20
    final safeRadius = radiusMeters.clamp(0, 50000);
    final safeMaxResults = maxResults.clamp(1, 20);

    final rp = (rankPreference.toUpperCase() == "POPULARITY") ? "POPULARITY" : "DISTANCE";

    final url = Uri.parse("https://places.googleapis.com/v1/places:searchNearby");

    final headers = {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": [
        "places.id",
        "places.displayName",
        "places.location",
        "places.primaryType",
        "places.types",
        "places.rating",
        "places.userRatingCount",
        "places.currentOpeningHours",
        "places.websiteUri",
        "places.googleMapsUri",
        "places.primaryTypeDisplayName",
      ].join(","),
    };

    final body = <String, dynamic>{
      "includedTypes": includedTypes,
      "maxResultCount": safeMaxResults,
      "rankPreference": rp,
      "locationRestriction": {
        "circle": {
          "center": {"latitude": lat, "longitude": lng},
          "radius": safeRadius,
        }
      }
    };

    final resp = await http.post(url, headers: headers, body: jsonEncode(body));

    if (resp.statusCode != 200) {
      throw Exception("Places API error ${resp.statusCode}: ${resp.body}");
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final places = (data["places"] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
    return places;
  }

  /// NOVÉ (NEINVASIVNÍ): použije "efektivní" polohu z LocationService:
  /// - pokud je vybrané město (MANUAL), použije jeho souřadnice
  /// - jinak použije GPS polohu zařízení
  Future<List<Map<String, dynamic>>> nearbyFromEffectiveLocation({
    int radiusMeters = 6000,
    int maxResults = 12,
    String rankPreference = "DISTANCE",
    List<String> includedTypes = const [
      "tourist_attraction",
      "museum",
      "park",
      "art_gallery",
      "hiking_area",
      "zoo",
      "aquarium",
      "amusement_park",
      "historical_landmark",
      "restaurant",
      "cafe",
    ],
  }) async {
    final Position? pos = await LocationService.getEffectiveLocation();
    if (pos == null) {
      throw Exception("Effective location is null (GPS unavailable and no manual city selected).");
    }

    return nearby(
      lat: pos.latitude,
      lng: pos.longitude,
      radiusMeters: radiusMeters,
      maxResults: maxResults,
      rankPreference: rankPreference,
      includedTypes: includedTypes,
    );
  }
}