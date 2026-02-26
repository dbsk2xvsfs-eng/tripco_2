import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/place.dart';
import '../services/routes_service.dart';
import '../widgets/navigation_sheet.dart';

import '../services/navigation_service.dart';
import '../models/transport_option.dart';

class PlanMapScreen extends StatefulWidget {
  final String title;
  final List<Place> places;
  final double originLat;
  final double originLng;
  final RoutesService routes;

  const PlanMapScreen({
    super.key,
    required this.title,
    required this.places,
    required this.originLat,
    required this.originLng,
    required this.routes,
  });

  @override
  State<PlanMapScreen> createState() => _PlanMapScreenState();
}

class _PlanMapScreenState extends State<PlanMapScreen> {
  GoogleMapController? _map;
  Place? _selected;


  void _openRidePicker(Place place) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Choose your ride 🧭",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),

                ListTile(
                  leading: const Icon(Icons.directions_walk),
                  title: const Text("Walking"),
                  onTap: () async {
                    Navigator.pop(context);
                    await NavigationService.openNavigation(
                      destLat: place.lat,
                      destLng: place.lng,
                      type: TransportType.walk,
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.directions_transit),
                  title: const Text("Public transport"),
                  onTap: () async {
                    Navigator.pop(context);
                    await NavigationService.openNavigation(
                      destLat: place.lat,
                      destLng: place.lng,
                      type: TransportType.transit,
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.directions_car),
                  title: const Text("Car"),
                  onTap: () async {
                    Navigator.pop(context);
                    await NavigationService.openNavigation(
                      destLat: place.lat,
                      destLng: place.lng,
                      type: TransportType.car,
                    );
                  },
                ),

                const SizedBox(height: 6),
                const Text(
                  "Times are estimates (MVP).",
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  double _degToRad(double d) => d * (pi / 180.0);

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

  String _kmText(Place p) {
    final km = _haversineMeters(widget.originLat, widget.originLng, p.lat, p.lng) / 1000.0;
    return "${km.toStringAsFixed(1)} km";
  }

  Set<Marker> _buildMarkers() {
    final out = <Marker>{};

    // origin marker (volitelné)
    out.add(
      Marker(
        markerId: const MarkerId("origin"),
        position: LatLng(widget.originLat, widget.originLng),
        infoWindow: const InfoWindow(title: "Origin"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
    );

    for (final p in widget.places) {
      out.add(
        Marker(
          markerId: MarkerId(p.id.isNotEmpty ? p.id : "${p.name}_${p.lat}_${p.lng}"),
          position: LatLng(p.lat, p.lng),
          infoWindow: InfoWindow(
            title: p.name,
            snippet: _kmText(p),
          ),
          onTap: () {
            setState(() => _selected = p);
          },
        ),
      );
    }
    return out;
  }

  Future<void> _fitToMarkers() async {
    final c = _map;
    if (c == null) return;

    final pts = <LatLng>[
      LatLng(widget.originLat, widget.originLng),
      ...widget.places.map((p) => LatLng(p.lat, p.lng)),
    ];
    if (pts.isEmpty) return;

    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;

    for (final p in pts) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLng = min(minLng, p.longitude);
      maxLng = max(maxLng, p.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    await c.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));
  }
  void _openNavigate(Place place) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => NavigationSheet(
        place: place,
        originLat: widget.originLat,
        originLng: widget.originLng,
        routes: widget.routes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = _buildMarkers();

    return Scaffold(
      appBar: AppBar(
        title: Text("Map • ${widget.title}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.center_focus_strong),
            tooltip: "Fit",
            onPressed: _fitToMarkers,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(widget.originLat, widget.originLng),
              zoom: 12,
            ),
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            markers: markers,
            onMapCreated: (c) async {
              _map = c;
              await _fitToMarkers();
            },
            onTap: (_) => setState(() => _selected = null),
          ),

          if (_selected != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Material(
                  elevation: 10,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selected!.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Text(_kmText(_selected!)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () => _openRidePicker(_selected!),
                          child: const Text("Navigate"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}