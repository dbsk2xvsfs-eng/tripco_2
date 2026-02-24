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

  String _extractCategory(String title) {
    // očekává např. "Replace (Culture)"
    final start = title.indexOf('(');
    final end = title.indexOf(')');
    if (start != -1 && end != -1 && end > start + 1) {
      return title.substring(start + 1, end).trim();
    }
    // fallback: vezmi celý text
    return title.trim();
  }

  Color _colorForCategory(String cat) {
    switch (cat) {
      case "Culture":
        return const Color(0xFFB86B2B); // jemná hnědá
      case "Museum":
        return const Color(0xFF2F6FD6); // modrá
      case "Nature":
        return const Color(0xFF2E7D32); // zelená
      case "Attraction":
        return const Color(0xFF7B3FE4); // fialová
      case "Castles":
        return const Color(0xFFB71C1C); // tm. červená
      case "Restaurant":
        return const Color(0xFF1E88E5); // modrá
      case "Cafe":
        return const Color(0xFF6D4C41); // kávová
      default:
        return const Color(0xFF607D8B); // šedo-modrá
    }
  }

  String _emojiForCategory(String cat) {
    switch (cat) {
      case "Culture":
        return "⛪️";
      case "Museum":
        return "🏛️";
      case "Nature":
        return "🌳";
      case "Attraction":
        return "🎡";
      case "Castles":
        return "🏰";
      case "Restaurant":
        return "🍽️";
      case "Cafe":
        return "☕";
      default:
        return "✨";
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...candidates];
    sorted.sort((a, b) {
      final da = _haversineMeters(originLat, originLng, a.lat, a.lng);
      final db = _haversineMeters(originLat, originLng, b.lat, b.lng);
      return da.compareTo(db);
    });

    final cat = _extractCategory(title);
    final accent = _colorForCategory(cat);

    return SafeArea(
      // ✅ posun dolů (~2 cm)
      child: Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ✅ barevné záhlaví dle kategorie
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    Text(
                      _emojiForCategory(cat),
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: sorted.length,
                  itemBuilder: (context, i) {
                    final p = sorted[i];
                    final distKm =
                        _haversineMeters(originLat, originLng, p.lat, p.lng) / 1000.0;

                    final disabled = p.id == currentId || allIds.contains(p.id);

                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
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
      ),
    );
  }
}

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLon = _degToRad(lon2 - lon1);
  final a = (sin(dLat / 2) * sin(dLat / 2)) +
      cos(_degToRad(lat1)) *
          cos(_degToRad(lat2)) *
          (sin(dLon / 2) * sin(dLon / 2));
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return r * c;
}

double _degToRad(double d) => d * (pi / 180.0);