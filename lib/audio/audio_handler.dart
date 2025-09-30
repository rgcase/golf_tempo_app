import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class BackgroundAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  BackgroundAudioHandler() {
    _player.playbackEventStream.listen((event) {
      playbackState.add(
        PlaybackState(
          processingState: _toProcessingState(event.processingState),
          playing: _player.playing,
          controls: const [
            MediaControl.play,
            MediaControl.pause,
            MediaControl.stop,
          ],
          updatePosition: event.updatePosition,
          bufferedPosition: event.bufferedPosition,
          speed: _player.speed,
        ),
      );
    });
  }

  Future<void> setCycleSource({
    required String assetPath,
    required Duration gap,
  }) async {
    final item = const MediaItem(
      id: 'swinggroove-cycle',
      title: 'SwingGroove Golf',
      album: 'Tempo',
    );
    try {
      debugPrint('[Handler] setAudioSource begin: $assetPath gap=$gap');
      final silenceItem = const MediaItem(
        id: 'swinggroove-silence',
        title: 'Silence',
        album: 'Tempo',
      );
      final seq = ConcatenatingAudioSource(
        children: [
          AudioSource.asset(assetPath, tag: item),
          AudioSource.asset(
            'assets/audio/silence_2000ms.wav',
            tag: silenceItem,
          ),
        ],
      );
      await _player.setLoopMode(LoopMode.all);
      await _player.setAudioSource(seq);
      mediaItem.add(item);
      debugPrint('[Handler] setAudioSource done');
    } catch (e) {
      debugPrint('[Handler] setAudioSource error: $e');
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    debugPrint('[Handler] play()');
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await _player.dispose();
  }

  AudioProcessingState _toProcessingState(ProcessingState s) {
    switch (s) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }
}
