import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'ui/home_screen.dart';
import 'consent/consent_manager.dart';

// Compile-time switch to enable a clean UI for screenshots on simulators/devices.
// Use: flutter run --dart-define=SCREENSHOT_MODE=true
const bool _kScreenshotMode = bool.fromEnvironment(
  'SCREENSHOT_MODE',
  defaultValue: false,
);

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
  // Required for StoreKit purchases to succeed on iOS.
  InAppPurchase.instance.enablePendingPurchases();
  // Hide iOS status bar when taking clean screenshots.
  if (_kScreenshotMode) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  }
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
      // Hide the top-right "DEBUG" banner when screenshot mode is enabled.
      debugShowCheckedModeBanner: kDebugMode && !_kScreenshotMode,
      home: const HomeScreen(),
    );
  }
}
