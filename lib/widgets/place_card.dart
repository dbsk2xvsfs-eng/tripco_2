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

  /// ALL actions
  final VoidCallback? onRemove;
  final VoidCallback? onReplace;
  final VoidCallback? onToggleDone;

  /// Category action
  final VoidCallback? onAddToAll;

  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  /// If true => Category mode (only "Add to All")
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
            // title
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

            // type / open / rating
            Row(
              children: [
                Expanded(child: Text(place.type)),
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

            // ✅ Entry row (only if website exists)
            if (hasWebsite) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    "${s.entry}:",
                    style: TextStyle(color: Colors.grey.shade800),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _openWebsite(context),
                    icon: const Icon(Icons.public),
                    tooltip: "Website",
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],

            const SizedBox(height: 10),

            // top row: Mark done (ALL) + Favorite (both)
            Row(
              children: [
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
                const Spacer(),
                IconButton(
                  onPressed: onToggleFavorite,
                  icon: Icon(isFavorite ? Icons.star : Icons.star_border),
                  tooltip: isFavorite ? s.saved : s.unsaved,
                ),
              ],
            ),

            const SizedBox(height: 10),

            // bottom actions: ALL vs CATEGORY
            if (categoryMode) ...[
              if (onAddToAll != null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onAddToAll,
                    child: const Text("Add to All"),
                  ),
                ),
            ] else ...[
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