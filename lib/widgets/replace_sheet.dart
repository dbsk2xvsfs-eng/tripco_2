import 'dart:math';
import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../models/place.dart';
import '../services/places_service.dart';
import '../services/place_mapper.dart';

class ReplaceSheet extends StatefulWidget {
  final PlacesService places;
  final double originLat;
  final double originLng;

  /// IDs already in plan (exclude duplicates)
  final Set<String> excludeIds;

  /// Allowed primaryTypes for current category. If null/empty => allow all.
  final Set<String>? allowedPrimaryTypes;

  const ReplaceSheet({
    super.key,
    required this.places,
    required this.originLat,
    required this.originLng,
    required this.excludeIds,
    this.allowedPrimaryTypes,
  });

  @override
  State<ReplaceSheet> createState() => _ReplaceSheetState();
}

class _ReplaceSheetState extends State<ReplaceSheet> {
  bool _loading = true;
  String? _error;

  List<_Candidate> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _deg2rad(double d) => d * (pi / 180.0);

  int _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return (R * c).round();
  }

  int _metersToMinutesWalkApprox(int meters) {
    // ~5 km/h => 83.33 m/min
    final m = (meters / 83.33).round();
    return m < 1 ? 1 : m;
  }

  String _formatKm(int meters) {
    final km = meters / 1000.0;
    return "${km.toStringAsFixed(km < 10 ? 1 : 0)} km";
  }

  Future<void> _load() async {
    try {
      final raw = await widget.places.nearby(
        lat: widget.originLat,
        lng: widget.originLng,
        radiusMeters: 8000,
        maxResults: 30,
      );

      final allowed = widget.allowedPrimaryTypes;
      final filtered = <_Candidate>[];

      for (final p in raw) {
        final id = (p["id"] ?? "").toString();
        if (id.isEmpty) continue;
        if (widget.excludeIds.contains(id)) continue;

        final primaryType = p["primaryType"]?.toString();
        if (allowed != null && allowed.isNotEmpty) {
          if (primaryType == null || !allowed.contains(primaryType)) continue;
        }

        final loc = p["location"] ?? {};
        final lat = (loc["latitude"] as num?)?.toDouble() ?? 0.0;
        final lng = (loc["longitude"] as num?)?.toDouble() ?? 0.0;

        final distMeters = _haversineMeters(widget.originLat, widget.originLng, lat, lng);
        final minutes = _metersToMinutesWalkApprox(distMeters);

        final place = PlaceMapper.fromGooglePlace(p, distanceMinutes: minutes);

        filtered.add(_Candidate(place: place, distMeters: distMeters));
      }

      filtered.sort((a, b) => a.distMeters.compareTo(b.distMeters));

      setState(() {
        _items = filtered;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  IconData _iconForPrimary(String? t) {
    switch (t) {
      case "museum":
      case "art_gallery":
      case "historical_landmark":
        return Icons.museum;

      case "park":
      case "hiking_area":
        return Icons.park;

      case "restaurant":
        return Icons.restaurant;

      case "cafe":
        return Icons.local_cafe;

      case "shopping_mall":
        return Icons.shopping_bag;

      case "zoo":
      case "aquarium":
      case "amusement_park":
      case "tourist_attraction":
        return Icons.attractions;

      default:
        return Icons.place;
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
              "Replace",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            if (_loading)
              const Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(),
              ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text("Load failed: $_error"),
              ),

            if (!_loading && _error == null)
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = _items[i];
                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        leading: Icon(_iconForPrimary(c.place.primaryType)),
                        title: Text(c.place.name),
                        subtitle: Text("${c.place.primaryType ?? ""} · ${_formatKm(c.distMeters)}"),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.of(context).pop(c.place);
                        },
                      ),
                    );
                  },
                ),
              ),

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

class _Candidate {
  final Place place;
  final int distMeters;

  _Candidate({required this.place, required this.distMeters});
}