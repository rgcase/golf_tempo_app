import 'dart:async';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart' as ap;

typedef SwingSpeed = ({int backswing, int downswing});

class AudioEngine {
  ap.AudioPlayer? _player;
  bool _initialized = false;
  bool _isPlaying = false;
  double _volume = 1.0;
  Duration _gapBetweenCycles = const Duration(seconds: 2);
  bool _didInitialRamp = false;

  StreamSubscription<void>? _onCompleteSub;

  // Current and pending swing speeds
  SwingSpeed? _speed;
  SwingSpeed? _pendingSpeed;

  // Current and pending sound set: 'tones' | 'woodblock' | 'piano' | 'golf'
  String _soundSet = 'tones';
  String? _pendingSoundSet;

  String? _currentAssetPath;

  Future<void> init() async {
    if (_initialized) return;
    debugPrint('[AudioEngine] init()');

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
    debugPrint('[AudioEngine] init done');
  }

  Future<void> setTempo({
    required int backswingUnits,
    required int downswingUnits,
  }) async {
    if (!_initialized) {
      await init();
    }
    _speed = (backswing: backswingUnits, downswing: downswingUnits);
    debugPrint('[AudioEngine] setTempo speed=$_speed isPlaying=$_isPlaying');
    if (_player != null && !_isPlaying) {
      await _applySource();
    }
  }

  Future<void> queueTempoChange({
    required int backswingUnits,
    required int downswingUnits,
  }) async {
    if (!_initialized) {
      await init();
    }
    _pendingSpeed = (backswing: backswingUnits, downswing: downswingUnits);
    debugPrint('[AudioEngine] queued tempo change -> $_pendingSpeed');
  }

  Future<void> setSoundSet(String soundSet) async {
    if (!_initialized) await init();
    _soundSet = soundSet;
    debugPrint(
      '[AudioEngine] setSoundSet soundSet=$_soundSet isPlaying=$_isPlaying',
    );
    if (_player != null && !_isPlaying) {
      await _applySource();
    }
  }

  Future<void> queueSoundSetChange(String soundSet) async {
    if (!_initialized) await init();
    _pendingSoundSet = soundSet;
    debugPrint('[AudioEngine] queued sound set change -> $_pendingSoundSet');
  }

  void setGap(Duration gap) {
    _gapBetweenCycles = gap;
    debugPrint('[AudioEngine] setGap gap=$_gapBetweenCycles');
  }

  Future<void> start() async {
    debugPrint(
      '[AudioEngine] start() begin initialized=$_initialized speed=$_speed',
    );
    if (!_initialized) {
      await init();
    }
    if (_speed == null) {
      await setTempo(backswingUnits: 21, downswingUnits: 7);
    }
    if (_isPlaying) {
      debugPrint('[AudioEngine] start() ignored because already playing');
      return;
    }

    await _disposePlayer();
    // Warm up hardware on a separate short-lived player to avoid iOS AVPlayer issues.
    await _primeHardware();

    _player = ap.AudioPlayer();
    // Start at near-silent volume to avoid an initial click, then ramp up.
    await _player!.setVolume(_didInitialRamp ? _volume : 0.0);
    await _player!.setReleaseMode(ap.ReleaseMode.stop);

    await _applySource();

    _onCompleteSub = _player!.onPlayerComplete.listen((_) async {
      debugPrint('[AudioEngine] onComplete, waiting gap=$_gapBetweenCycles');
      await Future.delayed(_gapBetweenCycles);
      if (!_isPlaying || _player == null) return;

      // Apply pending changes (take effect on the very next iteration)
      if (_pendingSoundSet != null || _pendingSpeed != null) {
        if (_pendingSoundSet != null) {
          _soundSet = _pendingSoundSet!;
          _pendingSoundSet = null;
        }
        if (_pendingSpeed != null) {
          _speed = _pendingSpeed;
          _pendingSpeed = null;
        }
        await _applySource();
        if (_currentAssetPath != null) {
          await _player!.play(ap.AssetSource(_currentAssetPath!));
        } else {
          await _player!.resume();
        }
      } else {
        // Restart same asset
        await _player!.seek(Duration.zero);
        // resume may be ignored if player is stopped; call play with source again
        if (_currentAssetPath != null) {
          await _player!.play(ap.AssetSource(_currentAssetPath!));
        } else {
          await _player!.resume();
        }
      }
    });

    try {
      // Prime iOS/Android audio output path with a short silent buffer to avoid
      // hardware activation pops before the first real tone.
      await _primeHardware();
      if (_currentAssetPath != null) {
        await _player!.play(ap.AssetSource(_currentAssetPath!));
      }
      _isPlaying = true;
      debugPrint('[AudioEngine] started playback');
      // Apply a short one-time volume ramp to remove any first-onset click.
      if (!_didInitialRamp) {
        unawaited(_rampIn(Duration(milliseconds: 30)));
      }
    } catch (e) {
      debugPrint('[AudioEngine] play() failed: $e');
      _isPlaying = false;
    }
  }

