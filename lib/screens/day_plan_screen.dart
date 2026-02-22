import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';

import '../i18n/strings.dart';
import '../models/place.dart';
import '../models/user_profile.dart';

import '../services/analytics_service.dart';
import '../services/favorites_storage.dart';
import '../services/location_service.dart';
import '../services/places_service.dart';
import '../services/plan_storage.dart';
import '../services/recommendation_service.dart';
import '../services/routes_service.dart';

import '../widgets/place_card.dart';
import '../widgets/replace_sheet.dart';

class DayPlanScreen extends StatefulWidget {
  const DayPlanScreen({super.key});

  @override
  State<DayPlanScreen> createState() => _DayPlanScreenState();
}

class _DayPlanScreenState extends State<DayPlanScreen> {
  Position? _pos;
  bool _loading = true;
  String? _error;

  late final RecommendationService _rec;
  late final RoutesService _routes;
  late final PlacesService _places;

  List<Place> _plan = [];

  static const UserProfile _fixedProfile = UserProfile.solo;
  static const _apiKey = String.fromEnvironment('GOOGLE_API_KEY');

  String _selectedCategory = "All";

  @override
  void initState() {
    super.initState();

    AnalyticsService.initIfAvailable();

    if (_apiKey.isEmpty) {
      _error = "Missing GOOGLE_API_KEY. Run with --dart-define=GOOGLE_API_KEY=...";
      _loading = false;
      return;
    }

    _places = PlacesService(apiKey: _apiKey);
    _rec = RecommendationService(places: _places);
    _routes = RoutesService(apiKey: _apiKey);

    _init();
  }

