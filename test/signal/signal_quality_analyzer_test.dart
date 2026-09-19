import 'package:flutter_test/flutter_test.dart';
import 'package:ppg_recorder_app/signal/models/ppg_sample.dart';
import 'package:ppg_recorder_app/signal/models/quality_level.dart';
import 'package:ppg_recorder_app/signal/signal_quality_analyzer.dart';

import 'test_signals.dart';

void main() {
  const analyzer = SignalQualityAnalyzer();

  test('clean synthetic fingertip PPG scores good with correct heart rate', () {
    final analysis = analyzer.analyze(syntheticFingerPpg());
    final report = analysis.report;
    expect(report.level, QualityLevel.good);
    expect(report.score, greaterThanOrEqualTo(70));
    expect(report.fingerCoverage, greaterThan(0.95));
    expect(report.stabilityOk, isTrue);
    expect(report.estimatedHeartRateBpm, closeTo(72, 4));
    expect(report.sampling.measuredFps, closeTo(30, 0.01));
    expect(report.sampling.droppedFrames, 0);
    expect(analysis.filteredRed, hasLength(900));
    expect(analysis.filteredGreen, hasLength(900));
  });

  test('uncovered lens scores poor with low coverage', () {
    final report = analyzer.analyze(syntheticNoFinger()).report;
    expect(report.level, QualityLevel.poor);
    expect(report.fingerCoverage, lessThan(0.1));
    expect(report.issues, contains(QualityIssue.lowFingerCoverage));
  });

  test('too few frames is reported as tooShort without throwing', () {
    final report = analyzer
        .analyze(syntheticFingerPpg(seconds: 1))
        .report;
    expect(report.score, 0);
    expect(report.issues, [QualityIssue.tooShort]);
  });

  test('exposure jump fails the backend stability check', () {
    final samples = syntheticFingerPpg();
    final jumped = [
      for (final s in samples)
        s.frameIndex == 450
            ? PpgSample(
                frameIndex: s.frameIndex,
                timestampMs: s.timestampMs,
                red: s.red * 3,
                green: s.green,
                blue: s.blue,
              )
            : s,
    ];
    final report = analyzer.analyze(jumped).report;
    expect(report.stabilityOk, isFalse);
    expect(report.issues, contains(QualityIssue.exposureJump));
  });

  test('saturation and dropped frames are detected', () {
    final samples = syntheticFingerPpg();
    final degraded = <PpgSample>[
      for (final s in samples)
        if (s.frameIndex % 20 != 0) // drop 5 % of frames
          PpgSample(
            frameIndex: s.frameIndex,
            timestampMs: s.timestampMs,
            red: 255,
            green: s.green,
            blue: s.blue,
          ),
    ];
    final report = analyzer.analyze(degraded).report;
    expect(report.saturationFraction, 1.0);
    expect(report.issues, contains(QualityIssue.overexposed));
    expect(report.issues, contains(QualityIssue.droppedFrames));
    expect(report.sampling.droppedFrames, greaterThan(0));
  });

  test('SamplingStats computes fps and drops from timestamps', () {
    final stats = SamplingStats.fromTimestamps([0, 33.3, 66.6, 133.2, 166.5]);
    expect(stats.frameCount, 5);
    expect(stats.medianIntervalMs, closeTo(33.3, 1e-9));
    expect(stats.droppedFrames, 1);
  });
}
