import 'package:hive/hive.dart';
import '../models/user_profile.dart';

class ProfileStorage {
  static const _boxName = 'tripcoBox';
  static const _keyProfile = 'profile_v1';

  static Box get _box => Hive.box(_boxName);

  static Future<void> save(UserProfile p) async {
    await _box.put(_keyProfile, p.name);
  }

  static UserProfile loadOrDefault() {
    final raw = _box.get(_keyProfile) as String?;
    if (raw == null) return UserProfile.solo;
    return UserProfile.values.firstWhere(
          (e) => e.name == raw,
      orElse: () => UserProfile.solo,
    );
  }
}
