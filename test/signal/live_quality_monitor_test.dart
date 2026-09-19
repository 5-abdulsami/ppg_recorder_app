import 'package:flutter_test/flutter_test.dart';
import 'package:ppg_recorder_app/signal/finger_detector.dart';
import 'package:ppg_recorder_app/signal/live_quality_monitor.dart';
import 'package:ppg_recorder_app/signal/models/quality_level.dart';
import 'package:ppg_recorder_app/signal/models/rgb_mean.dart';

import 'test_signals.dart';

void main() {
  group('FingerDetector (Sphygma rules)', () {
    const detector = FingerDetector();

    test('accepts a red-dominant bright frame', () {
      expect(detector.isFingerPresent(const RgbMean(180, 40, 20), []), isTrue);
    });

    test('rejects dim or white frames', () {
      expect(detector.isFingerPresent(const RgbMean(90, 10, 10), []), isFalse);
      expect(
        detector.isFingerPresent(const RgbMean(200, 190, 185), []),
        isFalse,
      );
    });

    test('rejects a perfectly static scene', () {
      expect(
        detector.isFingerPresent(const RgbMean(180, 40, 20), [
          180,
          180,
          180,
          180,
          180,
        ]),
        isFalse,
      );
    });
  });

  group('LiveQualityMonitor', () {
    test('steady fingertip becomes good and counts consecutive frames', () {
      final monitor = LiveQualityMonitor();
      LiveQualityReading? last;
      for (final s in syntheticFingerPpg(seconds: 2)) {
        last = monitor.addSample(RgbMean(s.red, s.green, s.blue));
      }
      expect(last!.level, QualityLevel.good);
      expect(last.fingerPresent, isTrue);
      expect(monitor.consecutiveFingerFrames, greaterThanOrEqualTo(55));
    });

    test('no finger is poor and counts missing frames', () {
      final monitor = LiveQualityMonitor();
      LiveQualityReading? last;
      for (var i = 0; i < 20; i++) {
        last = monitor.addSample(const RgbMean(150, 148, 145));
      }
      expect(last!.level, QualityLevel.poor);
      expect(last.issue, LiveQualityIssue.noFinger);
      expect(monitor.consecutiveMissingFrames, 20);
    });

    test('large fluctuations are flagged as motion', () {
      final monitor = LiveQualityMonitor();
      LiveQualityReading? last;
      for (var i = 0; i < 30; i++) {
        last = monitor.addSample(RgbMean(i.isEven ? 160 : 200, 40, 20));
      }
      expect(last!.issue, LiveQualityIssue.motion);
      expect(last.level, isNot(QualityLevel.good));
    });

    test('reset clears history', () {
      final monitor = LiveQualityMonitor()
        ..addSample(const RgbMean(180, 40, 20))
        ..reset();
      expect(monitor.consecutiveFingerFrames, 0);
      expect(monitor.consecutiveMissingFrames, 0);
    });
  });
}
