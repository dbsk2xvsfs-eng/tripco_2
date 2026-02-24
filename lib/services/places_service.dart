import 'dart:convert';
import 'package:http/http.dart' as http;

class PlacesService {
  final String apiKey;
  PlacesService({required this.apiKey});

  Future<List<Map<String, dynamic>>> nearby({
    required double lat,
    required double lng,
    int radiusMeters = 6000,
    int maxResults = 12,
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

    final url = Uri.parse("https://places.googleapis.com/v1/places:searchNearby");

    final headers = {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": [
        "places.id",
        "places.displayName",
        "places.location",
        "places.primaryType",
        "places.types", // ✅ důležité pro Cafe/Restaurant fallback
        "places.rating",
        "places.userRatingCount",
        "places.currentOpeningHours",
        "places.websiteUri",
        "places.googleMapsUri",
        // volitelné (když chceš někdy zobrazovat přímo text od Googlu)
        "places.primaryTypeDisplayName",
      ].join(","),
    };

    final body = {
      "includedTypes": includedTypes,
      "maxResultCount": safeMaxResults,
      "rankPreference": "DISTANCE", // ✅ nejbližší první
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
    final places = (data["places"] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return places;
  }
}