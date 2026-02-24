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
import '../services/place_mapper.dart';

import '../widgets/place_card.dart';
import '../widgets/replace_sheet.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:geocoding/geocoding.dart';


class DayPlanScreen extends StatefulWidget {
  const DayPlanScreen({super.key});

  @override
  State<DayPlanScreen> createState() => _DayPlanScreenState();
}

class _DayPlanScreenState extends State<DayPlanScreen> with WidgetsBindingObserver {
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


  String _cityLabel = "GPS…";

  Future<void> _updateCityLabel() async {
    if (_pos == null) return;

    final lat = _pos!.latitude;
    final lng = _pos!.longitude;

    final uri = Uri.parse(
      "https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$_apiKey&language=cs",
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) return;

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final results = (data["results"] as List?) ?? [];

    String? city;

    for (final r in results) {
      final comps = (r["address_components"] as List?) ?? [];
      for (final c in comps) {
        final types = (c["types"] as List?)?.cast<String>() ?? const <String>[];
        if (types.contains("locality")) {
          city = c["long_name"] as String?;
          break;
        }
        if (city == null && types.contains("administrative_area_level_2")) {
          city = c["long_name"] as String?;
        }
      }
      if (city != null) break;
    }

    if (!mounted) return;
    setState(() {
      _cityLabel = (city ?? "GPS");
    });
  }

  void _sortAllByDistance() {
    if (_pos == null) return;
    final originLat = _pos!.latitude;
    final originLng = _pos!.longitude;

    _allPlan.sort((a, b) {
      final da = _haversineMeters(originLat, originLng, a.lat, a.lng);
      final db = _haversineMeters(originLat, originLng, b.lat, b.lng);
      return da.compareTo(db);
    });
  }

  String _selectedTab = "All";

  bool _hasUnsavedChanges = false;

  Future<void> _saveCurrentPlanToSaved() async {
    if (_pos == null) return;

    final city = await _resolveCityName(); // už máš (nebo měj) funkci pro název města
    await PlanStorage.upsertSavedPlan(
      city: city,
      lat: _pos!.latitude,
      lng: _pos!.longitude,
      plan: List<Place>.from(_allPlan),
    );

    if (!mounted) return;
    setState(() => _hasUnsavedChanges = false);
  }


