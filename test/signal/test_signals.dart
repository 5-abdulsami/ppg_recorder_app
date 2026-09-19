import 'dart:math' as math;

import 'package:ppg_recorder_app/signal/models/ppg_sample.dart';

/// Synthetic fingertip PPG at [fps] for [seconds]: red ≈ 180 with a 1.2 Hz
/// (72 bpm) pulse, green ≈ 40 with a smaller pulse, plus slight noise.
List<PpgSample> syntheticFingerPpg({
  double fps = 30,
  double seconds = 30,
  double heartRateHz = 1.2,
  int seed = 1,
}) {
  final random = math.Random(seed);
  final n = (fps * seconds).round();
  return [
    for (var i = 0; i < n; i++)
      () {
        final t = i / fps;
        final pulse = math.sin(2 * math.pi * heartRateHz * t) +
            0.3 * math.sin(4 * math.pi * heartRateHz * t + 0.6);
        return PpgSample(
          frameIndex: i,
          timestampMs: t * 1000,
          red: 180 + 2.0 * pulse + 0.05 * t + random.nextDouble() * 0.2,
          green: 40 + 0.8 * pulse + random.nextDouble() * 0.1,
          blue: 20 + random.nextDouble() * 0.1,
        );
      }(),
  ];
}

/// Open-air / uncovered lens: roughly white, no pulse.
List<PpgSample> syntheticNoFinger({double fps = 30, double seconds = 30}) {
  final random = math.Random(7);
  final n = (fps * seconds).round();
  return [
    for (var i = 0; i < n; i++)
      PpgSample(
        frameIndex: i,
        timestampMs: i / fps * 1000,
        red: 120 + random.nextDouble() * 30,
        green: 118 + random.nextDouble() * 30,
        blue: 115 + random.nextDouble() * 30,
      ),
  ];
}
