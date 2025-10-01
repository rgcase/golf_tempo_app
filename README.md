# SwingGroove Golf

A simple, precise tempo trainer for golf. It provides three-beat tempo cues (Full Swing 3:1 and Short/Putting 2:1), multiple sound sets (Tones, Woodblock, Piano), optional gaps between cycles, banner ads with an in-app purchase to remove ads forever, and an About page listing third-party licenses.

## Features
- 3:1 and 2:1 tempo presets with common frame pairs (e.g., 21:7).
- Sound sets: Tones, Woodblock, and refined Piano samples.
- Interval between cycles: 2s, 5s, 15s, 30s.
- System volume awareness with inline muted-volume warning.
- Banner ads via AdMob with in-app purchase to remove ads.
- Debug Ad Inspector shortcut (debug/test builds only).
- Portrait-only UI with native splash.
- Dark mode and a build-time theme override.
- About page with version and OSS licenses (generated via flutter_oss_licenses).

## App architecture
- UI: `lib/ui/home_screen.dart`
- Audio engine: `lib/audio/audio_engine.dart` (loops pre-baked cycle WAVs)
- IAP (iOS implementation): `lib/iap/ios_iap_service_impl.dart` implements `lib/iap/iap_service.dart`
- Ads: `lib/ads/banner_ad_widget.dart`
- Entry: `lib/main.dart`
- Audio tools: `tools/generate_audio.dart`, `tools/make_piano_samples.sh`, `tools/check_tempos.py`

## Build and run
Prereqs: Flutter stable + platform toolchains.

```bash
flutter pub get
flutter run
```

### Useful --dart-define overrides
- `ADS_REMOVED_OVERRIDE=true|false` – force ads removed (override IAP).
- `THEME_MODE_OVERRIDE=system|light|dark` – force theme.
- `FORCE_TEST_ADS=true` – always use test ad units.
- `FORCE_REAL_ADS=true` – allow real ad units in non-release (use carefully).
- `ADMOB_TEST_DEVICE_ID=XXXX` – register AdMob test device ID.
- `ADMOB_BANNER_IOS=ca-app-pub-.../...` – real iOS banner unit.
- `ADMOB_BANNER_ANDROID=ca-app-pub-.../...` – real Android banner unit.

Examples:
```bash
flutter run \
  --dart-define=ADS_REMOVED_OVERRIDE=true \
  --dart-define=THEME_MODE_OVERRIDE=dark

flutter build ios --release \
  --dart-define=THEME_MODE_OVERRIDE=light \
  --dart-define=FORCE_REAL_ADS=true
```

## AdMob configuration (kept out of VCS)
- iOS: create `ios/Runner/Configs/Secrets.xcconfig`:
```
GAD_APPLICATION_IDENTIFIER = <your-ios-admob-app-id>
ADMOB_BANNER_IOS = <your-ios-banner-ad-unit>
```
- Android: add to `android/local.properties`:
```
ADMOB_APP_ID_ANDROID=<your-android-admob-app-id>
ADMOB_BANNER_ANDROID=<your-android-banner-ad-unit>
```

## In-app purchase (Remove Ads)
- iOS non-consumable via `in_app_purchase`.
- Example product ID: `dev.golfapp.swinggroove.remove_ads`.

## Audio assets & developer tools
- Pre-baked cycle WAVs in `assets/audio/cycles/...`.
- Generate/refine: `dart run tools/generate_audio.dart`
- Make piano samples: `tools/make_piano_samples.sh`
- Verify timing: `python tools/check_tempos.py`

## Licenses
Generate OSS licenses list:
```bash
dart run flutter_oss_licenses:generate --json
```
This writes `assets/oss_licenses.json`, which the app reads for the About page.

## Privacy
- Uses Google Mobile Ads SDK. Add a consent flow if required (e.g., UMP).

## Troubleshooting
- "No ad to show" in release: new ad units often have no fill; use test ads or wait for review/traffic.
- StoreKit product not returned: verify product setup and sandbox tester on device.
- Assets stale: `flutter clean && flutter pub get`.

## Contributing
Issues and PRs are welcome. Please keep changes small and focused.

## License
MIT License. See `LICENSE`.
