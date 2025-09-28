// Run with: dart run tools/generate_audio.dart
// Generates cycle WAV files into assets/audio/cycles/<set>/ for all speeds

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

Future<void> main() async {
  final cyclesRoot = Directory('assets/audio/cycles');
  if (!cyclesRoot.existsSync()) cyclesRoot.createSync(recursive: true);

  await _generateAllCycleSets(cyclesRoot);

  stdout.writeln('Done. Run: flutter pub get');
}

Future<void> _generateAllCycleSets(Directory cyclesRoot) async {
  // Frame pairs per ratio; total duration computed at 30 fps
  final threeToOne = <_Pair>[
    _Pair(18, 6),
    _Pair(21, 7),
    _Pair(24, 8),
    _Pair(27, 9),
    _Pair(30, 10),
  ];
  final twoToOne = <_Pair>[
    _Pair(14, 7),
    _Pair(16, 8),
    _Pair(18, 9),
    _Pair(20, 10),
    _Pair(22, 11),
  ];

  const int sampleRate = 44100;
  const int leadInMs = 15; // Default lead-in so first hit isn't at t=0
  const int defaultBlipMs = 60; // for synthesized tones; samples may differ
  final int blipSamples = (defaultBlipMs * sampleRate / 1000).round();

  // Build tone sets in memory
  final tones_low = _synthesizeSineWav(
    frequencyHz: 550,
    sampleRate: sampleRate,
    numSamples: blipSamples,
    amplitude: 0.25,
    applyEnvelope: true,
  );
  final tones_mid = _synthesizeSineWav(
    frequencyHz: 750,
    sampleRate: sampleRate,
    numSamples: blipSamples,
    amplitude: 0.25,
    applyEnvelope: true,
  );
  final tones_high = _synthesizeSineWav(
    frequencyHz: 1000,
    sampleRate: sampleRate,
    numSamples: blipSamples,
    amplitude: 0.25,
    applyEnvelope: true,
  );

  // Load external woodblock sample if present and apply micro fades.
  Uint8List woodblock_tick = _loadExternalWavOr(
    fallback: _synthesizeResonantClick(
      sampleRate: sampleRate,
      durationMs: defaultBlipMs,
      freqsHz: [1800, 3200],
      amps: [0.9, 0.6],
      decayMs: 50,
    ),
    path: 'tools/samples/woodblock/tick.wav',
  );
  woodblock_tick = _applyMicroFadeToWav(
    wav: woodblock_tick,
    sampleRate: sampleRate,
    fadeInMs: 3,
    fadeOutMs: 3,
  );

  // Piano: prefer external WAVs if available; otherwise synth fallback.
  Uint8List piano_low = _loadExternalWavOr(
    fallback: _synthesizeAdditiveTone(
      fundamentalHz: 440,
      partialAmps: const [1.0, 0.4, 0.2],
      sampleRate: sampleRate,
      durationMs: 70,
      attackMs: 4,
      decayMs: 60,
    ),
    path: 'tools/samples/piano/low.wav',
  );
  Uint8List piano_mid = _loadExternalWavOr(
    fallback: _synthesizeAdditiveTone(
      fundamentalHz: 660,
      partialAmps: const [1.0, 0.35, 0.15],
      sampleRate: sampleRate,
      durationMs: 70,
      attackMs: 4,
      decayMs: 60,
    ),
    path: 'tools/samples/piano/mid.wav',
  );
  Uint8List piano_high = _loadExternalWavOr(
    fallback: _synthesizeAdditiveTone(
      fundamentalHz: 880,
      partialAmps: const [1.0, 0.3, 0.12],
      sampleRate: sampleRate,
      durationMs: 70,
      attackMs: 4,
      decayMs: 60,
    ),
    path: 'tools/samples/piano/high.wav',
  );
  // Apply micro-fades and DC removal to piano samples to avoid clicks.
  piano_low = _applyMicroFadeToWav(
    wav: piano_low,
    sampleRate: sampleRate,
    fadeInMs: 20,
    fadeOutMs: 20,
  );
  piano_low = _removeDcAndNormalize(wav: piano_low);
  piano_mid = _applyMicroFadeToWav(
    wav: piano_mid,
    sampleRate: sampleRate,
    fadeInMs: 20,
    fadeOutMs: 20,
  );
  piano_mid = _removeDcAndNormalize(wav: piano_mid);
  piano_high = _applyMicroFadeToWav(
    wav: piano_high,
    sampleRate: sampleRate,
    fadeInMs: 20,
    fadeOutMs: 20,
  );
  piano_high = _removeDcAndNormalize(wav: piano_high);

  // Golf set removed.

  // Define the 4 sound sets
  final sets = <String, List<Uint8List>>{
    'tones': [tones_low, tones_mid, tones_high],
    'woodblock': [woodblock_tick, woodblock_tick, woodblock_tick],
    'piano': [piano_low, piano_mid, piano_high],
  };

  Future<void> writeSetDir(
    String setName,
    String ratioKey,
    List<_Pair> pairs,
  ) async {
    final outDir = Directory('${cyclesRoot.path}/$setName');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    final beeps = sets[setName]!; // [1,2,3]

    for (final p in pairs) {
      final totalFrames = p.backswing + p.downswing;
      final totalMs = ((totalFrames / 30.0) * 1000).round();
      final fileName = '${ratioKey}_${p.backswing}_${p.downswing}.wav';
      final path = '${outDir.path}/$fileName';
      final t1Ms = (totalMs * p.backswing / totalFrames).round();

      // Actual durations from WAVs (beeps may differ in length)
      final d1 = _wavDurationMs(beeps[0], sampleRate);
      final d2 = _wavDurationMs(beeps[1], sampleRate);

      // Use a larger compensated pre-roll for piano to avoid first-click.
      final int setLeadInMs = setName == 'piano' ? 50 : leadInMs;
      final silence1Ms = (t1Ms - d1 - setLeadInMs).clamp(0, 1 << 31);
      final silence2Ms = (totalMs - t1Ms - d2).clamp(0, 1 << 31);

      final crossfadeMs = setName == 'piano' ? 40 : 0;
      final firstOnsetAdjustMs = setName == 'piano' ? -10 : 0; // tighten Δ12
      // Compute desired deltas
      final desired12 = t1Ms;
      final desired23 = totalMs - t1Ms;
      // Solve for silences allowing negative s2 which we convert to extra overlap.
      int s1Calc =
          (desired12 + firstOnsetAdjustMs + crossfadeMs - d1 - setLeadInMs);
      if (s1Calc < 0) s1Calc = 0; // avoid pre-first-beep overlap
      final s2Raw = (desired23 + crossfadeMs - d2);
      int extraOverlap3Ms = 0;
      int s2Calc = s2Raw;
      if (s2Calc < 0) {
        extraOverlap3Ms = -s2Calc;
        s2Calc = 0;
      }

      final wav = _buildCycleWav(
        sampleRate: sampleRate,
        leadInMs: setLeadInMs,
        beep1: beeps[0],
        beep2: beeps[1],
        beep3: beeps[2],
        silence1Ms: s1Calc,
        silence2Ms: s2Calc,
        trailingGapMs: 10,
        crossfadeMs: crossfadeMs,
        extraOverlapAfterBeep2Ms: extraOverlap3Ms,
        leadCrossfadeMs: setName == 'piano' ? 40 : crossfadeMs,
        globalFadeInMs: setName == 'piano' ? 4 : 0,
      );
      File(path).writeAsBytesSync(wav, flush: true);
      stdout.writeln('Wrote $path');
    }
  }

  for (final set in sets.keys) {
    await writeSetDir(set, '3to1', threeToOne);
    await writeSetDir(set, '2to1', twoToOne);
  }
}

