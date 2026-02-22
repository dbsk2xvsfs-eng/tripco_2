import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
// volitelné:
import 'package:firebase_core/firebase_core.dart';

import 'screens/day_plan_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await Hive.openBox('tripcoBox');

  // Firebase je volitelný: pokud nemáš nastavený firebase project v appce,
  // zakomentuj tyto 2 řádky a app pojede dál.
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // ignore - allow running without firebase setup
  }

  runApp(const TripcoApp());
}

class TripcoApp extends StatelessWidget {
  const TripcoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tripco',
      debugShowCheckedModeBanner: false,
      supportedLocales: const [
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const DayPlanScreen(),
    );
  }
}
