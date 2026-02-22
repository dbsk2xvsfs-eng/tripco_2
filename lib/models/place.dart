class Place {
  final String id;

  final String name;
  final String type;

  final int distanceMinutes;

  final double lat;
  final double lng;

  final double? rating;
  final int? userRatingsTotal;
  final bool? openNow;

  final String? websiteUrl; // ✅ NOVÉ

  final bool done;

  const Place({
    required this.id,
    required this.name,
    required this.type,
    required this.distanceMinutes,
    required this.lat,
    required this.lng,
    this.rating,
    this.userRatingsTotal,
    this.openNow,
    this.websiteUrl, // ✅ NOVÉ
    this.done = false,
  });

  Place copyWith({
    String? id,
    String? name,
    String? type,
    int? distanceMinutes,
    double? lat,
    double? lng,
    double? rating,
    int? userRatingsTotal,
    bool? openNow,
    String? websiteUrl,
    bool? done,
  }) {
    return Place(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      distanceMinutes: distanceMinutes ?? this.distanceMinutes,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      rating: rating ?? this.rating,
      userRatingsTotal: userRatingsTotal ?? this.userRatingsTotal,
      openNow: openNow ?? this.openNow,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      done: done ?? this.done,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "id": id,
      "name": name,
      "type": type,
      "distanceMinutes": distanceMinutes,
      "lat": lat,
      "lng": lng,
      "rating": rating,
      "userRatingsTotal": userRatingsTotal,
      "openNow": openNow,
      "websiteUrl": websiteUrl, // ✅ NOVÉ
      "done": done,
    };
  }

  static Place fromMap(Map<dynamic, dynamic> m) {
    return Place(
      id: (m["id"] ?? "").toString(),
      name: (m["name"] ?? "").toString(),
      type: (m["type"] ?? "✨ Spot").toString(),
      distanceMinutes: (m["distanceMinutes"] as num?)?.toInt() ?? 10,
      lat: (m["lat"] as num?)?.toDouble() ?? 0.0,
      lng: (m["lng"] as num?)?.toDouble() ?? 0.0,
      rating: (m["rating"] as num?)?.toDouble(),
      userRatingsTotal: (m["userRatingsTotal"] as num?)?.toInt(),
      openNow: m["openNow"] as bool?,
      websiteUrl: m["websiteUrl"]?.toString(), // ✅ NOVÉ
      done: m["done"] as bool? ?? false,
    );
  }
}