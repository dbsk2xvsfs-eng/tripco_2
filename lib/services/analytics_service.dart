import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  static FirebaseAnalytics? _a;

  static void initIfAvailable() {
    try {
      _a = FirebaseAnalytics.instance;
    } catch (_) {
      _a = null;
    }
  }

  static Future<void> logNavigate(String placeId, String mode) async {
    if (_a == null) return;
    await _a!.logEvent(name: "navigate", parameters: {"place_id": placeId, "mode": mode});
  }

  static Future<void> logReplace(String placeId) async {
    if (_a == null) return;
    await _a!.logEvent(name: "replace", parameters: {"place_id": placeId});
  }

  static Future<void> logRemove(String placeId) async {
    if (_a == null) return;
    await _a!.logEvent(name: "remove", parameters: {"place_id": placeId});
  }

  static Future<void> logFavorite(String placeId, bool isFav) async {
    if (_a == null) return;
    await _a!.logEvent(name: "favorite_toggle", parameters: {"place_id": placeId, "is_fav": isFav});
  }

  static Future<void> logShare(int count) async {
    if (_a == null) return;
    await _a!.logEvent(name: "share_plan", parameters: {"count": count});
  }

  static Future<void> logProfile(String profile) async {
    if (_a == null) return;
    await _a!.logEvent(name: "profile_change", parameters: {"profile": profile});
  }
}
