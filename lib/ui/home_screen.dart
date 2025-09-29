import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;
import 'package:duration/duration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../audio/audio_engine.dart';
import '../state/tempo_models.dart';
import '../ads/banner_ad_widget.dart';
import '../iap/iap_service.dart';
import '../iap/ios_iap_service_impl.dart';

typedef SwingSpeed = ({int backswing, int downswing});

enum SoundSet { tones, woodblock, piano }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AudioEngine _engine = AudioEngine();
  final IapService _iap = IosIapServiceImpl();

  bool _isPlaying = false;
  double _systemVolume = 1.0;
  TempoRatio _ratio = TempoRatio.threeToOne;
  Duration _gap = const Duration(seconds: 2);
  SoundSet _soundSet = SoundSet.tones;
  bool _adsRemoved = false;
  ProductDetails? _removeAdsProduct;
  bool _iapReady = false;

  // Frame presets
  final List<SwingSpeed> _threeToOnePresets = const <SwingSpeed>[
    (backswing: 18, downswing: 6),
    (backswing: 21, downswing: 7),
    (backswing: 24, downswing: 8),
    (backswing: 27, downswing: 9),
    (backswing: 30, downswing: 10),
  ];
  final List<SwingSpeed> _twoToOnePresets = const <SwingSpeed>[
    (backswing: 14, downswing: 7),
    (backswing: 16, downswing: 8),
    (backswing: 18, downswing: 9),
    (backswing: 20, downswing: 10),
    (backswing: 22, downswing: 11),
  ];

  // Last-selected presets per ratio
  SwingSpeed _selectedThreeToOne = (backswing: 21, downswing: 7);
  SwingSpeed _selectedTwoToOne = (backswing: 16, downswing: 8);

  // Current selection
  SwingSpeed _selectedPreset = (backswing: 21, downswing: 7);

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _initVolumeListener();
    _initIap();
  }

  Future<void> _initVolumeListener() async {
    try {
      final v = await FlutterVolumeController.getVolume();
      setState(() => _systemVolume = (v ?? _systemVolume));
    } catch (_) {}
    FlutterVolumeController.addListener((v) {
      if (!mounted) return;
      setState(() => _systemVolume = v);
    });
  }

  @override
  void dispose() {
    FlutterVolumeController.removeListener();
    _iap.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRatio = prefs.getString('ratio');
    final r = savedRatio == '2to1'
        ? TempoRatio.twoToOne
        : TempoRatio.threeToOne;

    final t31b = prefs.getInt('t31_b') ?? 21;
    final t31d = prefs.getInt('t31_d') ?? 7;
    final t21b = prefs.getInt('t21_b') ?? 16;
    final t21d = prefs.getInt('t21_d') ?? 8;
    final gapMs = prefs.getInt('gap_ms') ?? 2000;
    final setKey = prefs.getString('sound_set') ?? 'tones';

    setState(() {
      _ratio = r;
      _selectedThreeToOne = (backswing: t31b, downswing: t31d);
      _selectedTwoToOne = (backswing: t21b, downswing: t21d);
      _selectedPreset = _ratio == TempoRatio.threeToOne
          ? _selectedThreeToOne
          : _selectedTwoToOne;
      _gap = Duration(milliseconds: gapMs);
      _soundSet = _fromSetKey(setKey);
    });
  }

  Future<void> _initIap() async {
    await _iap.init();
    if (!mounted) return;
    try {
      final product = await _iap.loadRemoveAdsProduct();
      if (!mounted) return;
      setState(() {
        _adsRemoved = _iap.adsRemoved;
        _removeAdsProduct = product;
        _iapReady = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _adsRemoved = _iap.adsRemoved;
        _iapReady = true;
      });
    }
  }

  Future<void> _showRemoveAdsDialog() async {
    final product = _removeAdsProduct ?? await _iap.loadRemoveAdsProduct();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final priceLabel = product?.price ?? '';
        return AlertDialog(
          title: const Text('Remove ads forever'),
          content: product == null
              ? const Text(
                  'In-app purchases are currently unavailable. Please try again later.',
                )
              : Text('Pay $priceLabel one time to remove ads permanently.'),
          actions: [
            TextButton(
              onPressed: () async {
                await _iap.restore();
                await Future.delayed(const Duration(milliseconds: 300));
                if (!mounted) return;
                setState(() => _adsRemoved = _iap.adsRemoved);
                if (mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Restore Purchases'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            if (product != null)
              ElevatedButton(
                onPressed: () async {
                  await _iap.buyRemoveAds(product);
                  await Future.delayed(const Duration(milliseconds: 300));
                  if (!mounted) return;
                  setState(() => _adsRemoved = _iap.adsRemoved);
                  if (mounted) Navigator.of(ctx).pop();
                },
                child: Text('Buy for ${product.price}'),
              ),
          ],
        );
      },
    );
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'ratio',
      _ratio == TempoRatio.threeToOne ? '3to1' : '2to1',
    );
    await prefs.setInt('t31_b', _selectedThreeToOne.backswing);
    await prefs.setInt('t31_d', _selectedThreeToOne.downswing);
    await prefs.setInt('t21_b', _selectedTwoToOne.backswing);
    await prefs.setInt('t21_d', _selectedTwoToOne.downswing);
    await prefs.setInt('gap_ms', _gap.inMilliseconds);
    await prefs.setString('sound_set', _toSetKey(_soundSet));
  }

  String _toSetKey(SoundSet s) => switch (s) {
    SoundSet.tones => 'tones',
    SoundSet.woodblock => 'woodblock',
    SoundSet.piano => 'piano',
  };
  SoundSet _fromSetKey(String k) => switch (k) {
    'woodblock' => SoundSet.woodblock,
    'piano' => SoundSet.piano,
    _ => SoundSet.tones,
  };

  Future<void> _start() async {
    if (_isPlaying) return;
    setState(() {
      _isPlaying = true; // optimistic
    });
    try {
      _engine.setGap(_gap);
      await _engine.setSoundSet(_toSetKey(_soundSet));
      final cfg = _configForSelection();
      await _engine.setTempo(
        backswingUnits: cfg.backswingUnits,
        downswingUnits: cfg.downswingUnits,
      );
      await _engine.start();
    } catch (_) {
      setState(() {
        _isPlaying = false;
      });
    } finally {
      setState(() {
        _isPlaying = _engine.isPlaying;
      });
    }
  }

  Future<void> _stop() async {
    if (!_isPlaying) return;
    setState(() {
      _isPlaying = false; // optimistic
    });
    try {
      await _engine.stop();
    } finally {
      setState(() {
        _isPlaying = _engine.isPlaying;
      });
    }
  }

  TempoConfig _configForSelection() {
    final backswing = _selectedPreset.backswing;
    final downswing = _selectedPreset.downswing;
    return TempoConfig(
      ratio: _ratio,
      backswingUnits: backswing,
      downswingUnits: downswing,
    );
  }

  String _bannerAdUnitId() {
    const forceTest = bool.fromEnvironment(
      'FORCE_TEST_ADS',
      defaultValue: false,
    );
    // Allow using real units in Profile via --dart-define=FORCE_REAL_ADS=true.
    const forceReal = bool.fromEnvironment(
      'FORCE_REAL_ADS',
      defaultValue: false,
    );
    if (Platform.isIOS) {
      const test = 'ca-app-pub-3940256099942544/2934735716';
      if (forceTest) return test;
      if (kReleaseMode || forceReal) {
        const real = String.fromEnvironment('ADMOB_BANNER_IOS');
        return real.isEmpty ? test : real;
      }
      return test;
    }
    if (Platform.isAndroid) {
      const test = 'ca-app-pub-3940256099942544/6300978111';
      if (forceTest) return test;
      if (kReleaseMode || forceReal) {
        const real = String.fromEnvironment('ADMOB_BANNER_ANDROID');
        return real.isEmpty ? test : real;
      }
      return test;
    }
    return '';
  }

  Future<void> _openAdInspector() async {
    try {
      MobileAds.instance.openAdInspector((error) {
        if (!mounted) return;
        final message = error == null
            ? 'Ad Inspector closed.'
            : 'Ad Inspector error: ${error.message}';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final List<SwingSpeed> presets = _ratio == TempoRatio.threeToOne
        ? _threeToOnePresets
        : _twoToOnePresets;
    return Scaffold(
      appBar: AppBar(title: const Text('SwingGroove Golf')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('3:1 Full Swing'),
                      selected: _ratio == TempoRatio.threeToOne,
                      onSelected: (_) {
                        setState(() {
                          _ratio = TempoRatio.threeToOne;
                          _selectedPreset = _selectedThreeToOne;
                        });
                        _savePrefs();
                      },
                    ),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text('2:1 Short/Putting'),
                      selected: _ratio == TempoRatio.twoToOne,
                      onSelected: (_) {
                        setState(() {
                          _ratio = TempoRatio.twoToOne;
                          _selectedPreset = _selectedTwoToOne;
                        });
                        _savePrefs();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text('Tempo'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [for (final p in presets) _tempoChip(p)],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text('Sound'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _soundChip(SoundSet.tones, 'Tones'),
                        _soundChip(SoundSet.woodblock, 'Woodblock'),
                        _soundChip(SoundSet.piano, 'Piano'),
                        // Golf removed
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text('Interval between cycles'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _gapChip(const Duration(seconds: 2)),
                        _gapChip(const Duration(seconds: 5)),
                        _gapChip(const Duration(seconds: 15)),
                        _gapChip(const Duration(seconds: 30)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ratio: ${_ratio == TempoRatio.threeToOne ? '3:1' : '2:1'}  •  ${_selectedPreset.backswing}:${_selectedPreset.downswing}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                      label: Text(_isPlaying ? 'Stop' : 'Start'),
                      onPressed: () {
                        _isPlaying ? _stop() : _start();
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'System volume is muted. Increase volume to hear tones.',
                      style: TextStyle(
                        color: _systemVolume == 0.0 ? Colors.red : Colors.white,
                      ),
                    ),
                    if (!kReleaseMode ||
                        const bool.fromEnvironment(
                          'FORCE_TEST_ADS',
                          defaultValue: false,
                        ))
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: OutlinedButton(
                          onPressed: _openAdInspector,
                          child: const Text('Open Ad Inspector'),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Ad banner and support link (hidden if purchased)
              if (!_adsRemoved) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Center(
                    child: BannerAdWidget(adUnitId: _bannerAdUnitId()),
                  ),
                ),
                TextButton(
                  onPressed: _showRemoveAdsDialog,
                  child: const Text(
                    'Support development and remove ads forever?',
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text('Thanks for supporting! Ads are disabled.'),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _gapChip(Duration d) {
    final selected = _gap == d;
    return ChoiceChip(
      label: Text(prettyDuration(d, abbreviated: true, spacer: '')),
      selected: selected,
      onSelected: (_) {
        setState(() => _gap = d);
        _engine.setGap(d);
        _savePrefs();
      },
    );
  }

  Widget _soundChip(SoundSet set, String label) {
    final selected = _soundSet == set;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) async {
        setState(() => _soundSet = set);
        _savePrefs();
        final key = _toSetKey(set);
        if (_isPlaying) {
          await _engine.queueSoundSetChange(key);
        } else {
          await _engine.setSoundSet(key);
        }
      },
    );
  }

  Widget _tempoChip(SwingSpeed p) {
    final selected =
        _selectedPreset.backswing == p.backswing &&
        _selectedPreset.downswing == p.downswing;
    return ChoiceChip(
      label: Text('${p.backswing}:${p.downswing}'),
      selected: selected,
      onSelected: (_) async {
        setState(() {
          _selectedPreset = p;
          if (_ratio == TempoRatio.threeToOne) {
            _selectedThreeToOne = p;
          } else {
            _selectedTwoToOne = p;
          }
        });
        _savePrefs();

        // If currently playing, queue change for next cycle
        if (_isPlaying) {
          final cfg = _configForSelection();
          await _engine.queueTempoChange(
            backswingUnits: cfg.backswingUnits,
            downswingUnits: cfg.downswingUnits,
          );
        }
      },
    );
  }
}
