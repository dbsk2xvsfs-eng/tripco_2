import 'package:hive/hive.dart';
import '../models/place.dart';

class PlanStorage {
  static const _boxName = 'tripcoBox';

  /// Aktuální (autosave) plán = vždy se načítá po startu aplikace
  static const _keyCurrentPlan = 'plan_current_v2';

  /// Archiv uložených plánů (snapshots) – seznam map
  static const _keySavedPlans = 'plan_saved_list_v2';

  static Box get _box => Hive.box(_boxName);

  // ---------------------------------------------------------------------------
  // CURRENT PLAN (autosave)
  // ---------------------------------------------------------------------------

  static Future<void> saveCurrentPlan(List<Place> plan) async {
    final data = plan.map((p) => p.toMap()).toList();
    await _box.put(_keyCurrentPlan, data);
  }

  static List<Place>? loadCurrentPlan() {
    final data = _box.get(_keyCurrentPlan);
    if (data == null) return null;

    final list = (data as List).cast<Map>();
    return list.map((m) => Place.fromMap(m)).toList();
  }

  static Future<void> clearCurrentPlan() async {
    await _box.delete(_keyCurrentPlan);
  }

  // ---------------------------------------------------------------------------
  // SAVED PLANS (snapshots)
  // ---------------------------------------------------------------------------

  /// Uloží snapshot aktuálního plánu do archivu "Uloženo".
  /// cityName může být prázdné – UI si může zobrazit fallback.
  static Future<void> addSavedPlanSnapshot({
    required List<Place> plan,
    required double lat,
    required double lng,
    required String cityName,
  }) async {
    final saved = loadSavedPlans();

    final snapshot = <String, dynamic>{
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
      'cityName': cityName,
      'lat': lat,
      'lng': lng,
      'plan': plan.map((p) => p.toMap()).toList(),
    };

    // přidáme nahoru (nejnovější první)
    saved.insert(0, snapshot);

    await _box.put(_keySavedPlans, saved);
  }

  /// Vrátí raw seznam uložených snapshotů (Map).
  /// Každý prvek obsahuje: id, createdAtMs, cityName, lat, lng, plan(List<Map>)
  static List<Map<String, dynamic>> loadSavedPlans() {
    final data = _box.get(_keySavedPlans);
    if (data == null) return <Map<String, dynamic>>[];

    final list = (data as List).cast<Map>();
    return list.map((m) => Map<String, dynamic>.from(m)).toList();
  }

  /// Načte konkrétní uložený plán (places) podle id.
  static List<Place>? loadSavedPlanById(String id) {
    final saved = loadSavedPlans();
    final found = saved.cast<Map<String, dynamic>>().firstWhere(
          (m) => (m['id'] ?? '').toString() == id,
      orElse: () => <String, dynamic>{},
    );

    if (found.isEmpty) return null;

    final planData = found['plan'];
    if (planData is! List) return null;

    final list = planData.cast<Map>();
    return list.map((m) => Place.fromMap(m)).toList();
  }

  static Future<void> deleteSavedPlanById(String id) async {
    final saved = loadSavedPlans();
    saved.removeWhere((m) => (m['id'] ?? '').toString() == id);
    await _box.put(_keySavedPlans, saved);
  }

  static Future<void> clearSavedPlans() async {
    await _box.delete(_keySavedPlans);
  }

  // ---------------------------------------------------------------------------
  // BACKWARD COMPAT (původní API) – mapujeme na CURRENT PLAN
  // ---------------------------------------------------------------------------

  static Future<void> savePlan(List<Place> plan) => saveCurrentPlan(plan);
  static List<Place>? loadPlan() => loadCurrentPlan();
  static Future<void> clearPlan() => clearCurrentPlan();
}