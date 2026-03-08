import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;

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
import 'plan_map_screen.dart';

import 'dart:async';



class DayPlanScreen extends StatefulWidget {
  const DayPlanScreen({super.key});

  @override
  State<DayPlanScreen> createState() => _DayPlanScreenState();
}

enum _PopularityFilter { all, top }

_PopularityFilter _popFilter = _PopularityFilter.all;


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


  final Map<String, List<Place>> _categoryPoolsNearby = {};
  final Map<String, List<Place>> _categoryPoolsTop = {};

  Map<String, List<Place>> get _categoryPools =>
      (_popFilter == _PopularityFilter.top)
          ? _categoryPoolsTop
          : _categoryPoolsNearby;



  final ScrollController _listCtrl = ScrollController();


  String _selectedTab = "All";
  bool _hasUnsavedChanges = false;


  void _addPlaceToYours(Place p) {
    setState(() {
      // Pokud máš pro Yours vlastní klíč, uprav ho sem
      final list = _categoryPools.putIfAbsent("Yours", () => <Place>[]);

      // Nechceme duplicity
      final exists = list.any((x) => x.id == p.id);
      if (!exists) list.add(p);

      _hasUnsavedChanges = true;
    });
  }

  void _removeFromYoursById(String id) {
    setState(() {
      _categoryPools["Yours"]?.removeWhere((p) => p.id == id);
      _hasUnsavedChanges = true;
    });
  }

  void _addToAllFromCurrentTab(Place place) {
    // zachovej původní chování
    _addToAllFromCategory(place); // tohle je tvoje existující metoda

    // a navíc: když přidáváš z Yours, po přidání ho smaž z Yours poolu
    if (_selectedTab == "Yours") {
      setState(() {
        _categoryPools["Yours"]?.removeWhere((p) => p.id == place.id);
        _hasUnsavedChanges = true;
      });
    }
  }



  static const UserProfile _fixedProfile = UserProfile.solo;
  static const _apiKey = String.fromEnvironment('PLACES_REST_KEY');

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
    "Culture": "⛪️",
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
  bool _ignoreEffectivePosChanges = false;
  late final VoidCallback _effectivePosListener;

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

    // Listener: když se změní efektivní poloha (GPS <-> město), přestav plán
    _effectivePosListener = () {
      if (_ignoreEffectivePosChanges) return;

      final p = LocationService.effectivePosition.value;
      if (p == null) return;
      _applyNewLocationAndRebuild(p);
    };
    LocationService.effectivePosition.addListener(_effectivePosListener);

    _init();
  }

  @override
  void dispose() {
    LocationService.effectivePosition.removeListener(_effectivePosListener);

    _listCtrl.dispose();

    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _openPlanMap() {
    if (_pos == null) return;

    final list = _currentList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlanMapScreen(
          title: _selectedTab == "All" ? "Yours" : _selectedTab,
          places: List<Place>.from(_currentList()),
          originLat: _pos!.latitude,
          originLng: _pos!.longitude,
          routes: _routes,
        ),
      ),
    );
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
      // ✅ nově: bereme efektivní lokaci (GPS nebo ruční město)
      final p = await LocationService.getEffectiveLocation();
      if (p == null) {
        setState(() {
          _loading = false;
          _error = S.of(context).locationNeeded;
        });
        return;
      }

      _pos = p;

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

  // ------------------- Location switching (GPS label click) -------------------

  Future<void> _applyNewLocationAndRebuild(Position p) async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _selectedTab = "All";
      _hasUnsavedChanges = false;
    });

    try {
      _pos = p;

      // Kompletně přepočítat vše od nové polohy:
      _categoryPoolsNearby.clear();
      _categoryPoolsTop.clear();
      await _loadCategoryPools();

      _allPlan = _buildInitialAllFromPools();
      await PlanStorage.saveCurrentPlan(_allPlan);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _applyLocationAndReloadPoolsOnly({
    required String label,
    required double lat,
    required double lng,
  }) async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _selectedTab = "All";
    });

    _ignoreEffectivePosChanges = true;
    try {
      // nastav manual lokaci (změní label nahoře + effectivePosition)
      LocationService.setManualLocation(
        label: label,
        latitude: lat,
        longitude: lng,
      );

      // nastav _pos tak, aby se vše počítalo od nového místa
      _pos = Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0, // pokud ti to hází error, smaž tento řádek (dle verze geolocatoru)
        headingAccuracy: 0,  // pokud ti to hází error, smaž tento řádek (dle verze geolocatoru)
      );

      // reload katalogů pro nové město
      _categoryPoolsNearby.clear();
      _categoryPoolsTop.clear();
      await _loadCategoryPools();

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    } finally {
      _ignoreEffectivePosChanges = false;
    }
  }

  Future<void> _openCityPicker() async {
    final picked = await showModalBottomSheet<_PickedCity>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _CityPickerSheet(
        apiKey: _apiKey,
        biasLat: _pos?.latitude,
        biasLng: _pos?.longitude,
      ),
    );

    if (picked == null) return;

    if (picked.useGps) {
      await LocationService.clearManualLocation();
      return;
    }

    LocationService.setManualLocation(
      label: picked.label,
      latitude: picked.lat,
      longitude: picked.lng,
    );
  }

  // ------------------- Helpers -------------------

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

    int popScore(Place p) {
      final r = p.rating ?? 0.0;
      final c = p.userRatingsTotal ?? 0;
      return (r * 1000).round() + c;
    }

    for (final entry in _categoryConfig.entries) {
      final key = entry.key;
      final cfg = entry.value;

      final normalRadius = min(cfg.radiusMeters, 50000);
      final topRadius = 20000;

      // -------- NEARBY DATASET --------

      final rawNearby = await _places.nearby(
        lat: originLat,
        lng: originLng,
        radiusMeters: normalRadius,
        maxResults: 20,
        rankPreference: "DISTANCE",
        includedTypes: cfg.includedTypes.toList(),
      );

      // -------- TOP DATASET --------

      final rawTop = await _places.nearby(
        lat: originLat,
        lng: originLng,
        radiusMeters: topRadius,
        maxResults: 20,
        rankPreference: "POPULARITY",
        includedTypes: cfg.includedTypes.toList(),
      );

      List<Place> mapPlaces(List raw) {
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

        return mapped;
      }

      final nearbyMapped = mapPlaces(rawNearby);
      final topMapped = mapPlaces(rawTop);

      // sort nearby distance
      nearbyMapped.sort((a, b) {
        final da = _haversineMeters(originLat, originLng, a.lat, a.lng);
        final db = _haversineMeters(originLat, originLng, b.lat, b.lng);
        return da.compareTo(db);
      });

      // sort top popularity
      topMapped.sort((a, b) {
        final sa = popScore(a);
        final sb = popScore(b);
        final s = sb.compareTo(sa);
        if (s != 0) return s;

        final da = _haversineMeters(originLat, originLng, a.lat, a.lng);
        final db = _haversineMeters(originLat, originLng, b.lat, b.lng);
        return da.compareTo(db);
      });

      List<Place> trim(List<Place> list) {
        final uniq = <String>{};
        final out = <Place>[];

        for (final pl in list) {
          if (uniq.add(pl.id)) out.add(pl);
          if (out.length >= _poolSize) break;
        }

        return out;
      }

      _categoryPoolsNearby[key] = trim(nearbyMapped);
      _categoryPoolsTop[key] = trim(topMapped);
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
    final topOn = _popFilter == _PopularityFilter.top;

    int popScore(Place p) {
      final r = p.rating ?? 0.0;
      final c = p.userRatingsTotal ?? 0;
      return (r * 1000).round() + c;
    }

    // 1) "All" = žádná kategorie vybraná
    if (_selectedTab == "All") {
      if (!topOn) return _allPlan;

      // TOP GLOBAL: merge všech top poolů, dedupe
      final seen = <String>{};
      final out = <Place>[];

      const perCategoryLimit = 3;

      for (final entry in _categoryPoolsTop.entries) {
        final catList = entry.value;

        var taken = 0;
        for (final p in catList) {
          if (seen.add(p.id)) {
            out.add(p);
            taken++;
            if (taken >= perCategoryLimit) break; // ✅ max 3 z kategorie
          }
        }
      }

      // ✅ stejné řazení jako v Top kategoriích
      out.sort((a, b) {
        final sa = popScore(a);
        final sb = popScore(b);
        final s = sb.compareTo(sa);
        if (s != 0) return s;

        // fallback distance (když je _pos)
        if (_pos == null) return 0;
        final da = _haversineMeters(_pos!.latitude, _pos!.longitude, a.lat, a.lng);
        final db = _haversineMeters(_pos!.latitude, _pos!.longitude, b.lat, b.lng);
        return da.compareTo(db);
      });

      return out;
    }

    // 2) Kategorie
    if (topOn) {
      return _categoryPoolsTop[_selectedTab] ?? const <Place>[];
    } else {
      return _categoryPoolsNearby[_selectedTab] ?? const <Place>[];
    }
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
      final db = _haversineMeters(originLat, originLng, a.lat, a.lng);
      return da.compareTo(db);
    });

    _categoryPools[cat] = list.take(_poolSize).toList();
  }

  // ------------------- Save prompt for Refresh/Delete -------------------


  String _cityKeyFromLabel(String label) {
    final t = label.trim();
    if (t.isEmpty) return "Unknown";
    // vezmeme jen první část před čárkou -> New York, Spojené státy... => New York
    return t.split(',').first.trim();
  }

  Future<String> _resolveCityName() async {
    // 1) Když máš ručně vybrané město, použij přímo label (nejspolehlivější)
    final label = LocationService.locationLabel.value.trim();
    if (label.isNotEmpty && label.toUpperCase() != "GPS" && label.toLowerCase() != "unknown") {
      return _cityKeyFromLabel(label);
    }

    // 2) GPS / fallback: reverse geocode z aktuální pozice
    if (_pos == null) return "Unknown";
    if (_apiKey.isEmpty) return "Unknown";

    final lat = _pos!.latitude;
    final lng = _pos!.longitude;

    final url = Uri.parse(
      "https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$_apiKey&language=en",
    );

    final resp = await http.get(url);
    if (resp.statusCode != 200) return label.isNotEmpty ? _cityKeyFromLabel(label) : "Unknown";

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = (data["results"] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    String? pickFromTypes(Set<String> wanted) {
      for (final r in results) {
        final comps = (r["address_components"] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        for (final c in comps) {
          final types = (c["types"] as List?)?.cast<String>() ?? const [];
          if (types.any(wanted.contains)) {
            final name = (c["long_name"] ?? "").toString().trim();
            if (name.isNotEmpty) return name;
          }
        }
      }
      return null;
    }

    // pořadí: locality -> postal_town -> admin_area_level_2 -> admin_area_level_1
    final city =
        pickFromTypes({"locality"}) ??
            pickFromTypes({"postal_town"}) ??
            pickFromTypes({"administrative_area_level_2"}) ??
            pickFromTypes({"administrative_area_level_1"});

    return city ?? (label.isNotEmpty ? _cityKeyFromLabel(label) : "Unknown");
  }

  Future<void> _saveCurrentPlanToSaved() async {
    if (_pos == null) return;

    final suggested = await _resolveCityName();

    final name = await _askPlanName(context, suggested);
    if (!mounted || name == null) return;

    await PlanStorage.upsertSavedPlan(
      city: name, // ✅ ručně zadaný název
      lat: _pos!.latitude,
      lng: _pos!.longitude,
      plan: List<Place>.from(_allPlan),
    );

    if (!mounted) return;
    setState(() => _hasUnsavedChanges = false);
  }

  Future<String?> _askPlanName(BuildContext context, String suggested) async {
    final ctrl = TextEditingController(text: suggested);

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 14,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Save plan',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(null),
                    icon: const Icon(Icons.close),
                    splashRadius: 20,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  hintText: 'Plan name',
                  border: UnderlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) {
                  final name = ctrl.text.trim();
                  Navigator.of(ctx).pop(name.isEmpty ? null : name);
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final name = ctrl.text.trim();
                    Navigator.of(ctx).pop(name.isEmpty ? null : name);
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        );
      },
    );


    return result;
  }


  Future<void> _clearAllWithConfirm() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Are you sure clean your plan ?"),
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

  Future<void> _openSavedPlansSheet() async {
    final saved = PlanStorage.loadSavedPlans();

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final items = [...saved]
          ..sort((a, b) => a.city.toLowerCase().compareTo(b.city.toLowerCase()));

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Saved",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text("Empty storage."),
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
                            // 1) přepni lokaci + reload pools
                            await _applyLocationAndReloadPoolsOnly(
                              label: it.city,   // nebo it.cityLabel pokud máš
                              lat: it.lat,
                              lng: it.lng,
                            );

                            // 2) teprve potom nahraj uložený plán (Yours)
                            if (!mounted) return;
                            setState(() {
                              _allPlan = List<Place>.from(it.plan);
                              _sortAllByDistance();
                              _selectedTab = "All";
                              _hasUnsavedChanges = false;
                            });

                            await PlanStorage.saveCurrentPlan(_allPlan);

                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await PlanStorage.deleteSavedPlan(it.city);
                              if (ctx.mounted) Navigator.pop(ctx);
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
          title: const Text("Save your plan?"),
          content: const Text("If Yes, your current plan will be saved to Saved."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_SaveChoice.cancel),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_SaveChoice.no),
              child: const Text("No"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(_SaveChoice.yes),
              child: const Text("Save"),
            ),
          ],
        );
      },
    );

    // Cancel / tap outside -> stop refresh
    if (res == null || res == _SaveChoice.cancel) return false;

    // ✅ No -> continue refresh
    if (res == _SaveChoice.no) return true;

    // Yes -> save then continue refresh
    if (res == _SaveChoice.yes) {
      if (_pos == null) return true; // nebo false, ale většinou ať refresh běží

      final suggested = await _resolveCityName();
      final name = await _askPlanName(context, suggested);
      if (!mounted || name == null) return false; // tady když zavře pojmenování, beru jako cancel

      await PlanStorage.upsertSavedPlan(
        city: name,
        lat: _pos!.latitude,
        lng: _pos!.longitude,
        plan: List<Place>.from(_allPlan),
      );

      if (mounted) setState(() => _hasUnsavedChanges = false);
      return true;
    }

    return true;
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

  Future<void> _addPlaceToAllFromTop(Place place) async {
    if (_allPlan.any((x) => x.id == place.id)) return;

    setState(() {
      _allPlan.add(place);
      _sortAllByDistance();
      _hasUnsavedChanges = true;
    });

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

  void _removeFromPoolById(String tab, String id) {
    setState(() {
      _categoryPools[tab]?.removeWhere((p) => p.id == id);
      _hasUnsavedChanges = true;
    });
  }


  void _addPlaceToPool(String tab, Place p) {
    debugPrint("ADD TO POOL tab=$tab id=${p.id} name=${p.name}");
    setState(() {
      final list = _categoryPools.putIfAbsent(tab, () => <Place>[]);
      final before = list.length;
      if (!list.any((x) => x.id == p.id)) {
        list.add(p);
        _hasUnsavedChanges = true;
      }
      debugPrint("POOL $tab size: $before -> ${list.length}");
    });
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
        _hasUnsavedChanges = false;
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


  Widget _buildTripcoLogo() {
    const textStyle = TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w900,
      letterSpacing: 0,
      color: Color(0xFF1F1F1F),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: const TextSpan(text: "eTripco", style: textStyle),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();

        final textWidth = painter.width;
        final textHeight = painter.height;

        // pozice tečky relativně podle šířky textu
        final dotLeft = textWidth * 0.44;
        final dotTop = textHeight * 0.02;

        return SizedBox(
          width: textWidth,
          height: textHeight + 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Text(
                "eTripco",
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: textStyle,
              ),
              Positioned(
                left: dotLeft,
                top: dotTop,
                child: Container(
                  width: 6,
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF7A00),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ------------------- UI -------------------



  Widget _buildTipsYoursToggle(Color tipsAccent) {
    final isTop = _popFilter == _PopularityFilter.top;
    final leftLabel = _hasUnsavedChanges ? "Yours" : "Tips";
    final leftPinIsDiagonal = !_hasUnsavedChanges;

    return ChoiceChip(
      showCheckmark: false,
      selected: !isTop,
      selectedColor: Colors.amber.withOpacity(0.22), // stejná barva jako Top
      backgroundColor: Colors.white,
      side: BorderSide(
        color: !isTop ? Colors.amber.shade700 : Colors.black12,
        width: 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),

      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isTop) ...[
            Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: Colors.black87,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check,
                size: 15,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
          ],

          Text(
            leftLabel,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(width: 8),

          Transform.rotate(
            angle: leftPinIsDiagonal ? -0.6 : 0.0,
            child: const Icon(
              Icons.push_pin,
              size: 16,
              color: Colors.red,
            ),
          ),
        ],
      ),

      onSelected: (_) {
        setState(() {
          _popFilter = _PopularityFilter.all;
          _selectedTab = "All";
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_listCtrl.hasClients) {
            _listCtrl.animateTo(
              0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });
      },
    );
  }


  Widget _buildTopCategoryChip() {
    final isTop = _popFilter == _PopularityFilter.top;

    return ChoiceChip(
      showCheckmark: false,
      selected: isTop,
      selectedColor: Colors.amber.withOpacity(0.22),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: isTop ? Colors.amber.shade700 : Colors.black12,
        width: 1,
      ),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isTop) ...[
            Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Colors.black87,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check,
                size: 14,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          const Text(
            "⭐",
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 6),
          const Text(
            "Top",
            style: TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      onSelected: (_) {
        final turnOn = !isTop;

        setState(() {
          _popFilter = turnOn ? _PopularityFilter.top : _PopularityFilter.all;
          if (!turnOn) {
            _selectedTab = "All";
          }
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_listCtrl.hasClients) {
            _listCtrl.animateTo(
              0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final tipsAccent = _hasUnsavedChanges ? _colorForTab("Attraction") : _colorForTab("Nature");
    final tipsEmoji = _hasUnsavedChanges ? "📍" : "📌";



    final tabs = _tabs();
    final list = _currentList();

    final topOn = _popFilter == _PopularityFilter.top;
    final isTopGlobal = topOn && _selectedTab == "All";

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 0,
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _buildTipsYoursToggle(tipsAccent),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _buildTripcoLogo(),
                ),
              ),
            ),
          ],
        ),

        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: "Map",
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
            onPressed: _openPlanMap,
          ),

          IconButton(
            icon: const Icon(Icons.search),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
            onPressed: () => _openPlaceSearch(context),
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_outline),
            tooltip: "Saved",
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
            onPressed: _openSavedPlansSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: s.refresh,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
            onPressed: _popFilter == _PopularityFilter.top
                ? null
                : _refreshEverything,
          ),
        ],
      ),
      body: Column(
        children: [
          _SummaryBar(
            count: _allPlan.length,
            showSave: _popFilter != _PopularityFilter.top && _hasUnsavedChanges,
            showClear: _popFilter != _PopularityFilter.top, // ✅ vždy v normal režimu
            onSave: _saveCurrentPlanToSaved,
            onClear: _clearAllWithConfirm,
            onPickLocation: _openCityPicker,
          ),

          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [



                  // ---------------- CATEGORY TABS ----------------
                  Expanded(
                    child: Row(
                      children: [
                        _buildTopCategoryChip(),
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
                                onSelected: (_) {
                                  setState(() {
                                    _selectedTab = (_selectedTab == t) ? "All" : t;
                                  });

                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (_listCtrl.hasClients) {
                                      _listCtrl.animateTo(
                                        0,
                                        duration: const Duration(milliseconds: 250),
                                        curve: Curves.easeOut,
                                      );
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),





          const SizedBox(height: 6),
          Expanded(
            child: isTopGlobal
                ? ListView.builder(
                  controller: _listCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final place = list[i];
                    final isFav = FavoritesStorage.isFavorite(place.id);

                    final alreadyInYours = _allPlan.any((x) => x.id == place.id);

                    return PlaceCard(
                      key: ValueKey(place.id),
                      place: place,
                      apiKey: _apiKey,
                      originLat: _pos!.latitude,
                      originLng: _pos!.longitude,
                      routes: _routes,
                      accentColor: _colorForTab(_targetCategoryForPrimaryType(place.primaryType)),

                      // ✅ chovej se jako kategorie: Add + (Navigate uvnitř karty)
                      categoryMode: true,

                      // ✅ jen Add (zmizí když už je v Yours)
                      onAddToAll: alreadyInYours ? null : () => _addPlaceToAllFromTop(place),

                      // ✅ zakázat věci z Yours UI
                      onRemove: null,
                      onReplace: null,
                      onToggleDone: null,

                      isFavorite: isFav,
                      onToggleFavorite: () => _toggleFavorite(place),
                    );
                  },
                )
              : _selectedTab == "All"
                  ? ReorderableListView.builder(
                      scrollController: _listCtrl,
                      padding: const EdgeInsets.all(12),
                      itemCount: list.length,
                      onReorder: _reorderAll,
                      itemBuilder: (context, i) {
                        final place = list[i];
                        final isFav = FavoritesStorage.isFavorite(place.id);
                        final isManual = place.isManual;

                        return PlaceCard(
                          key: ValueKey(place.id),
                          place: place,
                          apiKey: _apiKey,
                          originLat: _pos!.latitude,
                          originLng: _pos!.longitude,
                          routes: _routes,
                          accentColor: _colorForTab(_targetCategoryForPrimaryType(place.primaryType)),
                          categoryMode: false,
                          onRemove: () => _removeFromAllById(place.id),
                          onReplace: isManual ? null : () => _openReplaceForAllItem(place),
                          onToggleDone: () => _toggleDoneInAllById(place.id),
                          isFavorite: isFav,
                          onToggleFavorite: () => _toggleFavorite(place),
                          onAddToAll: null,
                        );
                      },
                  )




                : ListView.builder(

              controller: _listCtrl,

              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final place = list[i];
                final isFav = FavoritesStorage.isFavorite(place.id);

                final isUserTab = _selectedTab == "Yours" || _selectedTab == "Tips";
                final disableReplace = isUserTab && place.isManual;

                final isManual = place.isManual;

                if (isUserTab && isManual) {
                  // ✅ jen Remove (pro místa z lupy)
                  return PlaceCard(
                    key: ValueKey(place.id),
                    place: place,
                    apiKey: _apiKey,
                    originLat: _pos!.latitude,
                    originLng: _pos!.longitude,
                    routes: _routes,
                    accentColor: _colorForTab(_targetCategoryForPrimaryType(place.primaryType)),
                    categoryMode: false,
                    onAddToAll: null,
                    onReplace: disableReplace ? null : () => _openReplaceForAllItem(place),
                    onToggleDone: null,
                    onRemove: () => _removeFromPoolById(_selectedTab, place.id),
                    isFavorite: isFav,
                    onToggleFavorite: () => _toggleFavorite(place),
                  );
                }

// ✅ ostatní (katalogové) beze změny:
                return PlaceCard(
                  key: ValueKey(place.id),
                  place: place,
                  apiKey: _apiKey,
                  originLat: _pos!.latitude,
                  originLng: _pos!.longitude,
                  routes: _routes,
                  accentColor: _colorForTab(_targetCategoryForPrimaryType(place.primaryType)),
                  categoryMode: true,
                  onAddToAll: _allPlan.any((x) => x.id == place.id)
                      ? null
                      : () => _addToAllFromCurrentTab(place),
                  isFavorite: isFav,
                  onToggleFavorite: () => _toggleFavorite(place),
                  onRemove: null,
                  onReplace: null,
                  onToggleDone: null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }



  void _openPlaceSearch(BuildContext context) {
    final target = (_selectedTab == "Tips" || _selectedTab == "Yours")
        ? _selectedTab
        : "Yours";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PlaceSearchSheet(
        onAddToYours: (place) {
          setState(() {
            // ✅ rovnou do All plánu
            if (!_allPlan.any((x) => x.id == place.id)) {
              _allPlan.add(place);
              _sortAllByDistance();
              _hasUnsavedChanges = true;
            }
            _selectedTab = "All"; // nebo nech "Yours" podle toho co chceš ukázat
          });
        },
      ),
    );
  }

}

class _PlaceSearchSheet extends StatefulWidget {
  final void Function(Place place) onAddToYours;

  const _PlaceSearchSheet({
    super.key,
    required this.onAddToYours,
  });

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {

  static const _placesKey = String.fromEnvironment('PLACES_REST_KEY');
  static const _placesKeyFallback = String.fromEnvironment('GOOGLE_API_KEY');

  String get _apiKey =>
      _placesKey.isNotEmpty ? _placesKey : _placesKeyFallback;

  final TextEditingController _controller = TextEditingController();
  List<_PlaceSuggestion> _results = [];
  Timer? _debounce;
  bool _loading = false;
  String? _error;

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();

    if (q.isEmpty) {
      setState(() {
        _results = [];
        _error = null;
        _loading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() {
        _loading = true;
        _error = null;
      });

      try {
        final items = await _fetchAutocomplete(q);
        if (!mounted) return;
        setState(() {
          _results = items;
          _loading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    });
  }

  Future<List<_PlaceSuggestion>> _fetchAutocomplete(String input) async {
    final uri = Uri.parse('https://places.googleapis.com/v1/places:autocomplete');

    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': _apiKey,
        'X-Goog-FieldMask':
        'suggestions.placePrediction.placeId,suggestions.placePrediction.text',
      },
      body: jsonEncode({
        'input': input,
        'languageCode': 'cs',
        'regionCode': 'CZ',
      }),
    );



    if (res.statusCode != 200) {
      throw Exception('Places autocomplete ${res.statusCode}: ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final suggestions = (data['suggestions'] as List? ?? const []);

    return suggestions
        .map((s) => s['placePrediction'])
        .where((p) => p != null)
        .map<_PlaceSuggestion>((p) {
      final text = (p['text']?['text'] as String?) ?? '';
      final placeId = (p['placeId'] as String?) ?? '';
      return _PlaceSuggestion(placeId: placeId, text: text);
    })
        .where((x) => x.placeId.isNotEmpty && x.text.isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>> _fetchPlaceDetail(String placeId) async {
    final uri = Uri.parse('https://places.googleapis.com/v1/places/$placeId');

    final res = await http.get(
      uri,
      headers: {
        'X-Goog-Api-Key': _apiKey,
        'X-Goog-FieldMask':
        'id,displayName,location,types,rating,regularOpeningHours,googleMapsUri,websiteUri',
      },
    );

    if (res.statusCode != 200) {
      throw Exception('Place detail ${res.statusCode}: ${res.body}');
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    if (_apiKey.isEmpty) {
      return const Center(child: Text("Missing PLACES_REST_KEY"));
    }

    return SafeArea(
      child: Padding(
        padding: MediaQuery.of(context).viewInsets,
        child: SizedBox(
          height: 400, // nechávám stejně jako máš teď
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              children: [
                // ===== Header: Search place + X =====
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Search place',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      splashRadius: 20,
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ===== Input: lupa + Start writing (nic víc) =====
                TextField(
                  controller: _controller,
                  autofocus: true,
                  onChanged: _onChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Start writing',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (_, v, __) {
                        if (v.text.isEmpty) return const SizedBox.shrink();
                        return IconButton(
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                          },
                          icon: const Icon(Icons.close),
                          splashRadius: 20,
                          tooltip: 'Clear',
                        );
                      },
                    ),
                    border: const UnderlineInputBorder(),
                    isDense: true,
                  ),
                ),

                const SizedBox(height: 6),

                // ===== Seznam (stejně jako teď) =====
                Expanded(
                  child: Builder(
                    builder: (_) {
                      if (_loading) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (_error != null) {
                        return Center(child: Text(_error!));
                      }

                      return ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, index) {
                          return ListTile(
                            title: Text(_results[index].text),
                            onTap: () async {
                              final picked = _results[index];

                              try {
                                final detail = await _fetchPlaceDetail(picked.placeId);
                                final websiteUrl = detail['websiteUri'] as String?;
                                if (!mounted) return;

                                final name =
                                    (detail['displayName']?['text'] as String?) ??
                                        picked.text;

                                final loc = detail['location'] as Map<String, dynamic>?;
                                final lat = (loc?['latitude'] as num?)?.toDouble();
                                final lng = (loc?['longitude'] as num?)?.toDouble();

                                if (lat == null || lng == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Place has no location')),
                                  );
                                  return;
                                }

                                final types = (detail['types'] as List?)?.cast<String>() ??
                                    const <String>[];
                                final placeType = types.isNotEmpty ? types.first : 'custom';

                                final rating = (detail['rating'] as num?)?.toDouble();
                                final googleMapsUri = detail['googleMapsUri'] as String?;

                                final place = Place(
                                  id: picked.placeId,
                                  name: name,
                                  type: placeType,
                                  distanceMinutes: 0,
                                  lat: lat,
                                  lng: lng,
                                  rating: rating,
                                  googleMapsUri: googleMapsUri,
                                  websiteUrl: websiteUrl,
                                  isManual: true,
                                );

                                debugPrint(
                                    "SEARCH PICKED -> calling onAddToYours: ${place.id} $name");
                                widget.onAddToYours(place);
                                debugPrint("SEARCH PICKED -> called, closing sheet");
                                Navigator.pop(context);
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
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

  // ✅ nové: klik na lokaci (otevře city picker)
  final VoidCallback onPickLocation;

  const _SummaryBar({
    required this.count,
    required this.showSave,
    required this.showClear,
    required this.onSave,
    required this.onClear,
    required this.onPickLocation,
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

          // ✅ místo "Tripco" zobrazíme GPS / Brno (a je to klikatelné)
          ValueListenableBuilder<String>(
            valueListenable: LocationService.locationLabel,
            builder: (_, label, __) {
              return Expanded(   // ✅ klíčové
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onPickLocation,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(  // ✅ klíčové
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down, size: 18),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ------------------- City picker bottom sheet -------------------

class _PickedCity {
  final String label;
  final double lat;
  final double lng;
  final bool useGps;

  const _PickedCity({
    required this.label,
    required this.lat,
    required this.lng,
    this.useGps = false,
  });

  const _PickedCity.useGps()
      : label = "GPS",
        lat = 0,
        lng = 0,
        useGps = true;
}



class _CityPickerSheet extends StatefulWidget {
  final String apiKey;
  final double? biasLat;
  final double? biasLng;

  const _CityPickerSheet({
    required this.apiKey,
    this.biasLat,
    this.biasLng,
  });

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _GPrediction {
  final String label;
  final String placeId;
  const _GPrediction({required this.label, required this.placeId});
}


class _CityPickerSheetState extends State<_CityPickerSheet> {
  final _controller = TextEditingController();
  bool _loading = false;
  List<_PickedCity> _items = [];
  _PickedCity? _selected;



  int _callId = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _stripDiacritics(String input) {
    const map = {
      'á': 'a', 'č': 'c', 'ď': 'd', 'é': 'e', 'ě': 'e', 'í': 'i', 'ň': 'n', 'ó': 'o',
      'ř': 'r', 'š': 's', 'ť': 't', 'ú': 'u', 'ů': 'u', 'ý': 'y', 'ž': 'z',
      'Á': 'A', 'Č': 'C', 'Ď': 'D', 'É': 'E', 'Ě': 'E', 'Í': 'I', 'Ň': 'N', 'Ó': 'O',
      'Ř': 'R', 'Š': 'S', 'Ť': 'T', 'Ú': 'U', 'Ů': 'U', 'Ý': 'Y', 'Ž': 'Z',
    };

    final sb = StringBuffer();
    for (final ch in input.split('')) {
      sb.write(map[ch] ?? ch);
    }
    return sb.toString();
  }



  Future<List<_GPrediction>> _googleCitiesAutocomplete(String input) async {
    final params = <String, String>{
      "input": input,
      "types": "(cities)",
      "language": "cs",
      "key": widget.apiKey,
    };

    // ✅ bias jen pro relevanci, pořád celý svět
    if (widget.biasLat != null && widget.biasLng != null) {
      params["location"] = "${widget.biasLat},${widget.biasLng}";
      params["radius"] = "200000"; // 200 km bias
    }

    final uri = Uri.https("maps.googleapis.com", "/maps/api/place/autocomplete/json", params);

    final resp = await http.get(uri);
    debugPrint("G_AUTOCOMPLETE: $uri");
    debugPrint("G_AUTOCOMPLETE status=${resp.statusCode} len=${resp.body.length}");

    if (resp.statusCode != 200) return const [];

    final root = jsonDecode(resp.body) as Map<String, dynamic>;

    final status = (root["status"] ?? "").toString();
    if (status != "OK" && status != "ZERO_RESULTS") {
      // tady uvidíš důvod typu REQUEST_DENIED / INVALID_REQUEST
      debugPrint("G_AUTOCOMPLETE status=$status error=${root["error_message"]}");
      return const [];
    }

    final preds = (root["predictions"] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    return preds.map((p) {
      final desc = (p["description"] ?? "").toString().trim();
      final placeId = (p["place_id"] ?? "").toString().trim();
      return _GPrediction(label: desc, placeId: placeId);
    }).where((p) => p.label.isNotEmpty && p.placeId.isNotEmpty).toList();
  }


  Future<({double lat, double lng})?> _googlePlaceDetailsLatLng(String placeId) async {
    final uri = Uri.https("maps.googleapis.com", "/maps/api/place/details/json", {
      "place_id": placeId,
      "fields": "geometry,name",
      "key": widget.apiKey,
      "language": "cs",
    });

    final resp = await http.get(uri);
    debugPrint("G_DETAILS: $uri");
    debugPrint("G_DETAILS status=${resp.statusCode} len=${resp.body.length}");

    if (resp.statusCode != 200) return null;

    final root = jsonDecode(resp.body) as Map<String, dynamic>;

    final status = (root["status"] ?? "").toString();
    if (status != "OK") {
      debugPrint("G_DETAILS status=$status error=${root["error_message"]}");
      return null;
    }

    final result = (root["result"] as Map?)?.cast<String, dynamic>();
    final geom = (result?["geometry"] as Map?)?.cast<String, dynamic>();
    final loc = (geom?["location"] as Map?)?.cast<String, dynamic>();

    final lat = (loc?["lat"] as num?)?.toDouble();
    final lng = (loc?["lng"] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    return (lat: lat, lng: lng);
  }




  Future<List<_PickedCity>> _fetchSuggestions(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];

    // 1) autocomplete
    final preds = await _googleCitiesAutocomplete(q);

    // 2) details -> lat/lng
    final out = <_PickedCity>[];
    for (final p in preds.take(10)) {
      final ll = await _googlePlaceDetailsLatLng(p.placeId);
      if (ll == null) continue;
      out.add(_PickedCity(label: p.label, lat: ll.lat, lng: ll.lng));
    }
    return out;
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    final myCall = ++_callId;

    // ✅ KLÍČOVÉ: od 2 znaků (tím zmizí Brazílie při "br")
    if (query.length < 2) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _selected = null;
        _loading = false;
      });
      return;
    }

    // debounce
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    if (myCall != _callId) return;

    setState(() => _loading = true);
    try {
      var out = await _fetchSuggestions(query);

      // fallback bez diakritiky (když nic nenajde)
      final noDia = _stripDiacritics(query);
      if (out.isEmpty && noDia != query) {
        out = await _fetchSuggestions(noDia);
      }

      if (!mounted) return;
      if (myCall != _callId) return;

      setState(() {
        _items = out;
        _selected = null;
      });
    } finally {
      if (mounted && myCall == _callId) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Select a city",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: "Start writing",
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    onPressed: () {
                      _controller.clear();
                      setState(() {
                        _items = [];
                        _selected = null;
                        _loading = false;
                      });
                    },
                    icon: const Icon(Icons.clear),
                  ),
                ),
                onChanged: _search,
              ),
              const SizedBox(height: 10),
              if (_loading) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(context, const _PickedCity.useGps()),
                  icon: const Icon(Icons.my_location),
                  label: const Text("Use GPS"),
                ),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final it = _items[i];
                    final selected = _selected == it;
                    return ListTile(
                      title: Text(it.label),
                      trailing: selected ? const Icon(Icons.check) : null,
                      onTap: () => setState(() => _selected = it),
                      onLongPress: () => Navigator.pop(context, it),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selected == null ? null : () => Navigator.pop(context, _selected),
                      child: const Text("Use"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------- Category config -------------------

class _CategoryConfig {
  final Set<String> includedTypes;
  final int radiusMeters;
  const _CategoryConfig({required this.includedTypes, required this.radiusMeters});
}

// ------------------- Haversine -------------------

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLon = _degToRad(lon2 - lon1);
  final a = (sin(dLat / 2) * sin(dLat / 2)) +
      cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * (sin(dLon / 2) * sin(dLon / 2));
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return r * c;
}

class _PlaceSuggestion {
  final String placeId;
  final String text;
  const _PlaceSuggestion({required this.placeId, required this.text});
}

double _degToRad(double d) => d * (pi / 180.0);







enum _AddTarget { tips, yours, both }

class _AddToDialog extends StatefulWidget {
  final String placeName;
  const _AddToDialog({required this.placeName});

  @override
  State<_AddToDialog> createState() => _AddToDialogState();
}

class _AddToDialogState extends State<_AddToDialog> {
  bool tips = true;
  bool yours = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add place'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.placeName),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: tips,
            onChanged: (v) => setState(() => tips = v ?? false),
            title: const Text('Tips'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            value: yours,
            onChanged: (v) => setState(() => yours = v ?? false),
            title: const Text('Yours'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (!tips && !yours) return;
            if (tips && yours) return Navigator.pop(context, _AddTarget.both);
            if (tips) return Navigator.pop(context, _AddTarget.tips);
            return Navigator.pop(context, _AddTarget.yours);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}