class Place {
  final String id;

  final String name;
  final String type; // playful: "🌳 Nature" etc.

  final String entryPrice; // MVP: often "Unknown"
  final String transportPrice; // optional text

  final String crowdLevel; // MVP: "Unknown" (later improve)
  final int distanceMinutes; // MVP seed (later from routes)

  final double lat;
  final double lng;

  final double? rating;
  final int? userRatingsTotal;
  final bool? openNow;

  final bool done;

  const Place({
    required this.id,
    required this.name,
    required this.type,
    required this.entryPrice,
    required this.transportPrice,
    required this.crowdLevel,
    required this.distanceMinutes,
    required this.lat,
    required this.lng,
    this.rating,
    this.userRatingsTotal,
    this.openNow,
    this.done = false,
  });

  Place copyWith({
    String? id,
    String? name,
    String? type,
    String? entryPrice,
    String? transportPrice,
    String? crowdLevel,
    int? distanceMinutes,
    double? lat,
    double? lng,
    double? rating,
    int? userRatingsTotal,
    bool? openNow,
    bool? done,
  }) {
    return Place(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      entryPrice: entryPrice ?? this.entryPrice,
      transportPrice: transportPrice ?? this.transportPrice,
      crowdLevel: crowdLevel ?? this.crowdLevel,
      distanceMinutes: distanceMinutes ?? this.distanceMinutes,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      rating: rating ?? this.rating,
      userRatingsTotal: userRatingsTotal ?? this.userRatingsTotal,
      openNow: openNow ?? this.openNow,
      done: done ?? this.done,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "id": id,
      "name": name,
      "type": type,
      "entryPrice": entryPrice,
      "transportPrice": transportPrice,
      "crowdLevel": crowdLevel,
      "distanceMinutes": distanceMinutes,
      "lat": lat,
      "lng": lng,
      "rating": rating,
      "userRatingsTotal": userRatingsTotal,
      "openNow": openNow,
      "done": done,
    };
  }

  static Place fromMap(Map<dynamic, dynamic> m) {
    return Place(
      id: (m["id"] ?? "").toString(),
      name: (m["name"] ?? "").toString(),
      type: (m["type"] ?? "✨ Spot").toString(),
      entryPrice: (m["entryPrice"] ?? "Unknown").toString(),
      transportPrice: (m["transportPrice"] ?? "€?").toString(),
      crowdLevel: (m["crowdLevel"] ?? "Unknown").toString(),
      distanceMinutes: (m["distanceMinutes"] as num?)?.toInt() ?? 10,
      lat: (m["lat"] as num?)?.toDouble() ?? 0.0,
      lng: (m["lng"] as num?)?.toDouble() ?? 0.0,
      rating: (m["rating"] as num?)?.toDouble(),
      userRatingsTotal: (m["userRatingsTotal"] as num?)?.toInt(),
      openNow: m["openNow"] as bool?,
      done: m["done"] as bool? ?? false,
    );
  }
}
