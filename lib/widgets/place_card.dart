import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/strings.dart';
import '../models/place.dart';
import '../services/routes_service.dart';
import 'navigation_sheet.dart';



class PlaceCard extends StatelessWidget {
  final Place place;

  final Color? accentColor;

  final double originLat;
  final double originLng;
  final RoutesService routes;

  /// ALL actions
  final VoidCallback? onRemove;
  final VoidCallback? onReplace;
  final VoidCallback? onToggleDone;

  /// Category action
  final VoidCallback? onAddToAll;

  /// Favorite (nezobrazuje se – necháváme pro kompatibilitu)
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  /// If true => Category mode (Add to All v řádku s Entry)
  /// If false => All mode (navigate/replace/remove/mark done)
  final bool categoryMode;

  const PlaceCard({
    super.key,
    required this.place,
    required this.originLat,
    required this.originLng,
    required this.routes,
    required this.isFavorite,
    required this.onToggleFavorite,
    this.onRemove,
    this.onReplace,
    this.onToggleDone,
    this.onAddToAll,
    this.categoryMode = false,

    this.accentColor,

  });

  Future<void> _openWebsite(BuildContext context) async {
    final url = (place.websiteUrl ?? "").trim();
    if (url.isEmpty) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open website")),
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

  String _kmText() {
    final km = _haversineMeters(originLat, originLng, place.lat, place.lng) / 1000.0;
    return "${km.toStringAsFixed(1)} km";
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    final website = (place.websiteUrl ?? "").trim();
    final hasWebsite = website.isNotEmpty;

    return Card(
      color: (accentColor ?? Colors.white).withOpacity(0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // title
            Text(
              place.name,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                decoration: place.done ? TextDecoration.lineThrough : null,
                color: place.done ? Colors.grey : null,
              ),
            ),
            const SizedBox(height: 6),

            // type / open / rating
            Row(
              children: [
                Expanded(
                  child: Text(
                    place.type,
                    style: TextStyle(color: accentColor ?? Colors.black87),
                  ),
                ),
                if (place.openNow != null) ...[
                  const SizedBox(width: 10),
                  Text(place.openNow! ? s.open : s.closed),
                ],
                if (place.rating != null) ...[
                  const SizedBox(width: 10),
                  Text("⭐ ${place.rating!.toStringAsFixed(1)}"),
                ],
              ],
            ),

            const SizedBox(height: 8),

// Entry + WWW + km + (Category) Add / (All) Mark done
            Row(
              children: [
                Text(
                  "${s.entry}:",
                  style: TextStyle(color: Colors.grey.shade800),
                ),
                const SizedBox(width: 8),

                if (hasWebsite)
                  IconButton(
                    onPressed: () => _openWebsite(context),
                    icon: const Icon(Icons.public),
                    tooltip: "Website",
                    visualDensity: VisualDensity.compact,
                  )
                else
                  const SizedBox(width: 40), // drží stejné odsazení

                const SizedBox(width: 6),

                // ✅ Vzdálenost se zobrazí VŽDY
                Text(
                  _kmText(),
                  style: TextStyle(color: Colors.grey.shade800),
                ),

                const Spacer(),

                // ✅ ALL: Mark done
                if (!categoryMode)
                  GestureDetector(
                    onTap: () => onToggleDone?.call(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Text(place.done ? s.done : s.markDone),
                    ),
                  ),

                // ✅ CATEGORY: malé Add to All
                if (categoryMode && onAddToAll != null)
                  TextButton(
                    onPressed: onAddToAll,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text("Add to All"),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // bottom actions: ALL only
            if (!categoryMode) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: place.done
                          ? null
                          : () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                          ),
                          builder: (_) => NavigationSheet(
                            place: place,
                            originLat: originLat,
                            originLng: originLng,
                            routes: routes,
                          ),
                        );
                      },
                      child: Text(s.navigate),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: onReplace, // null => disabled
                    icon: const Icon(Icons.shuffle),
                    tooltip: "Replace",
                  ),
                  IconButton(
                    onPressed: onRemove, // null => disabled
                    icon: const Icon(Icons.close),
                    tooltip: "Remove",
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}