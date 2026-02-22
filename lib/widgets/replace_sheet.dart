import 'dart:math';
import 'package:flutter/material.dart';

import '../models/place.dart';

class ReplaceSheet extends StatelessWidget {
  final String title;

  final double originLat;
  final double originLng;

  // co právě nahrazuju
  final String currentId;

  // aby nešlo vybrat něco, co už v All je
  final Set<String> allIds;

  // kandidáti už jsou pool pro kategorii
  final List<Place> candidates;

  const ReplaceSheet({
    super.key,
    required this.title,
    required this.originLat,
    required this.originLng,
    required this.currentId,
    required this.allIds,
    required this.candidates,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...candidates];
    sorted.sort((a, b) {
      final da = _haversineMeters(originLat, originLng, a.lat, a.lng);
      final db = _haversineMeters(originLat, originLng, b.lat, b.lng);
      return da.compareTo(db);
    });

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sorted.length,
                itemBuilder: (context, i) {
                  final p = sorted[i];
                  final distKm = _haversineMeters(originLat, originLng, p.lat, p.lng) / 1000.0;

                  final disabled = p.id == currentId || allIds.contains(p.id);

                  return Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: ListTile(
                      title: Text(p.name),
                      subtitle: Text("${distKm.toStringAsFixed(1)} km"),
                      trailing: const Icon(Icons.swap_horiz),
                      enabled: !disabled,
                      onTap: disabled ? null : () => Navigator.of(context).pop(p),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLon = _degToRad(lon2 - lon1);
  final a = (sin(dLat / 2) * sin(dLat / 2)) +
      cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * (sin(dLon / 2) * sin(dLon / 2));
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return r * c;
}

double _degToRad(double d) => d * (pi / 180.0);