import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ui/home_screen.dart';
import 'consent/consent_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Request UMP consent (best-effort) before initializing ads.
  final consent = ConsentManager();
  // Fire and forget; do not block app startup excessively.
  consent.requestConsentIfNeeded();
  // Optionally register a test device ID when provided via --dart-define.
  const testDeviceId = String.fromEnvironment('ADMOB_TEST_DEVICE_ID');
  if (testDeviceId.isNotEmpty) {
    MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: [testDeviceId]),
    );
  }
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
