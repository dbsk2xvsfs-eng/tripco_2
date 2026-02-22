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
      "shopping_mall",
      "historical_landmark",
      "restaurant",
      "cafe",
    ],
  }) async {
    final url = Uri.parse("https://places.googleapis.com/v1/places:searchNearby");

    // Places API: maxResultCount musí být 1..20
    final safeMax = maxResults.clamp(1, 20);

    final headers = {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask":
      "places.id,places.displayName,places.location,places.primaryType,places.rating,places.userRatingCount,places.currentOpeningHours,places.websiteUri",
    };

    final body = {
      "includedTypes": includedTypes,
      "maxResultCount": safeMax,
      "locationRestriction": {
        "circle": {
          "center": {"latitude": lat, "longitude": lng},
          "radius": radiusMeters,
        }
      }
    };

    final resp = await http.post(url, headers: headers, body: jsonEncode(body));
    if (resp.statusCode != 200) {
      throw Exception("Places API error ${resp.statusCode}: ${resp.body}");
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (data["places"] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }
}