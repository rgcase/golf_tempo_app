import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:just_audio/just_audio.dart';

typedef SwingSpeed = ({int backswing, int downswing});

class AudioEngine {
  AudioPlayer? _player;
  bool _initialized = false;
  bool _isPlaying = false;
  double _volume = 1.0;
  Duration _gapBetweenCycles = const Duration(seconds: 2);

  StreamSubscription<PlayerState>? _playerStateSub;

  // Current and pending swing speeds
  SwingSpeed? _speed;
  SwingSpeed? _pendingSpeed;

  Future<void> init() async {
    if (_initialized) return;

    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidWillPauseWhenDucked: false,
      ),
    );

    _initialized = true;
  }

  // Kept for compatibility; totalCycle is unused
  Future<void> setTempo({
    required int backswingUnits,
    required int downswingUnits,
    required Duration totalCycle,
  }) async {
    if (!_initialized) {
      await init();
    }
    _speed = (backswing: backswingUnits, downswing: downswingUnits);
    if (_player != null && !_isPlaying) {
      await _applySource();
    }
  }

  // Queue a tempo change to take effect at the next cycle boundary
  Future<void> queueTempoChange({
    required int backswingUnits,
    required int downswingUnits,
    required Duration totalCycle,
  }) async {
    if (!_initialized) {
      await init();
    }
    _pendingSpeed = (backswing: backswingUnits, downswing: downswingUnits);
  }

  void setGap(Duration gap) {
    _gapBetweenCycles = gap;
  }

  Future<void> start() async {
    if (!_initialized) {
      await init();
    }
    if (_speed == null) {
      await setTempo(
        backswingUnits: 21,
        downswingUnits: 7,
        totalCycle: const Duration(milliseconds: 1200),
      );
    }
    if (_isPlaying) return;

    await _disposePlayer();
    _player = AudioPlayer();
    await _player!.setVolume(_volume);

    await _applySource();
    await _player!.setLoopMode(LoopMode.off);

    _playerStateSub = _player!.playerStateStream.listen((state) async {
      if (!_isPlaying) return;
      if (state.processingState == ProcessingState.completed) {
        try {
          await Future.delayed(_gapBetweenCycles);
          if (!_isPlaying || _player == null) return;
          if (_pendingSpeed != null) {
            _speed = _pendingSpeed;
            _pendingSpeed = null;
            await _applySource();
            await _player!.play();
          } else {
            await _player!.seek(Duration.zero, index: 0);
            await _player!.play();
          }
        } catch (_) {}
      }
    });

    await _player!.play();
    _isPlaying = true;
  }

  Future<void> stop() async {
    if (!_initialized) return;
    if (!_isPlaying && _player == null) return;

    _isPlaying = false;
    await _disposePlayer();
  }

  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    _player?.setVolume(_volume);
  }

  bool get isPlaying => _isPlaying;

  bool _isValidPcmWav(Uint8List wav) {
    if (wav.length < 44) return false;
    bool matchTag(int offset, String tag) {
      final bytes = wav.sublist(offset, offset + 4);
      return String.fromCharCodes(bytes) == tag;
    }

    if (!matchTag(0, 'RIFF')) return false;
    if (!matchTag(8, 'WAVE')) return false;
    if (!matchTag(12, 'fmt ')) return false;
    if (!matchTag(36, 'data')) return false;
    return true;
  }

  Future<void> _applySource() async {
    if (_player == null || _speed == null) return;
    final s = _speed!;

    final ratioKey = s.backswing ~/ s.downswing == 3 ? '3to1' : '2to1';
    final assetPath =
        'assets/audio/cycles/${ratioKey}_${s.backswing}_${s.downswing}.wav';

    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    if (!_isValidPcmWav(bytes)) {
      throw StateError('Invalid WAV asset at $assetPath');
    }
    final dir = await Directory.systemTemp.createTemp('golf_tempo_asset');
    final file = File('${dir.path}/cycle.wav');
    await file.writeAsBytes(bytes, flush: true);
    await _player!.setAudioSource(AudioSource.uri(Uri.file(file.path)));
  }

  Future<void> _disposePlayer() async {
    await _playerStateSub?.cancel();
    _playerStateSub = null;
    try {
      await _player?.stop();
    } catch (_) {}
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}
