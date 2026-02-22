import 'package:url_launcher/url_launcher.dart';
import '../models/transport_option.dart';

class NavigationService {
  static String _travelMode(TransportType t) {
    switch (t) {
      case TransportType.walk:
        return "walking";
      case TransportType.bike:
        return "bicycling";
      case TransportType.transit:
        return "transit";
      case TransportType.car:
        return "driving";
    }
  }

  static Future<void> openNavigation({
    required double destLat,
    required double destLng,
    required TransportType type,
  }) async {
    final mode = _travelMode(type);
    final uri = Uri.parse(
      "https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng&travelmode=$mode",
    );

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw Exception("Could not open maps");
    }
  }
}