  Future<void> stop() async {
    debugPrint('[AudioEngine] stop()');
    if (!_initialized) return;
    if (!_isPlaying && _player == null) return;

    _isPlaying = false;
    await _disposePlayer();
    debugPrint('[AudioEngine] stopped');
  }

  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
    _player?.setVolume(_volume);
    debugPrint('[AudioEngine] setVolume volume=$_volume');
  }

  bool get isPlaying => _isPlaying;

  Future<void> _applySource() async {
    if (_player == null || _speed == null) {
      debugPrint(
        '[AudioEngine] _applySource skipped player=${_player != null} speed=$_speed',
      );
      return;
    }
    final s = _speed!;

    final ratioKey = s.backswing ~/ s.downswing == 3 ? '3to1' : '2to1';
    final primary =
        'audio/cycles/${_soundSet}/${ratioKey}_${s.backswing}_${s.downswing}.wav';

    _currentAssetPath = primary;
    debugPrint('[AudioEngine] using asset $_currentAssetPath');
    // No need to pre-load; play() with AssetSource will handle it
  }

  Future<void> _primeHardware() async {
    // 80 ms of 44.1 kHz mono 16-bit silence wrapped in a minimal WAV header.
    final bytes = _buildSilentWavBytes(milliseconds: 80, sampleRate: 44100);
    final ap.AudioPlayer p = ap.AudioPlayer();
    try {
      await p.setReleaseMode(ap.ReleaseMode.stop);
      await p.setVolume(0.0);
      await p.play(ap.BytesSource(bytes, mimeType: 'audio/wav'));
      await Future.delayed(const Duration(milliseconds: 90));
      await p.stop();
    } catch (_) {
      // Best-effort warmup.
    } finally {
      try {
        await p.release();
      } catch (_) {}
      try {
        await p.dispose();
      } catch (_) {}
    }
  }

  Uint8List _buildSilentWavBytes({
    required int milliseconds,
    required int sampleRate,
  }) {
    final int numSamples = ((milliseconds * sampleRate) / 1000).round();
    final int subchunk2Size = numSamples * 2; // mono 16-bit
    final int chunkSize = 36 + subchunk2Size;
    final bytes = BytesBuilder();
    void writeString(String s) => bytes.add(s.codeUnits);
    void writeU32(int v) => bytes.add(
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little),
    );
    void writeU16(int v) => bytes.add(
      Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little),
    );
    writeString('RIFF');
    writeU32(chunkSize);
    writeString('WAVE');
    writeString('fmt ');
    writeU32(16);
    writeU16(1); // PCM
    writeU16(1); // mono
    writeU32(sampleRate);
    writeU32(sampleRate * 2); // byte rate
    writeU16(2); // block align
    writeU16(16); // bits per sample
    writeString('data');
    writeU32(subchunk2Size);
    // Append silent PCM
    bytes.add(Uint8List(subchunk2Size));
    return bytes.toBytes();
  }

  Future<void> _rampIn(Duration duration) async {
    if (_player == null || _didInitialRamp) return;
    final ap.AudioPlayer player = _player!;
    final int steps = duration.inMilliseconds.clamp(6, 30);
    final double startVol = 0.0;
    final double targetVol = _volume.clamp(0.0, 1.0);
    final Duration stepDelay = Duration(
      milliseconds: (duration.inMilliseconds / steps).ceil(),
    );
    try {
      await player.setVolume(startVol);
      for (int i = 1; i <= steps; i++) {
        if (!_isPlaying || _player != player) return;
        final double v = startVol + (targetVol - startVol) * (i / steps);
        await player.setVolume(v);
        await Future.delayed(stepDelay);
      }
      if (_isPlaying && _player == player) {
        await player.setVolume(targetVol);
      }
      _didInitialRamp = true;
    } catch (_) {
      // Best-effort; ignore errors during ramp.
    }
  }

  Future<void> _disposePlayer() async {
    debugPrint('[AudioEngine] _disposePlayer()');
    await _onCompleteSub?.cancel();
    _onCompleteSub = null;
    try {
      await _player?.stop();
    } catch (e) {
      debugPrint('[AudioEngine] stop() err: $e');
    }
    try {
      await _player?.release();
    } catch (e) {
      debugPrint('[AudioEngine] release() err: $e');
    }
    try {
      await _player?.dispose();
    } catch (e) {
      debugPrint('[AudioEngine] dispose() err: $e');
    }
    _player = null;
  }
}
