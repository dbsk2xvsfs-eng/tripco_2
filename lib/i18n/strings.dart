import 'package:flutter/material.dart';

class S {
  final Locale locale;
  S(this.locale);

  static S of(BuildContext context) => S(Localizations.localeOf(context));

  static const _t = {
    "en": {
      "dayPlan": "Your Day Plan 📌",
      "locationNeeded": "Location access needed 📍",
      "refresh": "Refresh plan",
      "startFresh": "Start fresh",
      "share": "Share plan",
      "finding": "Finding a better spot… ✨",
      "replaced": "Replaced! 🚀",
      "removed": "Removed 😌",
      "noReplacement": "No good replacement found nearby 😅",
      "chooseRide": "From GPS • choose your ride 🧭",
      "timesReal": "Times are real (Routes API). Prices are estimates (MVP).",
      "markDone": "Mark done",
      "done": "Done ✅",
      "navigate": "Navigate 🚀",
      "entry": "Entry",
      "open": "🟢 Open",
      "closed": "🔴 Closed",
      "todaySpots": "Today",
      "mode": "Mode",
      "travelWith": "Who are you traveling with? ✨",
      "tailor": "We’ll tailor your day plan to this mode.",
      "saved": "Saved ⭐",
      "unsaved": "Save ⭐",
    },
  };

  String _get(String key) {
    final lang = _t.containsKey(locale.languageCode) ? locale.languageCode : "en";
    return _t[lang]![key] ?? _t["en"]![key] ?? key;
  }

  String get dayPlan => _get("dayPlan");
  String get locationNeeded => _get("locationNeeded");
  String get refresh => _get("refresh");
  String get startFresh => _get("startFresh");
  String get share => _get("share");
  String get finding => _get("finding");
  String get replaced => _get("replaced");
  String get removed => _get("removed");
  String get noReplacement => _get("noReplacement");
  String get chooseRide => _get("chooseRide");
  String get timesReal => _get("timesReal");
  String get markDone => _get("markDone");
  String get done => _get("done");
  String get navigate => _get("navigate");
  String get entry => _get("entry");
  String get open => _get("open");
  String get closed => _get("closed");
  String get todaySpots => _get("todaySpots");
  String get mode => _get("mode");
  String get travelWith => _get("travelWith");
  String get tailor => _get("tailor");
  String get saved => _get("saved");
  String get unsaved => _get("unsaved");
}
