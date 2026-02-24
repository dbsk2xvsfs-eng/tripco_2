import '../models/place.dart';

class PlaceMapper {
  static String playfulTypeFromPrimary(String? primaryType) {
    switch (primaryType) {
      case "park":
      case "hiking_area":
      case "landmark":
        return "🌳 Nature";

      case "museum":
        return "🏛️ Museum";

      case "art_gallery":
      case "historical_landmark":
      case "library":
      case "monument":
      case "bridge":
      case "cathedral":
        return "⛪️ Culture";

      case "castle":
      case "church":
        return "🏰 Castles";

      case "amusement_park":
      case "zoo":
      case "aquarium":
      case "tourist_attraction":
      case "point_of_interest":
        return "🎡 Attraction";

      case "restaurant":
        return "🥣 Restaurant";

      case "cafe":
        return "☕ Cafe";

    // shopping_mall ignorujeme v celé appce
      case "shopping_mall":
        return "✨ Spot";

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
    final websiteUrl = p["websiteUri"]?.toString();
    final googleMapsUri = p["googleMapsUri"]?.toString();

    return Place(
      id: id,
      name: displayName,
      type: playfulTypeFromPrimary(primaryType),
      primaryType: primaryType,
      distanceMinutes: distanceMinutes,
      lat: lat,
      lng: lng,
      rating: rating,
      userRatingsTotal: userRatingCount,
      openNow: openNow,
      websiteUrl: websiteUrl,
      done: false,
      googleMapsUri: googleMapsUri,
    );
  }
}