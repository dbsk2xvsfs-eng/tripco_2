import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/strings.dart';
import '../models/place.dart';
import '../services/routes_service.dart';
import 'navigation_sheet.dart';

class PlaceCard extends StatelessWidget {
  final Place place;

  final double originLat;
  final double originLng;
  final RoutesService routes;

  final VoidCallback onRemove;
  final VoidCallback onReplace;
  final VoidCallback onToggleDone;

  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  const PlaceCard({
    super.key,
    required this.place,
    required this.originLat,
    required this.originLng,
    required this.routes,
    required this.onRemove,
    required this.onReplace,
    required this.onToggleDone,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  Future<void> _openWebsite(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open website")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    final website = (place.websiteUrl ?? "").trim();
    final hasWebsite = website.isNotEmpty;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              place.name,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                decoration: place.done ? TextDecoration.lineThrough : null,
                color: place.done ? Colors.grey : null,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(place.type),
                const SizedBox(width: 10),
                if (place.openNow != null) Text(place.openNow! ? s.open : s.closed),
                const SizedBox(width: 10),
                if (place.rating != null) Text("⭐ ${place.rating!.toStringAsFixed(1)}"),
              ],
            ),

            if (hasWebsite) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.public, size: 16),
                  const SizedBox(width: 6),
                  Text("${s.entry}: "),
                  const SizedBox(width: 6),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    tooltip: "Open website",
                    onPressed: () => _openWebsite(context, website),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 10),

            Row(
              children: [
                GestureDetector(
                  onTap: onToggleDone,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Text(place.done ? s.done : s.markDone),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onToggleFavorite,
                  icon: Icon(isFavorite ? Icons.star : Icons.star_border),
                  tooltip: isFavorite ? s.saved : s.unsaved,
                ),
              ],
            ),

            const SizedBox(height: 10),

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
                  onPressed: onReplace,
                  icon: const Icon(Icons.shuffle),
                  tooltip: "Replace",
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                  tooltip: "Remove",
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}