class _Pair {
  final int backswing;
  final int downswing;
  const _Pair(this.backswing, this.downswing);
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

Uint8List _loadExternalWavOr({
  required Uint8List fallback,
  required String path,
}) {
  final f = File(path);
  if (!f.existsSync()) return fallback;
  try {
    final bytes = f.readAsBytesSync();
    // Ensure it's a WAV with header length >= 44 bytes.
    if (bytes.length < 44) return fallback;
    return bytes;
  } catch (_) {
    return fallback;
  }
}

Uint8List _buildCycleWav({
  required int sampleRate,
  int leadInMs = 0,
  required Uint8List beep1,
  required Uint8List beep2,
  required Uint8List beep3,
  required int silence1Ms,
  required int silence2Ms,
  required int trailingGapMs,
  int crossfadeMs = 0,
  int extraOverlapAfterBeep2Ms = 0,
  int leadCrossfadeMs = -1,
  int globalFadeInMs = 0,
}) {
  Uint8List pcmFromWav(Uint8List wav) => wav.sublist(44);
  Uint8List silencePcm(int ms) {
    final samples = (ms * sampleRate / 1000).round();
    return Uint8List(samples * 2);
  }

  final pcm1 = pcmFromWav(beep1);
  final pcm2 = pcmFromWav(beep2);
  final pcm3 = pcmFromWav(beep3);
  final cfSamples = (crossfadeMs * sampleRate / 1000).round();
  final leadCfSamples =
      ((leadCrossfadeMs >= 0 ? leadCrossfadeMs : crossfadeMs) *
              sampleRate /
              1000)
          .round();

  // Soften the attack of the 2nd and 3rd hits inside the assembled cycle
  // to avoid residual clicks right before they start.
  Uint8List _attackSoften(Uint8List src, int ms) {
    final out = Uint8List.fromList(src);
    final bd = out.buffer.asByteData();
    final n = (ms * sampleRate / 1000).clamp(0, out.length ~/ 2);
    for (int i = 0; i < n; i++) {
      final s = bd.getInt16(i * 2, Endian.little).toDouble();
      final t = i / (n == 0 ? 1 : n);
      final w = t; // linear fade-in on top of existing fades/crossfades
      final v = (s * w).round().clamp(-32768, 32767) as int;
      bd.setInt16(i * 2, v, Endian.little);
    }
    return out;
  }

  final pcm2Soft = _attackSoften(pcm2, 10);
  final pcm3Soft = _attackSoften(pcm3, 10);

  Uint8List crossfadeN(Uint8List a, Uint8List b, int nSamples) {
    if (nSamples <= 0) {
      final out = BytesBuilder();
      out.add(a);
      out.add(b);
      return out.toBytes();
    }
    final aSamples = a.length ~/ 2;
    final bSamples = b.length ~/ 2;
    final n = aSamples < nSamples || bSamples < nSamples
        ? (aSamples < bSamples ? aSamples : bSamples)
        : nSamples;
    final out = BytesBuilder();
    // a without its last n samples
    out.add(a.sublist(0, (aSamples - n) * 2));
    // crossfade region
    for (int i = 0; i < n; i++) {
      final aIdx = (aSamples - n + i) * 2;
      final bIdx = i * 2;
      final aVal = ByteData.sublistView(
        a,
        aIdx,
        aIdx + 2,
      ).getInt16(0, Endian.little).toDouble();
      final bVal = ByteData.sublistView(
        b,
        bIdx,
        bIdx + 2,
      ).getInt16(0, Endian.little).toDouble();
      final t = i / n;
      // Equal-power crossfade weights
      final wA = math.cos(t * (math.pi / 2));
      final wB = math.sin(t * (math.pi / 2));
      final mixed = (aVal * wA + bVal * wB).round().clamp(-32768, 32767) as int;
      final bd = ByteData(2)..setInt16(0, mixed, Endian.little);
      out.add(bd.buffer.asUint8List());
    }
    // remainder of b after crossfade
    out.add(b.sublist(n * 2));
    return out.toBytes();
  }

  Uint8List crossfade(Uint8List a, Uint8List b) => crossfadeN(a, b, cfSamples);

  final pcmLead = silencePcm(leadInMs);
  final pcmSil1 = silencePcm(silence1Ms);
  final pcmSil2 = silencePcm(silence2Ms);
  final pcmGap = silencePcm(trailingGapMs);

  // Build dynamic PCM content with optional crossfades, then write header.
  final content = BytesBuilder();
  if (cfSamples > 0) {
    // Crossfade lead-in into first beep with potentially smaller/zero crossfade.
    final leadAndFirst = crossfadeN(pcmLead, pcm1, leadCfSamples);
    final seg1 = BytesBuilder()
      ..add(leadAndFirst)
      ..add(pcmSil1);
    final seg1Bytes = seg1.toBytes();
    final seg12 = crossfade(seg1Bytes, pcm2Soft);
    final seg12s = BytesBuilder()
      ..add(seg12)
      ..add(pcmSil2);
    var seg12sBytes = seg12s.toBytes();
    // If we need the third onset earlier than the second sample tail allows,
    // trim tail of seg12s before crossfading into pcm3.
    if (extraOverlapAfterBeep2Ms > 0) {
      final trimSamples = (extraOverlapAfterBeep2Ms * sampleRate / 1000)
          .round();
      final trimBytes = (trimSamples * 2).clamp(0, seg12sBytes.length);
      final keep = seg12sBytes.length - trimBytes;
      if (keep > 0) {
        seg12sBytes = seg12sBytes.sublist(0, keep);
      }
    }
    final segAll = crossfade(seg12sBytes, pcm3Soft);
    content.add(segAll);
  } else {
    content.add(pcmLead);
    content.add(pcm1);
    content.add(pcmSil1);
    content.add(pcm2);
    content.add(pcmSil2);
    content.add(pcm3);
  }
  content.add(pcmGap);

  final body = content.toBytes();
  // Apply an optional short global fade-in to the assembled PCM to soften the very first onset.
  if (globalFadeInMs > 0 && body.isNotEmpty) {
    final bd = ByteData.sublistView(body);
    final fadeSamples = (globalFadeInMs * sampleRate / 1000).round();
    final limit = math.min(fadeSamples, body.length ~/ 2);
    for (int i = 0; i < limit; i++) {
      final s = bd.getInt16(i * 2, Endian.little).toDouble();
      final t = i / (limit == 0 ? 1 : limit);
      final w = t; // linear fade-in
      final v = (s * w).round().clamp(-32768, 32767) as int;
      bd.setInt16(i * 2, v, Endian.little);
    }
  }
  // Force start/end samples to exact zero to eliminate any DC step at boundaries.
  if (body.isNotEmpty) {
    final bd = ByteData.sublistView(body);
    bd.setInt16(0, 0, Endian.little);
    if (body.length >= 2) {
      bd.setInt16(body.length - 2, 0, Endian.little);
    }
  }
  final subchunk2Size = body.length;
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
  out.add(body);

  return out.toBytes();
}

int _wavDurationMs(Uint8List wav, int sampleRate) {
  final pcmLen = wav.length - 44;
  if (pcmLen <= 0) return 0;
  final samples = pcmLen ~/ 2; // mono 16-bit
  return ((samples * 1000) / sampleRate).round();
}

Uint8List _applyMicroFadeToWav({
  required Uint8List wav,
  required int sampleRate,
  int fadeInMs = 3,
  int fadeOutMs = 3,
}) {
  if (wav.length < 44) return wav;
  final header = wav.sublist(0, 44);
  final pcm = wav.sublist(44).buffer.asByteData();
  final totalSamples = pcm.lengthInBytes ~/ 2;
  final fadeInSamples = (fadeInMs * sampleRate / 1000).round();
  final fadeOutSamples = (fadeOutMs * sampleRate / 1000).round();

  for (int i = 0; i < totalSamples; i++) {
    double gain = 1.0;
    if (i < fadeInSamples) {
      gain = i / (fadeInSamples == 0 ? 1 : fadeInSamples);
    } else if (i > totalSamples - fadeOutSamples) {
      final n = totalSamples - i;
      gain = n / (fadeOutSamples == 0 ? 1 : fadeOutSamples);
    }
    final s = pcm.getInt16(i * 2, Endian.little);
    final out = (s * gain).round().clamp(-32768, 32767);
    pcm.setInt16(i * 2, out, Endian.little);
  }
  // Force exact zero at the first and last samples to avoid residual steps.
  if (totalSamples > 0) {
    pcm.setInt16(0, 0, Endian.little);
    pcm.setInt16((totalSamples - 1) * 2, 0, Endian.little);
  }
  final out = BytesBuilder();
  out.add(header);
  out.add(wav.sublist(44));
  return out.toBytes();
}

Uint8List _removeDcAndNormalize({
  required Uint8List wav,
  double targetPeak = 0.98,
}) {
  if (wav.length < 44) return wav;
  final header = wav.sublist(0, 44);
  final pcm = wav.sublist(44).buffer.asByteData();
  final totalSamples = pcm.lengthInBytes ~/ 2;
  if (totalSamples == 0) return wav;

  // Compute DC offset and max abs
  double sum = 0;
  double maxAbs = 0;
  for (int i = 0; i < totalSamples; i++) {
    final s = pcm.getInt16(i * 2, Endian.little).toDouble();
    sum += s;
    final a = s.abs();
    if (a > maxAbs) maxAbs = a;
  }
  final dc = sum / totalSamples;
  final gain = maxAbs == 0 ? 1.0 : (targetPeak * 32767.0) / maxAbs;

  for (int i = 0; i < totalSamples; i++) {
    final s = pcm.getInt16(i * 2, Endian.little).toDouble();
    int out = ((s - dc) * gain).round();
    if (out < -32768) out = -32768;
    if (out > 32767) out = 32767;
    pcm.setInt16(i * 2, out, Endian.little);
  }

  final out = BytesBuilder();
  out.add(header);
  out.add(wav.sublist(44));
  return out.toBytes();
}

Uint8List _synthesizeResonantClick({
  required int sampleRate,
  required int durationMs,
  required List<int> freqsHz,
  required List<double> amps,
  required int decayMs,
}) {
  final int numSamples = (durationMs * sampleRate / 1000).round();
  final int subchunk2Size = numSamples * 2;
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

  final bd = BytesBuilder();
  final tau = decayMs / 1000.0; // seconds
  for (int n = 0; n < numSamples; n++) {
    final t = n / sampleRate;
    double sample = 0.0;
    for (int i = 0; i < freqsHz.length; i++) {
      sample += amps[i] * math.sin(2 * math.pi * freqsHz[i] * t);
    }
    final env = math.exp(-t / tau);
    sample = (sample * env).clamp(-1.0, 1.0);
    final s = ByteData(2)..setInt16(0, (sample * 32767).round(), Endian.little);
    bd.add(s.buffer.asUint8List());
  }
  bytes.add(bd.toBytes());
  return bytes.toBytes();
}

Uint8List _synthesizeAdditiveTone({
  required int fundamentalHz,
  required List<double> partialAmps,
  required int sampleRate,
  required int durationMs,
  required int attackMs,
  required int decayMs,
}) {
  final int numSamples = (durationMs * sampleRate / 1000).round();
  final int subchunk2Size = numSamples * 2;
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

  final bd = BytesBuilder();
  final attackSamp = (attackMs * sampleRate / 1000).round();
  final decaySamp = (decayMs * sampleRate / 1000).round();
  for (int n = 0; n < numSamples; n++) {
    final t = n / sampleRate;
    double sample = 0.0;
    for (int i = 0; i < partialAmps.length; i++) {
      sample +=
          partialAmps[i] * math.sin(2 * math.pi * fundamentalHz * (i + 1) * t);
    }
    double env = 1.0;
    if (n < attackSamp) {
      env = n / (attackSamp == 0 ? 1 : attackSamp);
    } else {
      final dn = n - attackSamp;
      env = math.exp(-dn / (decaySamp == 0 ? 1 : decaySamp));
    }
    sample = (sample * env).clamp(-1.0, 1.0);
    final s = ByteData(2)..setInt16(0, (sample * 32767).round(), Endian.little);
    bd.add(s.buffer.asUint8List());
  }
  bytes.add(bd.toBytes());
  return bytes.toBytes();
}

Uint8List _synthesizeNoiseWoosh({
  required int sampleRate,
  required int durationMs,
  required double startAmp,
  required double peakAmp,
  required double endAmp,
}) {
  final int numSamples = (durationMs * sampleRate / 1000).round();
  final int subchunk2Size = numSamples * 2;
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

  final rnd = math.Random(42);
  final bd = BytesBuilder();
  for (int n = 0; n < numSamples; n++) {
    final pos = n / numSamples;
    double env;
    if (pos < 0.5) {
      env = startAmp + (peakAmp - startAmp) * (pos / 0.5);
    } else {
      env = peakAmp + (endAmp - peakAmp) * ((pos - 0.5) / 0.5);
    }
    final noise = (rnd.nextDouble() * 2 - 1);
    final sample = (env * noise).clamp(-1.0, 1.0);
    final s = ByteData(2)..setInt16(0, (sample * 32767).round(), Endian.little);
    bd.add(s.buffer.asUint8List());
  }
  bytes.add(bd.toBytes());
  return bytes.toBytes();
}
