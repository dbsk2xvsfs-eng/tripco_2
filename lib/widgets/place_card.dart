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

  final String apiKey;


  const PlaceCard({
    super.key,
    required this.place,
    required this.originLat,
    required this.originLng,
    required this.routes,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.apiKey,
    this.onRemove,
    this.onReplace,
    this.onToggleDone,
    this.onAddToAll,
    this.categoryMode = false,
    this.accentColor,
  });

  Uri? _toSafeUri(String raw) {
    final u = raw.trim();
    if (u.isEmpty) return null;

    // doplníme schéma, pokud chybí (muzeumdobris.cz -> https://muzeumdobris.cz)
    final fixed = (u.startsWith('http://') || u.startsWith('https://')) ? u : 'https://$u';

    final uri = Uri.tryParse(fixed);
    if (uri == null) return null;

    // minimální validace
    if (uri.host.isEmpty) return null;

    return uri;
  }

  Future<void> _launchExternal(BuildContext context, String rawUrl, String failText) async {
    final uri = _toSafeUri(rawUrl);
    if (uri == null) return;

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failText)),
      );
    }
  }

  Future<void> _openWebsite(BuildContext context) async {
    final url = (place.websiteUrl ?? "").trim();
    if (url.isEmpty) return;

    await _launchExternal(context, url, "Could not open website");
  }

  Future<void> _openGoogleMapsPlace(BuildContext context) async {
    final url = (place.googleMapsUri ?? "").trim();
    if (url.isEmpty) return;

    await _launchExternal(context, url, "Could not open Google Maps");
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


  String _photoUrl(String photoName, {int maxWidth = 300}) {
    return "https://places.googleapis.com/v1/$photoName/media?maxWidthPx=$maxWidth&key=$apiKey";
  }

  void _openPhotoGallery(BuildContext context) {
    if (place.photos.isEmpty) return;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 420,
          child: PageView.builder(
            itemCount: place.photos.length,
            itemBuilder: (context, index) {
              final photo = place.photos[index];
              return Column(
                children: [
                  Expanded(
                    child: InteractiveViewer(
                      child: Image.network(
                        _photoUrl(photo.name, maxWidth: 1200),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                        const Center(child: Icon(Icons.broken_image, size: 48)),
                      ),
                    ),
                  ),
                  if ((photo.authorAttribution ?? "").trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        photo.authorAttribution!,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }


  Widget _buildPhotoStack(BuildContext context) {
    if (place.photos.isEmpty) return const SizedBox.shrink();

    final visible = place.photos.take(3).toList();

    return GestureDetector(
      onTap: () => _openPhotoGallery(context),
      child: SizedBox(
        width: 74,
        height: 54,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (int i = visible.length - 1; i >= 0; i--)
              Positioned(
                top: i * 4,
                right: i * 40,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.network(
                    _photoUrl(visible[i].name, maxWidth: 200),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.image, size: 20),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    final website = (place.websiteUrl ?? "").trim();
    final hasWebsite = website.isNotEmpty;

    return Card(
      color: (accentColor ?? Colors.white).withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // title
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    place.name,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      decoration: place.done ? TextDecoration.lineThrough : null,
                      color: place.done ? Colors.grey : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _buildPhotoStack(context),
              ],
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

                // Website
                if (hasWebsite)
                  IconButton(
                    onPressed: () => _openWebsite(context),
                    icon: const Icon(Icons.public),
                    tooltip: "Website",
                    visualDensity: VisualDensity.compact,
                  )
                else
                  const SizedBox(width: 40),

                const SizedBox(width: 6),

                // Vzdálenost
                Text(
                  _kmText(),
                  style: TextStyle(color: Colors.grey.shade800),
                ),

                const Spacer(),

                // 🔽 NOVĚ PŘESUNUTÉ Open
                if (place.openNow != null) ...[
                  Text(
                    place.openNow! ? s.open : s.closed,
                    style: TextStyle(
                      color: place.openNow! ? Colors.green : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],

                // 🔽 NOVĚ PŘESUNUTÉ Rating
                if (place.rating != null) ...[
                  Text("⭐ ${place.rating!.toStringAsFixed(1)}"),
                  const SizedBox(width: 8),
                ],

                // 🔽 NOVĚ PŘESUNUTÉ Google Maps
                if ((place.googleMapsUri ?? "").trim().isNotEmpty)
                  IconButton(
                    onPressed: () => _openGoogleMapsPlace(context),
                    icon: const Icon(Icons.public),
                    tooltip: "Google Maps",
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),

                // Add to Yours (zůstává)
                if (categoryMode && onAddToAll != null)
                  TextButton(
                    onPressed: onAddToAll,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text("Add"),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // bottom actions: ALL only
            if (!categoryMode) ...[
              Row(
                children: [
                  // Navigate (kratší, ne full width)
                  ElevatedButton(
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
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(s.navigate),
                  ),

                  const SizedBox(width: 10),

                  // Mark done (hned napravo od Navigate, před Replace)
                  if (onToggleDone != null)
                    OutlinedButton(
                      onPressed: onToggleDone,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        minimumSize: const Size(0, 40),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text("Mark done"), // pokud nemáš v lokalizaci, dej "Mark done"
                    ),

                  const Spacer(),

                  if (onReplace != null)
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
              )
            ],
          ],
        ),
      ),
    );
  }
}