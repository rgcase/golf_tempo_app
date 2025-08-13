import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  runApp(const GolfTempoApp());
}

class GolfTempoApp extends StatelessWidget {
  const GolfTempoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SwingGroove Golf',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
