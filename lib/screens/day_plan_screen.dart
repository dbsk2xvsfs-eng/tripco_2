// ignore: unused_import
import 'dart:math';

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

  // ✅ All = výběr dne (z toho se maže a dělá replace)
  List<Place> _allPlan = [];

  // ✅ Kategorie = katalog (15 položek), jen Add to All
  final Map<String, List<Place>> _categoryPools = {};

  String _selectedTab = "All";

  static const UserProfile _fixedProfile = UserProfile.solo;
  static const _apiKey = String.fromEnvironment('GOOGLE_API_KEY');

  // ------------------- Category config -------------------

  // “Hlavní” kategorie, ze kterých se skládá All: 3 z každé
  static const List<String> _mainCategoriesForAll = [
    "Culture",
    "Nature",
    "Attraction",
    "Food",
    "Castles",
  ];

  // Každá kategorie = přesné Google primaryType (includedTypes)
  // radius podle požadavku
  static const Map<String, _CategoryConfig> _categoryConfig = {
    "Culture": _CategoryConfig(
      includedTypes: {"museum", "art_gallery", "historical_landmark"},
      radiusMeters: 50000,
    ),
    "Museum": _CategoryConfig(
      includedTypes: {"museum"},
      radiusMeters: 50000,
    ),
    "Nature": _CategoryConfig(
      includedTypes: {"park", "hiking_area"},
      radiusMeters: 40000,
    ),
    "Attraction": _CategoryConfig(
      includedTypes: {"tourist_attraction", "amusement_park", "zoo", "aquarium"},
      radiusMeters: 50000,
    ),
    "Shopping": _CategoryConfig(
      includedTypes: {"shopping_mall"},
      radiusMeters: 20000,
    ),
    "Food": _CategoryConfig(
      includedTypes: {"restaurant", "cafe"},
      radiusMeters: 15000, // ✅ dle zadání
    ),
    "Restaurant": _CategoryConfig(
      includedTypes: {"restaurant"},
      radiusMeters: 15000,
    ),
    "Cafe": _CategoryConfig(
      includedTypes: {"cafe"},
      radiusMeters: 15000,
    ),
    "Indoor": _CategoryConfig(
      includedTypes: {"museum", "art_gallery", "shopping_mall", "aquarium"},
      radiusMeters: 30000,
    ),
    "Castles": _CategoryConfig(
      includedTypes: {"castle", "historical_landmark"},
      radiusMeters: 100000, // ✅ dle zadání (100 km)
    ),
  };

  // Kolik položek v katalogu a kolik do All
  static const int _poolSize = 15;
  static const int _takeFromEachToAll = 3;

  // ------------------- lifecycle -------------------

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

      _pos = p;

      // ✅ load saved All plan only
      final savedAll = PlanStorage.loadPlan();
      if (savedAll != null && savedAll.isNotEmpty) {
        _allPlan = savedAll;
      }

      // ✅ always (re)load category pools (katalogy)
      await _loadCategoryPools();

      // ✅ if no saved All, build initial All = 3 z každé hlavní kategorie
      if (_allPlan.isEmpty) {
        _allPlan = _buildInitialAllFromPools();
        await PlanStorage.savePlan(_allPlan);
      }

      setState(() {
        _loading = false;
        _error = null;
        _selectedTab = "All";
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ------------------- Pools (katalog) -------------------

  Future<void> _loadCategoryPools() async {
    if (_pos == null) return;

    final originLat = _pos!.latitude;
    final originLng = _pos!.longitude;

    // načti postupně (jednodušší debug); klidně můžeš změnit na Future.wait
    for (final entry in _categoryConfig.entries) {
      final key = entry.key;
      final cfg = entry.value;

      final raw = await _places.nearby(
        lat: originLat,
        lng: originLng,
        radiusMeters: cfg.radiusMeters,
        // Google Places: maxResultCount musí být 1..20
        maxResults: 20,
        includedTypes: cfg.includedTypes.toList(),
      );

      // map + filtr
      int minutesSeed = 6;
      final mapped = raw.map((p) {
        minutesSeed += 1;
        return _rec.mapGooglePlace(p, distanceMinutesSeed: minutesSeed);
      }).where((x) => x.id.isNotEmpty).toList();

      // řazení dle km (přímá vzdálenost)
      mapped.sort((a, b) {
        final da = _haversineMeters(originLat, originLng, a.lat, a.lng);
        final db = _haversineMeters(originLat, originLng, b.lat, b.lng);
        return da.compareTo(db);
      });

      // unikáty dle id + take 15
      final uniq = <String>{};
      final out = <Place>[];
      for (final pl in mapped) {
        if (uniq.add(pl.id)) out.add(pl);
        if (out.length >= _poolSize) break;
      }

      _categoryPools[key] = out;
    }
  }

  List<Place> _buildInitialAllFromPools() {
    final used = <String>{};
    final out = <Place>[];

    for (final cat in _mainCategoriesForAll) {
      final pool = _categoryPools[cat] ?? const <Place>[];
      int added = 0;
      for (final p in pool) {
        if (used.contains(p.id)) continue;
        out.add(p);
        used.add(p.id);
        added++;
        if (added >= _takeFromEachToAll) break;
      }
    }

    return out;
  }

  // ------------------- Tabs -------------------

  List<String> _tabs() {
    final out = <String>["All"];

    // zobraz jen ty kategorie, které mají něco v poolu
    final preferred = [
      "Culture",
      "Museum",
      "Nature",
      "Attraction",
      "Castles",
      "Food",
      "Restaurant",
      "Cafe",
      "Indoor",
      "Shopping",
    ];

    for (final k in preferred) {
      final pool = _categoryPools[k];
      if (pool != null && pool.isNotEmpty) out.add(k);
    }

    return out;
  }

  List<Place> _currentList() {
    if (_selectedTab == "All") return _allPlan;
    return _categoryPools[_selectedTab] ?? const <Place>[];
  }

  // ------------------- Actions: All -------------------

  Set<String> _allIds() => _allPlan.map((p) => p.id).toSet();

  Future<void> _removeFromAllById(String id) async {
    setState(() {
      _allPlan.removeWhere((p) => p.id == id);
    });
    await AnalyticsService.logRemove(id);
    await PlanStorage.savePlan(_allPlan);
  }

  Future<void> _toggleDoneInAllById(String id) async {
    final idx = _allPlan.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final current = _allPlan[idx];
    setState(() {
      _allPlan[idx] = current.copyWith(done: !current.done);
    });
    await PlanStorage.savePlan(_allPlan);
  }

  void _reorderAll(int oldIndex, int newIndex) async {
    if (_selectedTab != "All") return;

    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _allPlan.removeAt(oldIndex);
      _allPlan.insert(newIndex, item);
    });
    await PlanStorage.savePlan(_allPlan);
  }

  // ✅ Replace: otevře seznam z té samé kategorie (dle primaryType config), řazený dle km
  Future<void> _openReplaceForAllItem(Place current) async {
    if (_pos == null) return;

    final cat = _categoryForPlace(current);
    final candidates = (_categoryPools[cat] ?? const <Place>[])
        .where((p) => p.id != current.id)
        .toList();

    final selected = await showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => ReplaceSheet(
        title: "Replace ($cat)",
        originLat: _pos!.latitude,
        originLng: _pos!.longitude,
        currentId: current.id,
        allIds: _allIds(),
        candidates: candidates,
      ),
    );

    if (selected == null) return;

    setState(() {
      final idx = _allPlan.indexWhere((p) => p.id == current.id);
      if (idx != -1) _allPlan[idx] = selected;
    });

    await AnalyticsService.logReplace(current.id);
    await PlanStorage.savePlan(_allPlan);
  }

  String _categoryForPlace(Place p) {
    final pt = (p.primaryType ?? "").trim();
    if (pt.isEmpty) return "Attraction";

    // projdi config a vrať první match
    for (final entry in _categoryConfig.entries) {
      final cat = entry.key;
      final cfg = entry.value;

      // “subkategorie” nechceme jako hlavní zdroj pro replace v All
      // Replace má jít do logické hlavní kategorie
      if (!_mainCategoriesForAll.contains(cat) && cat != "Castles") continue;

      if (cfg.includedTypes.contains(pt)) return cat;
    }

    // fallback: food vs ostatní
    if (_categoryConfig["Food"]!.includedTypes.contains(pt)) return "Food";
    return "Attraction";
  }

  // ------------------- Actions: Category pools -------------------

  Future<void> _addToAll(Place p) async {
    if (_allPlan.any((x) => x.id == p.id)) return;

    setState(() => _allPlan.add(p));
    await PlanStorage.savePlan(_allPlan);
  }

  Future<void> _toggleFavorite(Place place) async {
    final nowFav = await FavoritesStorage.toggleFavorite(place.id);
    await AnalyticsService.logFavorite(place.id, nowFav);
    setState(() {});
  }

  // ------------------- Share / refresh -------------------

  Future<void> _shareAll() async {
    final lines = _allPlan.map((p) => "- ${p.name} (${p.primaryType ?? ""})").join("\n");
    final text = "My Tripco Day Plan ☀️\n\n$lines";
    await AnalyticsService.logShare(_allPlan.length);
    await Share.share(text);
  }

  Future<void> _refreshEverything() async {
    if (_pos == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _selectedTab = "All";
    });

    try {
      // znovu načti katalogy
      await _loadCategoryPools();

      // reset All = 3 z každé
      _allPlan = _buildInitialAllFromPools();
      await PlanStorage.savePlan(_allPlan);

      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _startFresh() async {
    await PlanStorage.clearPlan();
    await _refreshEverything();
  }

  // ------------------- UI -------------------

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

    final tabs = _tabs();
    final list = _currentList();

    return Scaffold(
      appBar: AppBar(
        title: Text(s.dayPlan),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: s.share,
            onPressed: _shareAll,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: s.refresh,
            onPressed: _refreshEverything,
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
          // ✅ vždy počítat All
          _SummaryBar(count: _allPlan.length),

          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final t = tabs[i];
                final selected = t == _selectedTab;
                return ChoiceChip(
                  label: Text(t),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedTab = t),
                );
              },
            ),
          ),

          const SizedBox(height: 6),

          Expanded(
            child: _selectedTab == "All"
                ? ReorderableListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              onReorder: _reorderAll,
              itemBuilder: (context, i) {
                final place = list[i];
                final isFav = FavoritesStorage.isFavorite(place.id);

                return PlaceCard(
                  key: ValueKey(place.id),
                  place: place,
                  originLat: _pos!.latitude,
                  originLng: _pos!.longitude,
                  routes: _routes,
                  // ✅ All má delete/replace
                  onRemove: () => _removeFromAllById(place.id),
                  onReplace: () => _openReplaceForAllItem(place),
                  onToggleDone: () => _toggleDoneInAllById(place.id),
                  isFavorite: isFav,
                  onToggleFavorite: () => _toggleFavorite(place),
                  // ✅ v All není add
                  onAddToAll: null,
                );
              },
            )
                : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final place = list[i];
                final isFav = FavoritesStorage.isFavorite(place.id);

                final alreadyInAll = _allPlan.any((x) => x.id == place.id);

                return PlaceCard(
                  key: ValueKey(place.id),
                  place: place,
                  originLat: _pos!.latitude,
                  originLng: _pos!.longitude,
                  routes: _routes,
                  // ✅ v kategorii NEJSOU delete/replace, jen add
                  onRemove: () {}, // nebude se zobrazovat (viz PlaceCard úprava)
                  onReplace: () {},
                  onToggleDone: () {}, // done dává smysl jen v All
                  isFavorite: isFav,
                  onToggleFavorite: () => _toggleFavorite(place),
                  onAddToAll: alreadyInAll ? null : () => _addToAll(place),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------- Summary bar -------------------

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

// ------------------- Helpers -------------------

class _CategoryConfig {
  final Set<String> includedTypes;
  final int radiusMeters;
  const _CategoryConfig({required this.includedTypes, required this.radiusMeters});
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

