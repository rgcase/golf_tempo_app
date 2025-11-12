import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;
import 'package:duration/duration.dart';
import 'package:golf_tempo_app/env/env.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';
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
  // Default to forced override if provided so we don't build the ad widget at all.
  bool _adsRemoved = Env.adsRemovedOverride;
  ProductDetails? _removeAdsProduct;
  bool _purchaseInProgress = false;

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

  Widget _tempoSegmented(List<SwingSpeed> presets) {
    final segments = presets
        .map(
          (p) => ButtonSegment<SwingSpeed>(
            value: p,
            label: Text(
              '${p.backswing}:${p.downswing}',
              maxLines: 1,
              softWrap: false,
            ),
          ),
        )
        .toList(growable: false);
    return SegmentedButton<SwingSpeed>(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 8),
        ),
        textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 14)),
      ),
      segments: segments,
      selected: <SwingSpeed>{_selectedPreset},
      onSelectionChanged: (s) async {
        final p = s.first;
        setState(() {
          _selectedPreset = p;
          if (_ratio == TempoRatio.threeToOne) {
            _selectedThreeToOne = p;
          } else {
            _selectedTwoToOne = p;
          }
        });
        _savePrefs();
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

  Widget _gapSegmented() {
    final options = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
    ];
    final segments = options
        .map(
          (d) => ButtonSegment<Duration>(
            value: d,
            label: Text(prettyDuration(d, abbreviated: true, spacer: '')),
          ),
        )
        .toList(growable: false);
    return SegmentedButton<Duration>(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 8),
        ),
        textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 14)),
      ),
      segments: segments,
      selected: <Duration>{_gap},
      onSelectionChanged: (s) {
        final d = s.first;
        setState(() => _gap = d);
        _engine.setGap(d);
        _savePrefs();
      },
    );
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
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _adsRemoved = _iap.adsRemoved;
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
                onPressed: _purchaseInProgress
                    ? null
                    : () async {
                        setState(() => _purchaseInProgress = true);
                        try {
                          final started = await _iap.buyRemoveAds(product);
                          // Give the purchase stream a moment to deliver events.
                          if (started) {
                            await Future.delayed(
                              const Duration(milliseconds: 300),
                            );
                          }
                          if (!mounted) return;
                          setState(() => _adsRemoved = _iap.adsRemoved);
                          if (_adsRemoved && mounted) {
                            Navigator.of(ctx).pop();
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _purchaseInProgress = false);
                          }
                        }
                      },
                child: _purchaseInProgress
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Buy for ${product.price}'),
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
    const forceTest = Env.forceTestAds;
    // Allow using real units in Profile via --dart-define=FORCE_REAL_ADS=true.
    const forceReal = Env.forceRealAds;
    if (Platform.isIOS) {
      return Env.iosBannerUnitId;
    }
    if (Platform.isAndroid) {
      const test = 'ca-app-pub-3940256099942544/6300978111';
      if (forceTest) return test;
      if (kReleaseMode || forceReal) {
        const real = Env.androidBannerUnitId;
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
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'About',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _openAbout(context),
          ),
        ],
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('logo.png', height: 22),
            const SizedBox(width: 8),
            const Text('SwingGroove Golf'),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _sectionCard(title: 'Mode', child: _ratioSegmented()),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _sectionCard(
                title: 'Tempo',
                child: _tempoSegmented(presets),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _sectionCard(title: 'Sound', child: _soundSegmented()),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _sectionCard(
                title: 'Interval between cycles',
                child: _gapSegmented(),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: const StadiumBorder(),
                        elevation: 2,
                      ),
                      icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                      label: Text(_isPlaying ? 'Stop' : 'Start'),
                      onPressed: () {
                        _isPlaying ? _stop() : _start();
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_systemVolume == 0.0) _inlineVolumeWarning(context),
                  if (Env.screenshotMode && (!kReleaseMode || Env.forceTestAds))
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
            const SizedBox(height: 12),
            // Ad banner and support link (hidden if purchased)
            if (!_adsRemoved) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Center(
                  child: BannerAdWidget(adUnitId: _bannerAdUnitId()),
                ),
              ),
              TextButton.icon(
                onPressed: _showRemoveAdsDialog,
                icon: const Icon(Icons.volunteer_activism),
                label: const Text(
                  'Support development and remove ads forever?',
                ),
              ),
              const SizedBox(height: 8),
            ] else ...[
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text('Thanks for supporting! Ads are disabled.'),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _sectionIconFor(title),
                const SizedBox(width: 6),
                Text(title, style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 6),
            Align(alignment: Alignment.center, child: child),
          ],
        ),
      ),
    );
  }

  Widget _sectionIconFor(String title) {
    switch (title) {
      case 'Mode':
        return const Icon(Icons.golf_course, size: 18);
      case 'Tempo':
        return const Icon(Icons.speed, size: 18);
      case 'Sound':
        return const Icon(Icons.music_note, size: 18);
      case 'Interval between cycles':
        return const Icon(Icons.timer, size: 18);
      default:
        return const Icon(Icons.tune, size: 18);
    }
  }

  Widget _ratioSegmented() {
    return SegmentedButton<TempoRatio>(
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: const [
        ButtonSegment(
          value: TempoRatio.threeToOne,
          label: Text('3:1 Full Swing'),
        ),
        ButtonSegment(
          value: TempoRatio.twoToOne,
          label: Text('2:1 Short Game & Putting'),
        ),
      ],
      selected: <TempoRatio>{_ratio},
      onSelectionChanged: (s) {
        final sel = s.first;
        setState(() {
          _ratio = sel;
          _selectedPreset = sel == TempoRatio.threeToOne
              ? _selectedThreeToOne
              : _selectedTwoToOne;
        });
        _savePrefs();
      },
    );
  }

  Widget _soundSegmented() {
    return SegmentedButton<SoundSet>(
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: const [
        ButtonSegment(value: SoundSet.tones, label: Text('Tones')),
        ButtonSegment(value: SoundSet.woodblock, label: Text('Wood Block')),
        ButtonSegment(value: SoundSet.piano, label: Text('Piano')),
      ],
      selected: <SoundSet>{_soundSet},
      onSelectionChanged: (s) async {
        final sel = s.first;
        setState(() => _soundSet = sel);
        _savePrefs();
        final key = _toSetKey(sel);
        if (_isPlaying) {
          await _engine.queueSoundSetChange(key);
        } else {
          await _engine.setSoundSet(key);
          final cfg = _configForSelection();
          await _engine.playPreviewPulse(
            soundSet: key,
            backswingUnits: cfg.backswingUnits,
            downswingUnits: cfg.downswingUnits,
          );
        }
      },
    );
  }

  Widget _inlineVolumeWarning(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.volume_off, size: 18),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'System volume is muted. Increase volume to hear tones.',
            ),
          ),
        ],
      ),
    );
  }

  void _openAbout(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const _AboutScreen()));
  }

  // _gapChip removed in favor of segmented control.

  // _soundChip removed in favor of segmented control.

  // _tempoChip removed in favor of segmented control.
}

