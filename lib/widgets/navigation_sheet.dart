import 'package:flutter/material.dart';
import '../i18n/strings.dart';
import '../models/place.dart';
import '../models/transport_option.dart';
import '../services/analytics_service.dart';
import '../services/navigation_service.dart';
import '../services/routes_service.dart';

class NavigationSheet extends StatefulWidget {
  final Place place;
  final double originLat;
  final double originLng;
  final RoutesService routes;

  const NavigationSheet({
    super.key,
    required this.place,
    required this.originLat,
    required this.originLng,
    required this.routes,
  });

  @override
  State<NavigationSheet> createState() => _NavigationSheetState();
}

class _NavigationSheetState extends State<NavigationSheet> {
  bool _loading = true;
  String? _error;
  List<TransportOption> _options = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return "$minutes min";
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return "$h:${m.toString().padLeft(2, '0')} hod";
  }

  String _formatKm(int distanceMeters) {
    final km = distanceMeters / 1000.0;
    return "${km.toStringAsFixed(1)} km";
  }

  Future<void> _load() async {
    try {
      final modes = <RouteTravelMode>[
        RouteTravelMode.walk,
        RouteTravelMode.transit,
        RouteTravelMode.drive,
      ];

      final results = await Future.wait(modes.map((m) async {
        try {
          return await widget.routes.computeRoute(
            originLat: widget.originLat,
            originLng: widget.originLng,
            destLat: widget.place.lat,
            destLng: widget.place.lng,
            mode: m,
          );
        } catch (_) {
          // If one mode fails (e.g., transit not available), just skip it.
          return null;
        }
      }));

      final opts = <TransportOption>[];
      for (int i = 0; i < modes.length; i++) {
        final m = modes[i];
        final r = results[i];
        if (r == null) continue;
        if (r.distanceMeters <= 0 || r.durationSeconds <= 0) continue;

        final label = switch (m) {
          RouteTravelMode.walk => "Walking",
          RouteTravelMode.transit => "Public transport",
          RouteTravelMode.drive => "Car",
        };

        final type = switch (m) {
          RouteTravelMode.walk => TransportType.walk,
          RouteTravelMode.transit => TransportType.transit,
          RouteTravelMode.drive => TransportType.car,
        };

        opts.add(
          TransportOption(
            type: type,
            label: label,
            minutes: r.durationMinutes,
            distanceMeters: r.distanceMeters,
          ),
        );
      }

      setState(() {
        _options = opts;
        _loading = false;
        _error = opts.isEmpty ? "No routes found" : null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  IconData _iconFor(TransportType type) {
    switch (type) {
      case TransportType.walk:
        return Icons.directions_walk;
      case TransportType.transit:
        return Icons.directions_transit;
      case TransportType.car:
        return Icons.directions_car;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.chooseRide,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            if (_loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),

            if (!_loading && _error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text("Routing error: $_error"),
              ),

            if (!_loading && _error == null)
              ..._options.map((o) {
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    leading: Icon(_iconFor(o.type)),
                    title: Text(
                      "${o.label} · ${_formatMinutes(o.minutes)} · ${_formatKm(o.distanceMeters)}",
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await AnalyticsService.logNavigate(widget.place.id, o.label);
                      await NavigationService.openNavigation(
                        destLat: widget.place.lat,
                        destLng: widget.place.lng,
                        type: o.type,
                      );
                    },
                  ),
                );
              }),

            const SizedBox(height: 6),
            Text(
              s.timesReal,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}