  Future<void> _clearAllWithConfirm() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Are you sure?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("No"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Yes"),
          ),
        ],
      ),
    );

    if (res != true) return;

    setState(() {
      _allPlan.clear();
      _hasUnsavedChanges = false;
    });

    await PlanStorage.savePlan(_allPlan);
  }


  static const UserProfile _fixedProfile = UserProfile.solo;
  static const _apiKey = String.fromEnvironment('GOOGLE_API_KEY');

  // ------------------- Category config -------------------

  // “Hlavní” kategorie, ze kterých se skládá All
  static const List<String> _mainCategoriesForAll = [
    "Culture",
    "Castles",
    "Nature",
    "Attraction",
    "Restaurant",
    "Cafe",
    "Museum",
  ];

  // Každá kategorie = přesné Google primaryType (includedTypes)
  static const Map<String, _CategoryConfig> _categoryConfig = {
    "Museum": _CategoryConfig(
      includedTypes: {"museum"},
      radiusMeters: 50000,
    ),
    "Culture": _CategoryConfig(
      includedTypes: {
        "art_gallery",
        "historical_landmark",
        "church",
        "monument",
        "bridge",
        "library",
      },
      radiusMeters: 50000,
    ),
    "Nature": _CategoryConfig(
      includedTypes: {"park", "hiking_area"},
      radiusMeters: 40000,
    ),
    "Attraction": _CategoryConfig(
      includedTypes: {
        "tourist_attraction",
        "amusement_park",
        "zoo",
        "aquarium",
      },
      radiusMeters: 50000,
    ),
    "Restaurant": _CategoryConfig(
      includedTypes: {"restaurant"},
      radiusMeters: 15000,
    ),
    "Cafe": _CategoryConfig(
      includedTypes: {"cafe", "coffee_shop", "tea_house", "bakery"},
      radiusMeters: 15000,
    ),
    "Castles": _CategoryConfig(
      includedTypes: {"castle"},
      radiusMeters: 50000,
    ),
  };

  // Kolik položek v katalogu a kolik do All
  static const int _poolSize = 15;
  static const int _takeFromEachToAll = 2;

  // ---------- Category colors + emoji ----------
  static const Map<String, Color> _catColor = {
    "Culture": Color(0xFF9C6B3D),
    "Museum": Color(0xFF4B6CB7),
    "Nature": Color(0xFF2E7D32),
    "Attraction": Color(0xFF7B1FA2),
    "Castles": Color(0xFFB71C1C),
    "Restaurant": Color(0xFF1565C0),
    "Cafe": Color(0xFF6D4C41),
  };

  static const Map<String, String> _catEmoji = {
    "Culture": "🏛️",
    "Museum": "🏛️",
    "Nature": "🌳",
    "Attraction": "🎡",
    "Castles": "🏰",
    "Restaurant": "🍽️",
    "Cafe": "☕",
  };

  Color _colorForTab(String tab) => _catColor[tab] ?? const Color(0xFF607D8B);
  String _emojiForTab(String tab) => _catEmoji[tab] ?? "✨";






  // ------------------- lifecycle -------------------

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ✅ autosave při odchodu do backgroundu / zavření
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      PlanStorage.saveCurrentPlan(_allPlan);
    }
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
      await _updateCityLabel();

      // ✅ load CURRENT (autosave) plan
      final savedAll = PlanStorage.loadCurrentPlan();
      if (savedAll != null && savedAll.isNotEmpty) {
        _allPlan = savedAll;
      }

      // ✅ always (re)load category pools (katalogy)
      await _loadCategoryPools();

      // ✅ if no saved plan, build initial All from pools and save as current
      if (_allPlan.isEmpty) {
        _allPlan = _buildInitialAllFromPools();
        await PlanStorage.saveCurrentPlan(_allPlan);
      } else {
        // vždy udržuj správné řazení po startu
        _sortAllByDistance();
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

  String _targetCategoryForPrimaryType(String? primaryType) {
    final pt = (primaryType ?? "").trim();
    if (pt.isEmpty) return "__IGNORE__";

    // ❌ shopping_mall úplně ignorujeme v celé appce
    if (pt == "shopping_mall") return "__IGNORE__";

    // ✅ UNIQUE mapping (žádné překryvy)
    if (pt == "museum") return "Museum";

    if (pt == "castle") return "Castles";

    if (pt == "cafe" || pt == "coffee_shop" || pt == "tea_house" || pt == "bakery") return "Cafe";
    if (pt == "restaurant") return "Restaurant";

    if (pt == "park" || pt == "hiking_area") return "Nature";

    if (pt == "aquarium" || pt == "zoo" || pt == "amusement_park" || pt == "tourist_attraction") {
      return "Attraction";
    }

    if (pt == "historical_landmark" ||
        pt == "art_gallery" ||
        pt == "church" ||
        pt == "place_of_worship" ||
        pt == "monument" ||
        pt == "landmark" ||
        pt == "bridge" ||
        pt == "library" ||
        pt == "point_of_interest") {
      return "Culture";
    }

    return "Culture";
  }

  // ------------------- Pools (katalog) -------------------

  Future<void> _loadCategoryPools() async {
    if (_pos == null) return;

    final originLat = _pos!.latitude;
    final originLng = _pos!.longitude;

    for (final entry in _categoryConfig.entries) {
      final key = entry.key;
      final cfg = entry.value;

      final radius = min(cfg.radiusMeters, 50000);

      final raw = await _places.nearby(
        lat: originLat,
        lng: originLng,
        radiusMeters: radius,
        maxResults: 20,
        includedTypes: cfg.includedTypes.toList(),
      );

      int minutesSeed = 6;
      final mapped = raw
          .map((p) {
        minutesSeed += 1;
        return PlaceMapper.fromGooglePlace(p, distanceMinutes: minutesSeed);
      })
          .where((x) => x.id.isNotEmpty)
          .where((x) {
        final target = _targetCategoryForPrimaryType(x.primaryType);
        if (target == "__IGNORE__") return false;
        return target == key;
      })
          .toList();

      mapped.sort((a, b) {
        final da = _haversineMeters(originLat, originLng, a.lat, a.lng);
        final db = _haversineMeters(originLat, originLng, b.lat, b.lng);
        return da.compareTo(db);
      });

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

    if (_pos != null) {
      final originLat = _pos!.latitude;
      final originLng = _pos!.longitude;
      out.sort((a, b) {
        final da = _haversineMeters(originLat, originLng, a.lat, a.lng);
        final db = _haversineMeters(originLat, originLng, b.lat, b.lng);
        return da.compareTo(db);
      });
    }

    return out;
  }

  // ------------------- Tabs -------------------

  List<String> _tabs() {
    final out = <String>["All"];

    final preferred = [
      "Culture",
      "Museum",
      "Nature",
      "Attraction",
      "Castles",
      "Restaurant",
      "Cafe",
      "Indoor",
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

  // ------------------- Category routing helpers -------------------

  String _categoryForPlace(Place p) {
    final pt = (p.primaryType ?? "").trim();
    if (pt.isEmpty) return "Attraction";

    if (_categoryConfig["Cafe"]!.includedTypes.contains(pt)) return "Cafe";
    if (_categoryConfig["Restaurant"]!.includedTypes.contains(pt)) return "Restaurant";
    if (_categoryConfig["Castles"]!.includedTypes.contains(pt)) return "Castles";

    for (final entry in _categoryConfig.entries) {
      final cat = entry.key;
      final cfg = entry.value;

      if (!_mainCategoriesForAll.contains(cat) && cat != "Castles") continue;
      if (cfg.includedTypes.contains(pt)) return cat;
    }

    return "Attraction";
  }

  void _upsertIntoPool(Place p) {
    if (_pos == null) return;

    final cat = _categoryForPlace(p);
    final originLat = _pos!.latitude;
    final originLng = _pos!.longitude;

    final list = List<Place>.from(_categoryPools[cat] ?? const <Place>[]);

    if (!list.any((x) => x.id == p.id)) {
      list.add(p);
    }

    list.sort((a, b) {
      final da = _haversineMeters(originLat, originLng, a.lat, a.lng);
      final db = _haversineMeters(originLat, originLng, b.lat, b.lng);
      return da.compareTo(db);
    });

    _categoryPools[cat] = list.take(_poolSize).toList();
  }

  void _insertBackToPool(Place p) {
    if (_pos == null) return;

    final cat = _categoryForPlace(p);
    final originLat = _pos!.latitude;
    final originLng = _pos!.longitude;

    final list = List<Place>.from(_categoryPools[cat] ?? const <Place>[]);

    if (_allPlan.any((x) => x.id == p.id)) return;
    if (list.any((x) => x.id == p.id)) return;

    list.add(p);

    list.sort((a, b) {
      final da = _haversineMeters(originLat, originLng, a.lat, a.lng);
      final db = _haversineMeters(originLat, originLng, b.lat, b.lng);
      return da.compareTo(db);
    });

    _categoryPools[cat] = list.take(_poolSize).toList();
  }

  // ------------------- Save prompt for Refresh/Delete -------------------


  Future<String> _resolveCityName() async {
    if (_pos == null) return "Unknown";
    if (_apiKey.isEmpty) return "Unknown";

    final lat = _pos!.latitude;
    final lng = _pos!.longitude;

    final url = Uri.parse(
      "https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$_apiKey",
    );

    final resp = await http.get(url);
    if (resp.statusCode != 200) return "Unknown";

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = (data["results"] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    for (final r in results) {
      final comps = (r["address_components"] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      for (final c in comps) {
        final types = (c["types"] as List?)?.cast<String>() ?? const [];
        if (types.contains("locality")) {
          final name = (c["long_name"] ?? "").toString().trim();
          if (name.isNotEmpty) return name;
        }
      }
    }

    // fallback: administrative_area_level_1 když "locality" není
    for (final r in results) {
      final comps = (r["address_components"] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      for (final c in comps) {
        final types = (c["types"] as List?)?.cast<String>() ?? const [];
        if (types.contains("administrative_area_level_1")) {
          final name = (c["long_name"] ?? "").toString().trim();
          if (name.isNotEmpty) return name;
        }
      }
    }

    return "Unknown";
  }

  Future<void> _openSavedPlansSheet() async {
    final saved = PlanStorage.loadSavedPlans();

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final items = [...saved]..sort((a, b) => a.city.toLowerCase().compareTo(b.city.toLowerCase()));

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Uložené",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text("Zatím nemáš uložený žádný plán."),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final it = items[i];
                        return ListTile(
                          title: Text(it.city),
                          subtitle: Text("${it.plan.length} míst"),
                          onTap: () async {
                            // načti plán
                            setState(() {
                              _allPlan = List<Place>.from(it.plan);
                              _sortAllByDistance();
                              _selectedTab = "All";
                            });
                            await PlanStorage.savePlan(_allPlan);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await PlanStorage.deleteSavedPlan(it.city);
                              if (ctx.mounted) Navigator.pop(ctx);
                              // znovu otevři se zaktualizovaným seznamem
                              if (mounted) await _openSavedPlansSheet();
                            },
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _askSaveCurrentPlanToSaved() async {
    final res = await showDialog<_SaveChoice>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Chceš uložit svůj plán?"),
          content: const Text("Pokud dáš Uložit, tvůj aktuální plán se uloží do „Uloženo“."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_SaveChoice.cancel),
              child: const Text("Zrušit"),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_SaveChoice.no),
              child: const Text("Ne"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(_SaveChoice.yes),
              child: const Text("Uložit"),
            ),
          ],
        );
      },
    );

    if (res == _SaveChoice.cancel || res == null) return false;

    if (res == _SaveChoice.yes) {

      final city = await _resolveCityName();
      await PlanStorage.upsertSavedPlan(
        city: city,
        lat: _pos!.latitude,
        lng: _pos!.longitude,
        plan: List<Place>.from(_allPlan),
      );
    }

    return true; // pokračovat v akci
  }

  // ------------------- Actions: All -------------------

  Set<String> _allIds() => _allPlan.map((p) => p.id).toSet();

  Future<void> _removeFromAllById(String id) async {
    final idx = _allPlan.indexWhere((p) => p.id == id);
    if (idx == -1) return;

    final removed = _allPlan[idx];

    setState(() {
      _allPlan.removeAt(idx);
      _insertBackToPool(removed);
      _sortAllByDistance();

      _hasUnsavedChanges = true;

    });

    await AnalyticsService.logRemove(id);
    await PlanStorage.saveCurrentPlan(_allPlan);
  }

  Future<void> _toggleDoneInAllById(String id) async {
    final idx = _allPlan.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final current = _allPlan[idx];
    setState(() {
      _allPlan[idx] = current.copyWith(done: !current.done);

      _hasUnsavedChanges = true;

    });
    await PlanStorage.saveCurrentPlan(_allPlan);
  }

  void _reorderAll(int oldIndex, int newIndex) async {
    if (_selectedTab != "All") return;

    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _allPlan.removeAt(oldIndex);
      _allPlan.insert(newIndex, item);
      _sortAllByDistance(); // držíme řazení dle km

      _hasUnsavedChanges = true;

    });
    await PlanStorage.saveCurrentPlan(_allPlan);
  }

  Future<void> _openReplaceForAllItem(Place current) async {
    if (_pos == null) return;

    final cat = _categoryForPlace(current);

    final candidates = List<Place>.from(_categoryPools[cat] ?? const <Place>[])
        .where((p) => p.id != current.id)
        .where((p) => !_allPlan.any((x) => x.id == p.id))
        .toList();

    final originLat = _pos!.latitude;
    final originLng = _pos!.longitude;
    candidates.sort((a, b) {
      final da = _haversineMeters(originLat, originLng, a.lat, a.lng);
      final db = _haversineMeters(originLat, originLng, b.lat, b.lng);
      return da.compareTo(db);
    });

    final selected = await showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => ReplaceSheet(
        title: "Replace ($cat)",
        originLat: originLat,
        originLng: originLng,
        currentId: current.id,
        allIds: _allIds(),
        candidates: candidates,
      ),
    );

    if (selected == null) return;

    setState(() {
      final idx = _allPlan.indexWhere((p) => p.id == current.id);
      if (idx != -1) _allPlan[idx] = selected;

      _upsertIntoPool(current);
      _upsertIntoPool(selected);

      _sortAllByDistance();

      _hasUnsavedChanges = true;

    });

    await AnalyticsService.logReplace(current.id);
    await PlanStorage.saveCurrentPlan(_allPlan);
  }

  // ------------------- Actions: Category pools -------------------

  Future<void> _addToAllFromCategory(Place p) async {
    if (_selectedTab == "All") return;
    if (_allPlan.any((x) => x.id == p.id)) return;

    setState(() {
      _allPlan.add(p);
      _sortAllByDistance();

      _hasUnsavedChanges = true;

    });

    await PlanStorage.saveCurrentPlan(_allPlan);
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

    final proceed = await _askSaveCurrentPlanToSaved();
    if (!proceed) return;

    setState(() {
      _loading = true;
      _error = null;
      _selectedTab = "All";
      _hasUnsavedChanges = false;
    });

    try {
      await _loadCategoryPools();

      _allPlan = _buildInitialAllFromPools();
      await PlanStorage.savePlan(_allPlan);

      setState(() {
        _hasUnsavedChanges = false; // ✅ po refresh je to zase Tips
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
    final proceed = await _askSaveCurrentPlanToSaved();
    if (!proceed) return;

    await PlanStorage.clearCurrentPlan();
    await _refreshEverything();
  }

  // ------------------- UI -------------------

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final tipsAccent = _hasUnsavedChanges ? _colorForTab("Attraction") : _colorForTab("Nature");
    final tipsEmoji = _hasUnsavedChanges ? "🧾" : "💡";

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

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                _cityLabel,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: s.share,
            onPressed: _shareAll,
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_outline),
            tooltip: "Uložené",
            onPressed: _openSavedPlansSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: s.refresh,
            onPressed: _refreshEverything,
          ),
        ],
      ),
      body: Column(
        children: [
          _SummaryBar(
            count: _allPlan.length,
            showSave: _hasUnsavedChanges,
            showClear: _selectedTab == "All",
            onSave: _saveCurrentPlanToSaved,
            onClear: _clearAllWithConfirm,
          ),




          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [

                  ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_hasUnsavedChanges ? "Yours" : "Tips"),
                        const SizedBox(width: 6),
                        Text(tipsEmoji),
                      ],
                    ),
                    selected: _selectedTab == "All",
                    selectedColor: tipsAccent.withOpacity(0.18),
                    backgroundColor: tipsAccent.withOpacity(0.10),
                    labelStyle: TextStyle(color: tipsAccent),
                    onSelected: (_) => setState(() => _selectedTab = "All"),
                  ),



                  const SizedBox(width: 8),

                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: tabs.where((t) => t != "All").length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final otherTabs = tabs.where((t) => t != "All").toList();
                        final t = otherTabs[i];
                        final selected = t == _selectedTab;

                        final accent = _colorForTab(t);
                        final emoji = _emojiForTab(t);

                        return ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(emoji),
                              const SizedBox(width: 6),
                              Text(t),
                            ],
                          ),
                          selected: selected,
                          selectedColor: accent.withOpacity(0.18),
                          backgroundColor: accent.withOpacity(0.10),
                          labelStyle: TextStyle(color: accent),
                          onSelected: (_) => setState(() => _selectedTab = t),
                        );
                      },
                    ),
                  ),
                ],
              ),
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

                  categoryMode: false,
                  onRemove: () => _removeFromAllById(place.id),
                  onReplace: () => _openReplaceForAllItem(place),
                  onToggleDone: () => _toggleDoneInAllById(place.id),

                  isFavorite: isFav,
                  onToggleFavorite: () => _toggleFavorite(place),

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

                return PlaceCard(
                  key: ValueKey(place.id),
                  place: place,
                  originLat: _pos!.latitude,
                  originLng: _pos!.longitude,
                  routes: _routes,
                  categoryMode: true,
                  onAddToAll: _allPlan.any((x) => x.id == place.id)
                      ? null
                      : () => _addToAllFromCategory(place),
                  isFavorite: isFav,
                  onToggleFavorite: () => _toggleFavorite(place),
                  onRemove: null,
                  onReplace: null,
                  onToggleDone: null,
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

enum _SaveChoice { yes, no, cancel }

// ------------------- Summary bar -------------------

class _SummaryBar extends StatelessWidget {
  final int count;
  final bool showSave;
  final bool showClear;
  final VoidCallback onSave;
  final VoidCallback onClear;

  const _SummaryBar({
    required this.count,
    required this.showSave,
    required this.showClear,
    required this.onSave,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                "${s.todaySpots}: $count spots ✨",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),

              // 💾 SAVE (jen když je změna)
              if (showSave) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onSave,
                  icon: const Icon(Icons.save),
                  tooltip: "Save",
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],

              // 🗑 CLEAR ALL (jen v All tabu)
              if (showClear) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_sweep),
                  tooltip: "Clear all",
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
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