import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PlacesCacheService {
  static const _prefix = 'places_cache_v1_';

  static String buildKey({
    required double lat,
    required double lng,
    required List<String> includedTypes,
    required int radiusMeters,
    String? rankPreference,
    int precision = 2,
  }) {
    final roundedLat = lat.toStringAsFixed(precision);
    final roundedLng = lng.toStringAsFixed(precision);

    final sortedTypes = [...includedTypes]..sort();

    return [
      roundedLat,
      roundedLng,
      radiusMeters.toString(),
      rankPreference ?? '',
      sortedTypes.join(','),
    ].join('|');
  }

  static Future<void> save({
    required String key,
    required List<Map<String, dynamic>> data,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final payload = {
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    };

    await prefs.setString('$_prefix$key', jsonEncode(payload));
  }

  static Future<List<Map<String, dynamic>>?> load({
    required String key,
    required Duration maxAge,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final savedAtMs = decoded['savedAt'] as int?;
      final data = decoded['data'] as List?;

      if (savedAtMs == null || data == null) return null;

      final savedAt = DateTime.fromMillisecondsSinceEpoch(savedAtMs);
      final age = DateTime.now().difference(savedAt);

      if (age > maxAge) {
        await prefs.remove('$_prefix$key');
        return null;
      }

      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      await prefs.remove('$_prefix$key');
      return null;
    }
  }

  static Future<void> clearExpired({
    Duration maxAge = const Duration(minutes: 15),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;

      final raw = prefs.getString(key);
      if (raw == null) continue;

      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final savedAtMs = decoded['savedAt'] as int?;
        if (savedAtMs == null) {
          await prefs.remove(key);
          continue;
        }

        final savedAt = DateTime.fromMillisecondsSinceEpoch(savedAtMs);
        if (now.difference(savedAt) > maxAge) {
          await prefs.remove(key);
        }
      } catch (_) {
        await prefs.remove(key);
      }
    }
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}