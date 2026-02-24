import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// LocationService:
/// - Zachovává původní API: [getCurrentLocation]
/// - Přidává možnost ručního override města (MANUAL) nad GPS
/// - Exponuje notifiery pro UI (label + effective position)
class LocationService {
  /// Label pro UI v headeru:
  /// - výchozí: "GPS"
  /// - po výběru města: např. "Brno"
  static final ValueNotifier<String> locationLabel =
  ValueNotifier<String>('GPS');

  /// Ručně zvolená poloha (pokud je null, používá se GPS).
  static final ValueNotifier<Position?> manualOverridePosition =
  ValueNotifier<Position?>(null);

  /// Efektivní poloha, kterou má aplikace používat.
  /// UI si na ni může napojit listener a při změně refetchovat místa.
  static final ValueNotifier<Position?> effectivePosition =
  ValueNotifier<Position?>(null);

  /// Původní funkce: vrací aktuální GPS polohu zařízení (neřeší manual override).
  /// Zachováno beze změny, aby nic ve stávajícím kódu neprasklo.
  static Future<Position?> getCurrentLocation() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }

    if (permission == LocationPermission.deniedForever) return null;

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  /// Nové: nastaví ruční město/polohu (override nad GPS).
  /// [label] se zobrazí místo "GPS" v headeru.
  static void setManualLocation({
    required String label,
    required double latitude,
    required double longitude,
  }) {
    final pos = Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      // i když tyhle hodnoty nepoužíváš, Position je vyžaduje
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );

    manualOverridePosition.value = pos;
    locationLabel.value = label;
    effectivePosition.value = pos;
  }

  /// Nové: zruší ruční override a vrátí aplikaci zpět na GPS mód.
  static Future<void> clearManualLocation() async {
    manualOverridePosition.value = null;
    locationLabel.value = 'GPS';

    // Update effective position na aktuální GPS (pokud dostupná)
    final gps = await getCurrentLocation();
    effectivePosition.value = gps;
  }

  /// Nové: vrátí polohu, kterou má aplikace používat:
  /// - pokud existuje manual override, vrátí ten
  /// - jinak vrátí aktuální GPS
  static Future<Position?> getEffectiveLocation() async {
    final manual = manualOverridePosition.value;
    if (manual != null) {
      effectivePosition.value = manual;
      return manual;
    }

    final gps = await getCurrentLocation();
    effectivePosition.value = gps;
    return gps;
  }

  /// Volitelné: zavolej při startu obrazovky/appky, aby se effectivePosition naplnilo.
  static Future<void> initEffectiveLocation() async {
    await getEffectiveLocation();
  }
}