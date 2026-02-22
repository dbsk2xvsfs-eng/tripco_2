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
import '../services/profile_storage.dart';
import '../services/recommendation_service.dart';
import '../services/routes_service.dart';

import '../widgets/place_card.dart';
import '../widgets/profile_sheet.dart';

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

  List<Place> _plan = [];
  UserProfile _profile = UserProfile.solo;

  static const _apiKey = String.fromEnvironment('GOOGLE_API_KEY');

  @override
  void initState() {
    super.initState();

    AnalyticsService.initIfAvailable();

    if (_apiKey.isEmpty) {
      _error = "Missing GOOGLE_API_KEY. Run with --dart-define=GOOGLE_API_KEY=...";
      _loading = false;
      return;
    }

    _rec = RecommendationService(places: PlacesService(apiKey: _apiKey));
    _routes = RoutesService(apiKey: _apiKey);
    _profile = ProfileStorage.loadOrDefault();

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
        profile: _profile,
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
        profile: _profile,
        maxItems: 10,
      );

      await PlanStorage.savePlan(plan);

      setState(() {
        _plan = plan;
        _loading = false;
        _error = null;
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
    final lines = _plan.map((p) => "- ${p.name} ${p.type}").join("\n");
    final text = "My Tripco Day Plan ☀️\n\n$lines";
    await AnalyticsService.logShare(_plan.length);
    await Share.share(text);
  }

  void _removeAt(int index) async {
    final id = _plan[index].id;
    setState(() {
      _plan.removeAt(index);
    });
    await AnalyticsService.logRemove(id);
    await PlanStorage.savePlan(_plan);

    final s = S.of(context);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.removed)));
    }
  }

  Future<void> _replaceAt(int index) async {
    if (_pos == null) return;

    final s = S.of(context);
    final current = _plan[index];

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.finding)));

    try {
      final replacement = await _rec.replaceOne(
        lat: _pos!.latitude,
        lng: _pos!.longitude,
        profile: _profile,
        current: current,
        excludeIds: _excludeIds(),
      );

      if (replacement == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.noReplacement)));
        }
        return;
      }

      setState(() {
        _plan[index] = replacement;
      });

      await AnalyticsService.logReplace(current.id);
      await PlanStorage.savePlan(_plan);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.replaced)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Replace failed: $e")));
      }
    }
  }

  void _reorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _plan.removeAt(oldIndex);
      _plan.insert(newIndex, item);
    });
    await PlanStorage.savePlan(_plan);
  }

  void _toggleDone(int index) async {
    final current = _plan[index];
    setState(() {
      _plan[index] = current.copyWith(done: !current.done);
    });
    await PlanStorage.savePlan(_plan);
  }

  Future<void> _toggleFavorite(Place place) async {
    final nowFav = await FavoritesStorage.toggleFavorite(place.id);
    await AnalyticsService.logFavorite(place.id, nowFav);
    setState(() {});
  }

  Future<void> _changeProfile() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => ProfileSheet(
        current: _profile,
        onSelected: (p) async {
          setState(() => _profile = p);
          await ProfileStorage.save(p);
          await AnalyticsService.logProfile(p.name);
          await _startFresh(); // nový plán podle režimu
        },
      ),
    );
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

    return Scaffold(
      appBar: AppBar(
        title: Text(s.dayPlan),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Text(_profile.emoji, style: const TextStyle(fontSize: 20)),
            tooltip: "Change mode",
            onPressed: _changeProfile,
          ),
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
          _SummaryBar(count: _plan.length),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _plan.length,
              onReorder: _reorder,
              itemBuilder: (context, i) {
                final place = _plan[i];
                final isFav = FavoritesStorage.isFavorite(place.id);

                return PlaceCard(
                  key: ValueKey(place.id),
                  place: place,
                  originLat: _pos!.latitude,
                  originLng: _pos!.longitude,
                  routes: _routes,
                  onRemove: () => _removeAt(i),
                  onReplace: () => _replaceAt(i),
                  onToggleDone: () => _toggleDone(i),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
