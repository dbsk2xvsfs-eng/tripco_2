import 'package:hive/hive.dart';

class FavoritesStorage {
  static const _boxName = 'tripcoBox';
  static const _keyFav = 'favorites_v1';

  static Box get _box => Hive.box(_boxName);

  static List<String> loadFavoriteIds() {
    final data = _box.get(_keyFav);
    if (data == null) return [];
    return (data as List).map((e) => e.toString()).toList();
  }

  static bool isFavorite(String placeId) {
    return loadFavoriteIds().contains(placeId);
  }

  static Future<bool> toggleFavorite(String placeId) async {
    final favs = loadFavoriteIds().toSet();
    final nowFav = !favs.contains(placeId);
    if (nowFav) {
      favs.add(placeId);
    } else {
      favs.remove(placeId);
    }
    await _box.put(_keyFav, favs.toList());
    return nowFav;
  }
}
