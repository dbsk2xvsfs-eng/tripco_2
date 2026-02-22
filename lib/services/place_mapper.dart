import '../models/place.dart';

class PlaceMapper {
  // Priority, kterou chceme pro "náš" primaryType (kvůli kategoriím v appce)
  static const List<String> _preferredTypes = [
    // Food
    "cafe",
    "restaurant",

    // Culture / castles
    "castle",
    "museum",
    "art_gallery",
    "historical_landmark",

    // Nature
    "park",
    "hiking_area",

    // Attraction
    "tourist_attraction",
    "amusement_park",
    "zoo",
    "aquarium",
  ];

  static String playfulTypeFromPrimary(String? primaryType) {
    switch ((primaryType ?? "").trim()) {
      case "park":
      case "hiking_area":
        return "🌳 Nature";

      case "museum":
      case "art_gallery":
      case "historical_landmark":
      case "castle":
        return "🏛️ Culture";

      case "amusement_park":
      case "zoo":
      case "aquarium":
      case "tourist_attraction":
        return "🎡 Attraction";

      case "restaurant":
        return "🍽️ Restaurant";

      case "cafe":
        return "☕ Cafe";

    // shopping_mall vědomě ignorujeme – nechceme ho nikde používat
      case "shopping_mall":
        return "✨ Spot";

      default:
        return "✨ Spot";
    }
  }

  /// Vrátí "náš" primaryType:
  /// - když je Google primaryType už užitečný (cafe/restaurant/...), nechá ho
  /// - jinak zkusí najít match v `types[]` podle priority výše
  /// - shopping_mall ignoruje
  static String? inferAppPrimaryType(Map<String, dynamic> p) {
    final rawPrimary = (p["primaryType"] ?? "").toString().trim();
    final primary = rawPrimary.isEmpty ? null : rawPrimary;

    // Z types může chodit List<dynamic> nebo null
    final typesRaw = p["types"];
    final List<String> types = (typesRaw is List)
        ? typesRaw.map((e) => e.toString().trim()).where((x) => x.isNotEmpty).toList()
        : const <String>[];

    // Pokud primaryType je přímo v preferovaných, použij ho (krom shopping_mall)
    if (primary != null && primary != "shopping_mall") {
      if (_preferredTypes.contains(primary)) return primary;

      // Někdy Google vrátí primaryType "restaurant"/"cafe" i když v types to je taky
      // (už to řešíme výše), tady už jen fallback na types.
    }

    // Hledej nejlepší typ v types[] podle priority
    for (final want in _preferredTypes) {
      if (want == "shopping_mall") continue; // pro jistotu
      if (types.contains(want)) return want;
    }

    // Když nic – vrať primary pokud není shopping_mall, jinak null
    if (primary != null && primary != "shopping_mall") return primary;
    return null;
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

    final inferredPrimaryType = inferAppPrimaryType(p);

    final rating = (p["rating"] as num?)?.toDouble();
    final userRatingCount = (p["userRatingCount"] as num?)?.toInt();
    final openNow = p["currentOpeningHours"]?["openNow"] as bool?;
    final websiteUrl = p["websiteUri"]?.toString();

    return Place(
      id: id,
      name: displayName,
      type: playfulTypeFromPrimary(inferredPrimaryType),
      primaryType: inferredPrimaryType, // 👈 klíčové: pro kategorie v appce
      distanceMinutes: distanceMinutes,
      lat: lat,
      lng: lng,
      rating: rating,
      userRatingsTotal: userRatingCount,
      openNow: openNow,
      websiteUrl: websiteUrl,
      done: false,
    );
  }
}