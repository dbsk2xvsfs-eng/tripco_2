import 'package:flutter/material.dart';
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

  // ✅ když není null -> jsme v kategorii a zobrazíme Add to All,
  // a zároveň schováme Replace/Delete/Done.
  final VoidCallback? onAddToAll;

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
    this.onAddToAll,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    final isCatalogMode = onAddToAll != null || (onAddToAll == null && false);

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
                decoration: (!isCatalogMode && place.done) ? TextDecoration.lineThrough : null,
                color: (!isCatalogMode && place.done) ? Colors.grey : null,
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

            const SizedBox(height: 10),

            // ✅ Entry řádek už řešíš přes website ikonku (pokud existuje) -> tady nic nezobrazujeme

            Row(
              children: [
                if (!isCatalogMode)
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
                if (!isCatalogMode) const Spacer(),

                if (isCatalogMode)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onAddToAll,
                      child: Text(onAddToAll == null ? "Added" : "Add to All"),
                    ),
                  ),

                if (!isCatalogMode)
                  IconButton(
                    onPressed: onToggleFavorite,
                    icon: Icon(isFavorite ? Icons.star : Icons.star_border),
                    tooltip: isFavorite ? s.saved : s.unsaved,
                  ),
              ],
            ),

            const SizedBox(height: 10),

            if (!isCatalogMode)
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