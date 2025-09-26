import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

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
  static const bool _showDiag = bool.fromEnvironment(
    'ADS_DIAG',
    defaultValue: false,
  );
  static const bool _forceNpa = bool.fromEnvironment(
    'FORCE_NPA',
    defaultValue: false,
  );

  @override
  void initState() {
    super.initState();
    // ignore: avoid_print
    print('[AdMob] Creating BannerAd with unitId=${widget.adUnitId}');
    if (_showDiag) {
      _diag = 'Creating banner: ${widget.adUnitId}';
    }
    _banner = BannerAd(
      size: AdSize.banner,
      adUnitId: widget.adUnitId,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          // ignore: avoid_print
          print('[AdMob] Banner loaded successfully');
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
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
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
