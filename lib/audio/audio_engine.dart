import 'dart:async';

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
    _player = ap.AudioPlayer();
    await _player!.setVolume(_volume);
    await _player!.setReleaseMode(ap.ReleaseMode.stop);

    await _applySource();

    _onCompleteSub = _player!.onPlayerComplete.listen((_) async {
      debugPrint('[AudioEngine] onComplete, waiting gap=$_gapBetweenCycles');
      await Future.delayed(_gapBetweenCycles);
      if (!_isPlaying || _player == null) return;

      // Apply pending changes
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
        await _player!.resume();
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
      if (_currentAssetPath != null) {
        await _player!.play(ap.AssetSource(_currentAssetPath!));
      }
      _isPlaying = true;
      debugPrint('[AudioEngine] started playback');
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
