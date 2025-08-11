// Run with: dart run tools/generate_audio.dart
// Generates WAV cycle files into assets/audio/cycles/

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

Future<void> main() async {
  final outDir = Directory('assets/audio/cycles');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  // Presets (ratioNumerator: [backswingUnits, downswingUnits, totalCycleMs])
  // 3:1: 18/6 (800ms), 21/7 (933ms), 24/8 (1067ms), 27/9 (1200ms)
  // 2:1: 12/6 (600ms), 16/8 (800ms), 20/10 (1000ms)
  final presets = <String, List<_Preset>>{
    '3to1': [
      _Preset(18, 6, 800),
      _Preset(21, 7, 933),
      _Preset(24, 8, 1067),
      _Preset(27, 9, 1200),
    ],
    '2to1': [_Preset(12, 6, 600), _Preset(16, 8, 800), _Preset(20, 10, 1000)],
  };

  const int sampleRate = 44100;
  const Duration beepDuration = Duration(milliseconds: 60);
  const Duration trailingGap = Duration.zero; // no embedded gap

  // Precompute beeps
  final int beepSamples = (beepDuration.inMilliseconds * sampleRate / 1000)
      .round();
  final beep1 = _synthesizeSineWav(
    frequencyHz: 550,
    sampleRate: sampleRate,
    numSamples: beepSamples,
    amplitude: 0.25,
    applyEnvelope: true,
  );
  final beep2 = _synthesizeSineWav(
    frequencyHz: 750,
    sampleRate: sampleRate,
    numSamples: beepSamples,
    amplitude: 0.25,
    applyEnvelope: true,
  );
  final beep3 = _synthesizeSineWav(
    frequencyHz: 1000,
    sampleRate: sampleRate,
    numSamples: beepSamples,
    amplitude: 0.25,
    applyEnvelope: true,
  );

  for (final entry in presets.entries) {
    final ratioKey = entry.key;
    for (final p in entry.value) {
      final fileName = '${ratioKey}_${p.backswing}_${p.downswing}.wav';
      final path = '${outDir.path}/$fileName';
      final t1Ms = (p.totalMs * p.backswing / (p.backswing + p.downswing))
          .round();
      final silence1Ms = (t1Ms - beepDuration.inMilliseconds).clamp(0, 1 << 31);
      final silence2Ms = (p.totalMs - t1Ms - beepDuration.inMilliseconds).clamp(
        0,
        1 << 31,
      );

      final wav = _buildCycleWav(
        sampleRate: sampleRate,
        beep1: beep1,
        beep2: beep2,
        beep3: beep3,
        silence1Ms: silence1Ms as int,
        silence2Ms: silence2Ms as int,
        trailingGapMs: trailingGap.inMilliseconds,
      );
      File(path).writeAsBytesSync(wav, flush: true);
      stdout.writeln('Wrote $path');
    }
  }

  stdout.writeln('Done. Add assets path to pubspec and run: flutter pub get');
}

class _Preset {
  final int backswing;
  final int downswing;
  final int totalMs;
  const _Preset(this.backswing, this.downswing, this.totalMs);
}

Uint8List _synthesizeSineWav({
  required int frequencyHz,
  required int sampleRate,
  required int numSamples,
  double amplitude = 0.25,
  bool applyEnvelope = true,
}) {
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
  writeU16(1);
  writeU16(1);
  writeU32(sampleRate);
  writeU32(sampleRate * 2);
  writeU16(2);
  writeU16(16);
  writeString('data');
  writeU32(subchunk2Size);

  final twoPiFOverFs = 2 * math.pi * frequencyHz / sampleRate;
  final bd = BytesBuilder();
  final attackRelease = (0.005 * sampleRate).round();
  for (int n = 0; n < numSamples; n++) {
    double env = 1.0;
    if (applyEnvelope) {
      if (n < attackRelease)
        env = n / attackRelease;
      else if (n > numSamples - attackRelease)
        env = (numSamples - n) / attackRelease;
      if (env < 0) env = 0;
    }
    final sample = (amplitude * env * math.sin(twoPiFOverFs * n)).clamp(
      -1.0,
      1.0,
    );
    final s = ByteData(2)..setInt16(0, (sample * 32767).round(), Endian.little);
    bd.add(s.buffer.asUint8List());
  }
  bytes.add(bd.toBytes());

  return bytes.toBytes();
}

Uint8List _buildCycleWav({
  required int sampleRate,
  required Uint8List beep1,
  required Uint8List beep2,
  required Uint8List beep3,
  required int silence1Ms,
  required int silence2Ms,
  required int trailingGapMs,
}) {
  Uint8List pcmFromWav(Uint8List wav) => wav.sublist(44);
  Uint8List silencePcm(int ms) {
    final samples = (ms * sampleRate / 1000).round();
    return Uint8List(samples * 2);
  }

  final pcm1 = pcmFromWav(beep1);
  final pcm2 = pcmFromWav(beep2);
  final pcm3 = pcmFromWav(beep3);
  final pcmSil1 = silencePcm(silence1Ms);
  final pcmSil2 = silencePcm(silence2Ms);
  final pcmGap = silencePcm(trailingGapMs);

  final subchunk2Size =
      pcm1.length +
      pcmSil1.length +
      pcm2.length +
      pcmSil2.length +
      pcm3.length +
      pcmGap.length;
  final chunkSize = 36 + subchunk2Size;

  final out = BytesBuilder();
  void writeString(String s) => out.add(s.codeUnits);
  void writeU32(int v) =>
      out.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void writeU16(int v) =>
      out.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));

  writeString('RIFF');
  writeU32(chunkSize);
  writeString('WAVE');
  writeString('fmt ');
  writeU32(16);
  writeU16(1);
  writeU16(1);
  writeU32(sampleRate);
  writeU32(sampleRate * 2);
  writeU16(2);
  writeU16(16);
  writeString('data');
  writeU32(subchunk2Size);

  out.add(pcm1);
  out.add(pcmSil1);
  out.add(pcm2);
  out.add(pcmSil2);
  out.add(pcm3);
  out.add(pcmGap);

  return out.toBytes();
}
