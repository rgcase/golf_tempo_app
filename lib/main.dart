import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ui/home_screen.dart';
import 'consent/consent_manager.dart';

ThemeMode _parseThemeModeOverride(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return ThemeMode.system;
  if (s == 'dark' || s == 'true' || s == '1') return ThemeMode.dark;
  if (s == 'light' || s == 'false' || s == '0') return ThemeMode.light;
  if (s == 'system') return ThemeMode.system;
  return ThemeMode.system;
}

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
    final lightScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7D32),
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7D32),
      brightness: Brightness.dark,
    );
    const themeOverrideRaw = String.fromEnvironment('THEME_MODE_OVERRIDE');
    final mode = _parseThemeModeOverride(themeOverrideRaw);
    if (kDebugMode && themeOverrideRaw.isNotEmpty) {
      debugPrint(
        'Theme override: THEME_MODE_OVERRIDE=$themeOverrideRaw -> $mode',
      );
    }
    return MaterialApp(
      title: 'SwingGroove Golf',
      theme: ThemeData(colorScheme: lightScheme, useMaterial3: true),
      darkTheme: ThemeData(colorScheme: darkScheme, useMaterial3: true),
      themeMode: mode,
      home: const HomeScreen(),
    );
  }
}
