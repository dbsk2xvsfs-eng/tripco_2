import '../models/place.dart';
import '../models/user_profile.dart';
import 'places_service.dart';
import 'place_mapper.dart';

class RecommendationService {
  final PlacesService places;
  RecommendationService({required this.places});

  Future<List<Place>> getTodayPlan({
    required double lat,
    required double lng,
    required UserProfile profile,
    int maxItems = 10,
  }) async {
    final includedTypes = _typesForProfile(profile);

    final raw = await places.nearby(
      lat: lat,
      lng: lng,
      radiusMeters: 6000,
      maxResults: 18,
      includedTypes: includedTypes,
    );

    int minutesSeed = 8;
    final mapped = raw.map((p) {
      minutesSeed += 2;
      return PlaceMapper.fromGooglePlace(p, distanceMinutes: minutesSeed);
    }).toList();

    final filtered = mapped.where((x) => x.openNow != false).toList();
    filtered.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));

    return filtered.take(maxItems).toList();
  }

  Future<Place?> replaceOne({
    required double lat,
    required double lng,
    required UserProfile profile,
    required Place current,
    required Set<String> excludeIds,
  }) async {
    final includedTypes = _typesForVibe(current.type) ?? _typesForProfile(profile);

    final raw = await places.nearby(
      lat: lat,
      lng: lng,
      radiusMeters: 8000,
      maxResults: 20,
      includedTypes: includedTypes,
    );

    int minutesSeed = 10;
    final candidates = raw
        .map((p) {
      minutesSeed += 2;
      return PlaceMapper.fromGooglePlace(p, distanceMinutes: minutesSeed);
    })
        .where((p) => p.id.isNotEmpty)
        .where((p) => !excludeIds.contains(p.id))
        .where((p) => p.openNow != false)
        .toList();

    candidates.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    if (candidates.isEmpty) return null;
    return candidates.first;
  }

  List<String> _typesForProfile(UserProfile p) {
    switch (p) {
      case UserProfile.solo:
        return ["museum", "art_gallery", "historical_landmark", "viewpoint", "park", "tourist_attraction"];
      case UserProfile.couple:
        return ["viewpoint", "park", "tourist_attraction", "museum", "art_gallery"];
      case UserProfile.family:
        return ["park", "tourist_attraction", "museum", "shopping_mall"];
      case UserProfile.kids:
        return ["zoo", "aquarium", "amusement_park", "park", "tourist_attraction"];
    }
  }

  List<String>? _typesForVibe(String playfulType) {
    if (playfulType.contains("Nature")) {
      return ["park", "hiking_area", "tourist_attraction"];
    }
    if (playfulType.contains("Culture")) {
      return ["museum", "art_gallery", "historical_landmark", "tourist_attraction"];
    }
    if (playfulType.contains("View")) {
      return ["viewpoint", "tourist_attraction", "park"];
    }
    if (playfulType.contains("Attraction")) {
      return ["amusement_park", "zoo", "aquarium", "tourist_attraction"];
    }
    return null;
  }
}
