import 'package:flutter/material.dart';
import 'package:duration/duration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../audio/audio_engine.dart';
import '../state/tempo_models.dart';

typedef SwingSpeed = ({int backswing, int downswing});

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AudioEngine _engine = AudioEngine();

  bool _isPlaying = false;
  TempoRatio _ratio = TempoRatio.threeToOne;
  Duration _gap = const Duration(seconds: 2);

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

    setState(() {
      _ratio = r;
      _selectedThreeToOne = (backswing: t31b, downswing: t31d);
      _selectedTwoToOne = (backswing: t21b, downswing: t21d);
      _selectedPreset = _ratio == TempoRatio.threeToOne
          ? _selectedThreeToOne
          : _selectedTwoToOne;
      _gap = Duration(milliseconds: gapMs);
    });
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
  }

  Future<void> _start() async {
    if (_isPlaying) return;
    setState(() {
      _isPlaying = true; // optimistic
    });
    try {
      _engine.setGap(_gap);
      final cfg = _configForSelection();
      await _engine.setTempo(
        backswingUnits: cfg.backswingUnits,
        downswingUnits: cfg.downswingUnits,
        totalCycle: cfg.totalCycle,
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
    final totalFrames = backswing + downswing;
    final totalMs = Duration(
      milliseconds: ((totalFrames / 30.0) * 1000).round(),
    );
    return TempoConfig(
      ratio: _ratio,
      backswingUnits: backswing,
      downswingUnits: downswing,
      totalCycle: totalMs,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<SwingSpeed> presets = _ratio == TempoRatio.threeToOne
        ? _threeToOnePresets
        : _twoToOnePresets;
    return Scaffold(
      appBar: AppBar(title: const Text('Golf Tempo')),
      body: SafeArea(
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
                  const Text('Swing speed'),
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
                  const Text('Interval between cycles'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final d in [2, 5, 15, 30])
                        _gapChip(Duration(seconds: d)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                      label: Text(_isPlaying ? 'Stop' : 'Start'),
                      onPressed: () {
                        _isPlaying ? _stop() : _start();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
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
            totalCycle: cfg.totalCycle,
          );
        }
      },
    );
  }
}
