import 'package:flutter/material.dart';
import '../audio/audio_engine.dart';
import '../state/tempo_models.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AudioEngine _engine = AudioEngine();

  bool _isPlaying = false;
  TempoRatio _ratio = TempoRatio.threeToOne;

  Future<void> _start() async {
    if (_isPlaying) return;
    setState(() {
      _isPlaying = true; // optimistic
    });
    try {
      final cfg = _configForRatio(_ratio);
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

  TempoConfig _configForRatio(TempoRatio ratio) {
    switch (ratio) {
      case TempoRatio.threeToOne:
        return const TempoConfig(
          ratio: TempoRatio.threeToOne,
          backswingUnits: 21,
          downswingUnits: 7,
          totalCycle: Duration(milliseconds: 1200),
        );
      case TempoRatio.twoToOne:
        return const TempoConfig(
          ratio: TempoRatio.twoToOne,
          backswingUnits: 20,
          downswingUnits: 10,
          totalCycle: Duration(milliseconds: 1000),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      setState(() => _ratio = TempoRatio.threeToOne);
                    },
                  ),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: const Text('2:1 Short/Putting'),
                    selected: _ratio == TempoRatio.twoToOne,
                    onSelected: (_) {
                      setState(() => _ratio = TempoRatio.twoToOne);
                    },
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
                    Text(
                      'Ratio: ${_ratio == TempoRatio.threeToOne ? '3:1' : '2:1'}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
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
}