  Future<void> _init() async {
    try {
      final p = await LocationService.getCurrentLocation();
      if (p == null) {
        setState(() {
          _loading = false;
          _error = S.of(context).locationNeeded;
        });
        return;
      }

      final saved = PlanStorage.loadPlan();
      if (saved != null && saved.isNotEmpty) {
        setState(() {
          _pos = p;
          _plan = saved;
          _loading = false;
        });
        return;
      }

      final plan = await _rec.getTodayPlan(
        lat: p.latitude,
        lng: p.longitude,
        profile: _fixedProfile,
        maxItems: 10,
      );

      await PlanStorage.savePlan(plan);

      setState(() {
        _pos = p;
        _plan = plan;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Set<String> _excludeIds() => _plan.map((p) => p.id).toSet();

  Future<void> _refreshAll() async {
    if (_pos == null) return;
    setState(() => _loading = true);

    try {
      final plan = await _rec.getTodayPlan(
        lat: _pos!.latitude,
        lng: _pos!.longitude,
        profile: _fixedProfile,
        maxItems: 10,
      );

      await PlanStorage.savePlan(plan);

      setState(() {
        _plan = plan;
        _loading = false;
        _error = null;
        _selectedCategory = "All";
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _startFresh() async {
    await PlanStorage.clearPlan();
    await _refreshAll();
  }

  Future<void> _sharePlan() async {
    final lines = _plan.map((p) => "- ${p.name} (${p.primaryType ?? ""})").join("\n");
    final text = "My Tripco Day Plan ☀️\n\n$lines";
    await AnalyticsService.logShare(_plan.length);
    await Share.share(text);
  }

  void _removeById(String id) async {
    setState(() {
      _plan.removeWhere((p) => p.id == id);
    });
    await AnalyticsService.logRemove(id);
    await PlanStorage.savePlan(_plan);
  }

  void _toggleDoneById(String id) async {
    final idx = _plan.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final current = _plan[idx];
    setState(() {
      _plan[idx] = current.copyWith(done: !current.done);
    });
    await PlanStorage.savePlan(_plan);
  }

  Future<void> _toggleFavorite(Place place) async {
    final nowFav = await FavoritesStorage.toggleFavorite(place.id);
    await AnalyticsService.logFavorite(place.id, nowFav);
    setState(() {});
  }

  // ------------------- Categories (exact by primaryType) -------------------

  static const Map<String, Set<String>> _categoryToPrimaryTypes = {
    "Culture": {"museum", "art_gallery", "historical_landmark"},
    "Museum": {"museum"},
    "Nature": {"park", "hiking_area"},
    "Attraction": {"tourist_attraction", "amusement_park", "zoo", "aquarium"},
    "Shopping": {"shopping_mall"},
    "Food": {"restaurant", "cafe"},
    "Restaurant": {"restaurant"},
    "Cafe": {"cafe"},
    // Derived but still exact (based on primaryType)
    "Indoor": {"museum", "art_gallery", "shopping_mall", "aquarium"},
  };

  List<String> _buildCategories() {
    final present = _plan.map((p) => p.primaryType).whereType<String>().toSet();

    final cats = <String>["All"];

    // Add category if ANY of its primaryTypes is present
    for (final entry in _categoryToPrimaryTypes.entries) {
      if (entry.value.any(present.contains)) {
        cats.add(entry.key);
      }
    }

    // Stable order preference
    final preferred = [
      "All",
      "Culture",
      "Museum",
      "Nature",
      "Attraction",
      "Food",
      "Restaurant",
      "Cafe",
      "Indoor",
      "Shopping",
    ];

    final out = <String>[];
    for (final p in preferred) {
      if (cats.contains(p)) out.add(p);
    }
    for (final c in cats) {
      if (!out.contains(c)) out.add(c);
    }
    return out;
  }

  List<Place> _filteredPlan() {
    if (_selectedCategory == "All") return _plan;

    final allowed = _categoryToPrimaryTypes[_selectedCategory];
    if (allowed == null || allowed.isEmpty) return _plan;

    return _plan.where((p) => p.primaryType != null && allowed.contains(p.primaryType)).toList();
  }

  Set<String>? _allowedForCurrentCategory() {
    if (_selectedCategory == "All") return null;
    return _categoryToPrimaryTypes[_selectedCategory];
  }

  // ------------------- Replace flow (sorted by distance) -------------------

  Future<void> _openReplaceFor(Place current) async {
    if (_pos == null) return;

    final selected = await showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => ReplaceSheet(
        places: _places,
        originLat: _pos!.latitude,
        originLng: _pos!.longitude,
        excludeIds: _excludeIds(),
        allowedPrimaryTypes: _allowedForCurrentCategory(),
      ),
    );

    if (selected == null) return;

    setState(() {
      final idx = _plan.indexWhere((p) => p.id == current.id);
      if (idx != -1) _plan[idx] = selected;
    });

    await AnalyticsService.logReplace(current.id);
    await PlanStorage.savePlan(_plan);
  }

  void _reorderAll(int oldIndex, int newIndex) async {
    if (_selectedCategory != "All") return;

    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _plan.removeAt(oldIndex);
      _plan.insert(newIndex, item);
    });
    await PlanStorage.savePlan(_plan);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(s.dayPlan)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.dayPlan)),
        body: Center(child: Text(_error!)),
      );
    }

    final categories = _buildCategories();
    final filtered = _filteredPlan();

    return Scaffold(
      appBar: AppBar(
        title: Text(s.dayPlan),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: s.share,
            onPressed: _sharePlan,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: s.refresh,
            onPressed: _refreshAll,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: s.startFresh,
            onPressed: _startFresh,
          ),
        ],
      ),
      body: Column(
        children: [
          _SummaryBar(count: filtered.length),

          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final c = categories[i];
                final selected = c == _selectedCategory;
                return ChoiceChip(
                  label: Text(c),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _selectedCategory = c);
                  },
                );
              },
            ),
          ),

          const SizedBox(height: 6),

          Expanded(
            child: _selectedCategory == "All"
                ? ReorderableListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: filtered.length,
              onReorder: _reorderAll,
              itemBuilder: (context, i) {
                final place = filtered[i];
                final isFav = FavoritesStorage.isFavorite(place.id);

                return PlaceCard(
                  key: ValueKey(place.id),
                  place: place,
                  originLat: _pos!.latitude,
                  originLng: _pos!.longitude,
                  routes: _routes,
                  onRemove: () => _removeById(place.id),
                  onReplace: () => _openReplaceFor(place),
                  onToggleDone: () => _toggleDoneById(place.id),
                  isFavorite: isFav,
                  onToggleFavorite: () => _toggleFavorite(place),
                );
              },
            )
                : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final place = filtered[i];
                final isFav = FavoritesStorage.isFavorite(place.id);

                return PlaceCard(
                  key: ValueKey(place.id),
                  place: place,
                  originLat: _pos!.latitude,
                  originLng: _pos!.longitude,
                  routes: _routes,
                  onRemove: () => _removeById(place.id),
                  onReplace: () => _openReplaceFor(place),
                  onToggleDone: () => _toggleDoneById(place.id),
                  isFavorite: isFav,
                  onToggleFavorite: () => _toggleFavorite(place),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final int count;
  const _SummaryBar({required this.count});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "${s.todaySpots}: $count spots ✨",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text("Tripco"),
        ],
      ),
    );
  }
}