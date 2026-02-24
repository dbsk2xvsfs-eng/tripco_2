import 'package:hive/hive.dart';
import '../models/place.dart';

class SavedPlan {
  final String city;
  final double lat;
  final double lng;
  final List<Place> plan;

  const SavedPlan({
    required this.city,
    required this.lat,
    required this.lng,
    required this.plan,
  });

  Map<String, dynamic> toMap() {
    return {
      "city": city,
      "lat": lat,
      "lng": lng,
      "plan": plan.map((p) => p.toMap()).toList(),
    };
  }

  static SavedPlan fromMap(Map<dynamic, dynamic> m) {
    final planRaw = (m["plan"] as List?) ?? const [];
    final places = planRaw
        .cast<Map>()
        .map((x) => Place.fromMap(x))
        .toList();

    return SavedPlan(
      city: (m["city"] ?? "").toString(),
      lat: (m["lat"] as num?)?.toDouble() ?? 0.0,
      lng: (m["lng"] as num?)?.toDouble() ?? 0.0,
      plan: places,
    );
  }
}

class PlanStorage {
  static const _boxName = 'tripcoBox';

  // Current plan (ALL)
  static const _keyPlan = 'plan_v1';

  // Saved plans list
  static const _keySavedPlans = 'saved_plans_v1';

  static Box get _box => Hive.box(_boxName);

  // -----------------------------
  // CURRENT PLAN (ALL) API
  // -----------------------------

  static Future<void> saveCurrentPlan(List<Place> plan) async {
    await savePlan(plan);
  }

  static List<Place>? loadCurrentPlan() {
    return loadPlan();
  }

  static Future<void> clearCurrentPlan() async {
    await clearPlan();
  }

  // Backwards-compatible names
  static Future<void> savePlan(List<Place> plan) async {
    final data = plan.map((p) => p.toMap()).toList();
    await _box.put(_keyPlan, data);
  }

  static List<Place>? loadPlan() {
    final data = _box.get(_keyPlan);
    if (data == null) return null;

    final list = (data as List).cast<Map>();
    return list.map((m) => Place.fromMap(m)).toList();
  }

  static Future<void> clearPlan() async {
    await _box.delete(_keyPlan);
  }

  // -----------------------------
  // SAVED PLANS (max 5, by city)
  // -----------------------------

  static List<SavedPlan> loadSavedPlans() {
    final data = _box.get(_keySavedPlans);
    if (data == null) return <SavedPlan>[];

    final list = (data as List).cast<Map>();
    return list.map((m) => SavedPlan.fromMap(m)).where((x) => x.city.trim().isNotEmpty).toList();
  }

  static Future<void> upsertSavedPlan({
    required String city,
    required double lat,
    required double lng,
    required List<Place> plan,
  }) async {
    final c = city.trim();
    if (c.isEmpty) return;

    final items = loadSavedPlans();

    // remove old for same city (case-insensitive)
    items.removeWhere((x) => x.city.trim().toLowerCase() == c.toLowerCase());

    // add new
    items.add(SavedPlan(city: c, lat: lat, lng: lng, plan: List<Place>.from(plan)));

    // sort A-Z by city
    items.sort((a, b) => a.city.toLowerCase().compareTo(b.city.toLowerCase()));

    // keep max 5
    while (items.length > 5) {
      items.removeLast();
    }

    await _box.put(_keySavedPlans, items.map((x) => x.toMap()).toList());
  }

  static Future<void> deleteSavedPlan(String city) async {
    final c = city.trim();
    if (c.isEmpty) return;

    final items = loadSavedPlans();
    items.removeWhere((x) => x.city.trim().toLowerCase() == c.toLowerCase());

    await _box.put(_keySavedPlans, items.map((x) => x.toMap()).toList());
  }
}