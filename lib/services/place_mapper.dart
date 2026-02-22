import '../models/place.dart';

class PlaceMapper {
  static String playfulTypeFromPrimary(String? primaryType) {
    switch (primaryType) {
      case "park":
      case "hiking_area":
        return "🌳 Nature";
      case "museum":
      case "art_gallery":
      case "historical_landmark":
        return "🏛️ Culture";
      case "amusement_park":
      case "zoo":
      case "aquarium":
        return "🎡 Attraction";
      case "shopping_mall":
        return "🛍️ Spot";
      default:
        return "✨ Spot";
    }
  }

  static Place fromGooglePlace(
      Map<String, dynamic> p, {
        required int distanceMinutes,
      }) {
    final id = (p["id"] ?? "").toString();
    final displayName = (p["displayName"]?["text"] ?? "Unknown").toString();

    final loc = p["location"] ?? {};
    final lat = (loc["latitude"] as num?)?.toDouble() ?? 0.0;
    final lng = (loc["longitude"] as num?)?.toDouble() ?? 0.0;

    final primaryType = p["primaryType"]?.toString();
    final rating = (p["rating"] as num?)?.toDouble();
    final userRatingCount = (p["userRatingCount"] as num?)?.toInt();
    final openNow = p["currentOpeningHours"]?["openNow"] as bool?;

    // 🔥 NOVÉ – načteme websiteUri z Places API (v1)
    final websiteUrl = p["websiteUri"]?.toString();

    return Place(
      id: id,
      name: displayName,
      type: playfulTypeFromPrimary(primaryType),
      distanceMinutes: distanceMinutes,
      lat: lat,
      lng: lng,
      rating: rating,
      userRatingsTotal: userRatingCount,
      openNow: openNow,
      websiteUrl: websiteUrl, // 👈 přidáno
      done: false,
    );
  }
}