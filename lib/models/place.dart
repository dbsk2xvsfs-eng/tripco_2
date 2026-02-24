class Place {
  final String id;

  final String name;

  /// Playful label (e.g. "⛪️ Culture")
  final String type;

  /// Exact Google Places primaryType (e.g. "museum", "restaurant", "cafe", ...)
  final String? primaryType;

  final int distanceMinutes;

  final double lat;
  final double lng;

  final double? rating;
  final int? userRatingsTotal;
  final bool? openNow;

  /// Website (from places.websiteUri)
  final String? websiteUrl;
  final String? googleMapsUri;

  final bool done;

  const Place({
    required this.id,
    required this.name,
    required this.type,
    required this.distanceMinutes,
    required this.lat,
    required this.lng,
    this.primaryType,
    this.rating,
    this.userRatingsTotal,
    this.openNow,
    this.websiteUrl,
    this.done = false,
    this.googleMapsUri,
  });

  Place copyWith({
    String? id,
    String? name,
    String? type,
    String? primaryType,
    int? distanceMinutes,
    double? lat,
    double? lng,
    double? rating,
    int? userRatingsTotal,
    bool? openNow,
    String? websiteUrl,
    bool? done,
    String? googleMapsUri,
  }) {
    return Place(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      primaryType: primaryType ?? this.primaryType,
      distanceMinutes: distanceMinutes ?? this.distanceMinutes,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      rating: rating ?? this.rating,
      userRatingsTotal: userRatingsTotal ?? this.userRatingsTotal,
      openNow: openNow ?? this.openNow,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      done: done ?? this.done,
      googleMapsUri: googleMapsUri ?? this.googleMapsUri,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "id": id,
      "name": name,
      "type": type,
      "primaryType": primaryType,
      "distanceMinutes": distanceMinutes,
      "lat": lat,
      "lng": lng,
      "rating": rating,
      "userRatingsTotal": userRatingsTotal,
      "openNow": openNow,
      "websiteUrl": websiteUrl,
      "done": done,
      "googleMapsUri": googleMapsUri,
    };
  }

  static Place fromMap(Map<dynamic, dynamic> m) {
    return Place(
      id: (m["id"] ?? "").toString(),
      name: (m["name"] ?? "").toString(),
      type: (m["type"] ?? "✨ Spot").toString(),
      primaryType: m["primaryType"]?.toString(),
      distanceMinutes: (m["distanceMinutes"] as num?)?.toInt() ?? 10,
      lat: (m["lat"] as num?)?.toDouble() ?? 0.0,
      lng: (m["lng"] as num?)?.toDouble() ?? 0.0,
      rating: (m["rating"] as num?)?.toDouble(),
      userRatingsTotal: (m["userRatingsTotal"] as num?)?.toInt(),
      openNow: m["openNow"] as bool?,
      websiteUrl: m["websiteUrl"]?.toString(),
      done: m["done"] as bool? ?? false,
      googleMapsUri: (m["googleMapsUri"] ?? "").toString().isEmpty ? null : (m["googleMapsUri"]).toString(),
    );
  }
}