class _AboutScreen extends StatelessWidget {
  const _AboutScreen();

  Future<String> _getVersion() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      return '${pkg.version}+${pkg.buildNumber}';
    } catch (_) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: FutureBuilder<String>(
        future: _getVersion(),
        builder: (context, snapshot) {
          final version = snapshot.data ?? '';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                leading: const Icon(Icons.apps),
                title: const Text('SwingGroove Golf'),
                subtitle: Text('Version $version'),
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Source code on GitHub'),
                subtitle: const Text('github.com/rgcase/golf_tempo_app'),
                onTap: () => launchUrlString(
                  'https://github.com/rgcase/golf_tempo_app',
                  mode: LaunchMode.externalApplication,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy Policy'),
                subtitle: const Text(
                  'github.com/rgcase/golf_tempo_app/PRIVACY.md',
                ),
                onTap: () => launchUrlString(
                  'https://github.com/rgcase/golf_tempo_app/blob/main/PRIVACY.md',
                  mode: LaunchMode.externalApplication,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Open-source licenses'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const _LicensesListPage()),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LicensesListPage extends StatelessWidget {
  const _LicensesListPage();

  Future<List<dynamic>> _loadLicenses() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/oss_licenses.json');
      final data = jsonDecode(jsonStr) as List<dynamic>;
      return data;
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Licenses')),
      body: FutureBuilder<List<dynamic>>(
        future: _loadLicenses(),
        builder: (context, snapshot) {
          final licenses = snapshot.data ?? const [];
          if (licenses.isEmpty) {
            return const Center(child: Text('No license data found.'));
          }
          return ListView.separated(
            itemCount: licenses.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = licenses[index] as Map<String, dynamic>;
              final name = item['name'] as String? ?? '';
              final license = item['license'] as String? ?? '';
              final version = item['version'] as String? ?? '';
              return ExpansionTile(
                title: Text(name),
                subtitle: Text(version),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(license),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
