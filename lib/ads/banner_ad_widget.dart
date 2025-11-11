import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';

class BannerAdWidget extends StatefulWidget {
  final String adUnitId;
  const BannerAdWidget({super.key, required this.adUnitId});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _banner;
  bool _loaded = false;
  String _diag = '';
  bool _scheduled = false;
  static const bool _showDiag = bool.fromEnvironment(
    'ADS_DIAG',
    defaultValue: false,
  );
  static const bool _forceNpa = bool.fromEnvironment(
    'FORCE_NPA',
    defaultValue: false,
  );
  // Allows disabling banners during development on environments that have platform
  // view issues (e.g., some ChromeOS builds).
  static const bool _disableBanners = bool.fromEnvironment(
    'ADS_DISABLE_BANNERS',
    defaultValue: false,
  );

  @override
  void initState() {
    super.initState();
    // Create the banner after first frame to avoid first-frame stalls/crashes
    // on some devices/renderers.
    if (!_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeCreateBanner();
      });
    }
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  void _maybeCreateBanner() {
    if (!mounted) return;
    () async {
      if (_disableBanners) {
        if (_showDiag && mounted) {
          setState(() {
            _diag = 'Banners disabled via ADS_DISABLE_BANNERS';
          });
        }
        return;
      }
      // Disable banners on ChromeOS devices to avoid platform view crashes.
      final bool isChromeOs = await _isChromeOsDevice();
      if (isChromeOs) {
        // ignore: avoid_print
        print('[AdMob] Skipping banner on ChromeOS device');
        if (_showDiag && mounted) {
          setState(() {
            _diag = 'Skipped on ChromeOS';
          });
        }
        return;
      }
      _createBanner();
    }();
  }

  void _createBanner() {
    if (!mounted) return;
    try {
      // ignore: avoid_print
      print('[AdMob] Creating BannerAd with unitId=${widget.adUnitId}');
      if (_showDiag) {
        setState(() {
          _diag = 'Creating banner: ${widget.adUnitId}';
        });
      }
      _banner = BannerAd(
        size: AdSize.banner,
        adUnitId: widget.adUnitId,
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            // ignore: avoid_print
            print('[AdMob] Banner loaded successfully');
            if (!mounted) return;
            setState(() => _loaded = true);
            if (_showDiag) {
              setState(() {
                _diag = 'Loaded banner';
              });
            }
          },
          onAdFailedToLoad: (ad, error) {
            // Helpful for debugging no-fill/config issues
            // ignore: avoid_print
            print(
              '[AdMob] Banner failed to load: code=${error.code} message=${error.message} domain=${error.domain}',
            );
            ad.dispose();
            if (!mounted) return;
            setState(() => _loaded = false);
            if (_showDiag) {
              setState(() {
                _diag = 'Failed: code=${error.code} ${error.message}';
              });
            }
          },
        ),
        request: AdRequest(nonPersonalizedAds: _forceNpa),
      )..load();
    } catch (e) {
      // ignore: avoid_print
      print('[AdMob] Exception creating BannerAd: $e');
      if (_showDiag && mounted) {
        setState(() {
          _diag = 'Exception: $e';
        });
      }
    }
  }

  Future<bool> _isChromeOsDevice() async {
    try {
      if (!Platform.isAndroid) return false;
      final info = await DeviceInfoPlugin().androidInfo;
      final features = info.systemFeatures;
      final bool hasArcFeature = features.any((f) =>
          f.contains('org.chromium.arc') || f.contains('android.hardware.type.pc'));
      final model = info.model.toLowerCase();
      final device = info.device.toLowerCase();
      final product = info.product.toLowerCase();
      final brand = info.brand.toLowerCase();
      final bool chromeish = model.contains('chromebook') ||
          device.contains('cheets') ||
          product.contains('cheets') ||
          brand.contains('chromium');
      return hasArcFeature || chromeish;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final adWidget = (_loaded && _banner != null)
        ? SizedBox(
            height: _banner!.size.height.toDouble(),
            width: _banner!.size.width.toDouble(),
            child: AdWidget(ad: _banner!),
          )
        : const SizedBox.shrink();
    if (!_showDiag) return adWidget;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        adWidget,
        if (_diag.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              _diag,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

// Placeholder removed; use BannerAdWidget above.
