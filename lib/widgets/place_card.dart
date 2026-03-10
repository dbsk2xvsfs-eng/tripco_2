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

    final fixed =
    (u.startsWith('http://') || u.startsWith('https://')) ? u : 'https://$u';

    final uri = Uri.tryParse(fixed);
    if (uri == null) return null;
    if (uri.host.isEmpty) return null;

    return uri;
  }

  Future<void> _launchExternal(
      BuildContext context,
      String rawUrl,
      String failText,
      ) async {
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
    final km =
        _haversineMeters(originLat, originLng, place.lat, place.lng) / 1000.0;
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
                        style:
                        const TextStyle(fontSize: 12, color: Colors.grey),
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

  Widget _tinyIconButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String tooltip,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      splashRadius: 18,
    );
  }

  Widget _buildPhotoStack(BuildContext context) {
    if (place.photos.isEmpty) return const SizedBox.shrink();

    final visible = place.photos.take(3).toList();
    const thumbSize = 60.0;
    const overlap = 24.0;

    final stackWidth = thumbSize + ((visible.length - 1) * overlap);
    const stackHeight = 68.0;

    return GestureDetector(
      onTap: () => _openPhotoGallery(context),
      child: SizedBox(
        width: stackWidth,
        height: stackHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (int i = 0; i < visible.length; i++)
              Positioned(
                left: i * overlap,
                top: i * 1,
                child: Container(
                  width: thumbSize,
                  height: thumbSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 3,
                        offset: Offset(0, -3),
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
    final hasGoogleMaps = (place.googleMapsUri ?? "").trim().isNotEmpty;

    return Card(
      color: (accentColor ?? Colors.white).withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // title + photos
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      place.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        decoration:
                        place.done ? TextDecoration.lineThrough : null,
                        color: place.done ? Colors.grey : null,
                      ),
                    ),
                  ),
                ),
                if (place.photos.isNotEmpty) _buildPhotoStack(context),
              ],
            ),

            const SizedBox(height: 6),

            // type
            Text(
              place.type,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: accentColor ?? Colors.black87),
            ),

            const SizedBox(height: 10),

            // info row - responsive
            Row(
              children: [

                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [

                      Text(
                        "${s.entry}:",
                        style: TextStyle(color: Colors.grey.shade800),
                      ),

                      if (hasWebsite)
                        _tinyIconButton(
                          onPressed: () => _openWebsite(context),
                          icon: Icons.public,
                          tooltip: "Website",
                        ),

                      Text(
                        _kmText(),
                        style: TextStyle(color: Colors.grey.shade800),
                      ),

                      if (place.openNow != null)
                        Text(
                          place.openNow! ? s.open : s.closed,
                          style: TextStyle(
                            color: place.openNow! ? Colors.green : Colors.grey,
                          ),
                        ),

                      if (hasGoogleMaps)
                        _tinyIconButton(
                          onPressed: () => _openGoogleMapsPlace(context),
                          icon: Icons.public,
                          tooltip: "Google Maps",
                        ),
                    ],
                  ),
                ),

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

            const SizedBox(height: 10),

            // bottom actions: ALL only
            if (!categoryMode) ...[
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: place.done
                        ? null
                        : () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(18),
                          ),
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

                  if (onToggleDone != null)
                    OutlinedButton(
                      onPressed: onToggleDone,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        minimumSize: const Size(0, 40),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text("Mark done"),
                    ),

                  if (onReplace != null)
                    IconButton(
                      onPressed: onReplace,
                      icon: const Icon(Icons.shuffle),
                      tooltip: "Replace",
                      visualDensity: VisualDensity.compact,
                    ),

                  if (onRemove != null)
                    IconButton(
                      onPressed: onRemove,
                      icon: const Icon(Icons.close),
                      tooltip: "Remove",
                      visualDensity: VisualDensity.compact,
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