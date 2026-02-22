import 'package:hive/hive.dart';
import '../models/place.dart';

class PlanStorage {
  static const _boxName = 'tripcoBox';
  static const _keyPlan = 'plan_v1';

  static Box get _box => Hive.box(_boxName);

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
}
