import 'dart:convert';
import 'package:http/http.dart' as http;

enum RouteTravelMode { drive, walk, transit }

class RouteResult {
  final int distanceMeters;
  final int durationSeconds;

  RouteResult({required this.distanceMeters, required this.durationSeconds});

  int get durationMinutes => (durationSeconds / 60).round();
}

class RoutesService {
  final String apiKey;
  RoutesService({required this.apiKey});

  String _mode(RouteTravelMode m) {
    switch (m) {
      case RouteTravelMode.drive:
        return "DRIVE";
      case RouteTravelMode.walk:
        return "WALK";
      case RouteTravelMode.transit:
        return "TRANSIT";
    }
  }

  int _parseDurationSeconds(String duration) {
    final clean = duration.trim().replaceAll("s", "");
    final seconds = double.tryParse(clean) ?? 0.0;
    return seconds.round();
  }

  Future<RouteResult> computeRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    required RouteTravelMode mode,
  }) async {
    print("ROUTE REQ mode=$mode origin=$originLat,$originLng dest=$destLat,$destLng");
    final url = Uri.parse("https://routes.googleapis.com/directions/v2:computeRoutes");

    final headers = {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": "routes.distanceMeters,routes.duration",
    };

    final body = {
      "origin": {
        "location": {"latLng": {"latitude": originLat, "longitude": originLng}}
      },
      "destination": {
        "location": {"latLng": {"latitude": destLat, "longitude": destLng}}
      },
      "travelMode": _mode(mode),
      "languageCode": "en",
    };

    final resp = await http.post(url, headers: headers, body: jsonEncode(body));
    print("ROUTES RAW RESPONSE: ${resp.body}");
    if (resp.statusCode != 200) {
      throw Exception("Routes API error ${resp.statusCode}: ${resp.body}");
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final routes = (data["routes"] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (routes.isEmpty) {
      return RouteResult(distanceMeters: 0, durationSeconds: 0);
    }

    final r0 = routes.first;
    final distanceMeters = (r0["distanceMeters"] as num?)?.toInt() ?? 0;
    final durationStr = (r0["duration"] as String?) ?? "0s";
    final durationSeconds = _parseDurationSeconds(durationStr);

    return RouteResult(distanceMeters: distanceMeters, durationSeconds: durationSeconds);
  }
}
