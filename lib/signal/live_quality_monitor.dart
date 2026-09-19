import 'dart:collection';
import 'dart:math' as math;

import 'finger_detector.dart';
import 'models/quality_level.dart';
import 'models/rgb_mean.dart';
import 'signal_config.dart';

/// Reason behind a non-good live quality reading.
enum LiveQualityIssue {
  /// No problem detected.
  none,

  /// Lens is not fully covered by a fingertip.
  noFinger,

  /// Readings are fluctuating too much (finger or phone moving).
  motion,

  /// The red channel is clipped at the sensor maximum.
  overexposed,
}

/// Result of feeding one frame into [LiveQualityMonitor].
class LiveQualityReading {
  /// Creates a reading.
  const LiveQualityReading({
    required this.level,
    required this.issue,
    required this.fingerPresent,
  });

  /// Debounced level to display (worst over the last few frames).
  final QualityLevel level;

  /// Issue associated with [level].
  final LiveQualityIssue issue;

  /// Whether a finger was detected in this exact frame (not debounced).
  final bool fingerPresent;
}

/// Rolling, frame-by-frame signal quality assessment for the on-screen
/// traffic-light indicator.
///
/// Stateful but UI-free: feed it one [RgbMean] per camera frame.
class LiveQualityMonitor {
  /// Creates a monitor. [detector] is injectable for testing.
  LiveQualityMonitor({FingerDetector detector = const FingerDetector()})
    : _detector = detector;

  final FingerDetector _detector;
  final ListQueue<double> _redWindow = ListQueue<double>();
  final ListQueue<(QualityLevel, LiveQualityIssue)> _recent =
      ListQueue<(QualityLevel, LiveQualityIssue)>();

  int _consecutiveFingerFrames = 0;
  int _consecutiveMissingFrames = 0;

  /// Frames in a row (ending now) in which a finger was detected.
  int get consecutiveFingerFrames => _consecutiveFingerFrames;

  /// Frames in a row (ending now) in which no finger was detected.
  int get consecutiveMissingFrames => _consecutiveMissingFrames;

  /// Clears all history (e.g. when a new recording attempt starts).
  void reset() {
    _redWindow.clear();
    _recent.clear();
    _consecutiveFingerFrames = 0;
    _consecutiveMissingFrames = 0;
  }

  /// Adds one frame's ROI means and returns the updated reading.
  LiveQualityReading addSample(RgbMean sample) {
    final previousRed = _redWindow.isEmpty ? null : _redWindow.last;
    _redWindow.addLast(sample.red);
    while (_redWindow.length > SignalConfig.liveWindowFrames) {
      _redWindow.removeFirst();
    }

    final fingerWindow = _redWindow
        .skip(math.max(0, _redWindow.length - SignalConfig.fingerVarianceWindow))
        .toList(growable: false);
    final fingerPresent = _detector.isFingerPresent(sample, fingerWindow);
    if (fingerPresent) {
      _consecutiveFingerFrames++;
      _consecutiveMissingFrames = 0;
    } else {
      _consecutiveMissingFrames++;
      _consecutiveFingerFrames = 0;
    }

    final instant = _evaluate(sample, previousRed, fingerPresent);
    _recent.addLast(instant);
    while (_recent.length > SignalConfig.liveDebounceFrames) {
      _recent.removeFirst();
    }
    var worst = _recent.last;
    for (final entry in _recent) {
      if (entry.$1.severity > worst.$1.severity) worst = entry;
    }
    return LiveQualityReading(
      level: worst.$1,
      issue: worst.$2,
      fingerPresent: fingerPresent,
    );
  }

  (QualityLevel, LiveQualityIssue) _evaluate(
    RgbMean sample,
    double? previousRed,
    bool fingerPresent,
  ) {
    if (!fingerPresent) return (QualityLevel.poor, LiveQualityIssue.noFinger);

    if (_redWindow.length >= SignalConfig.liveMinFramesForMotion) {
      var sum = 0.0;
      for (final v in _redWindow) {
        sum += v;
      }
      final mean = sum / _redWindow.length;
      if (mean > 0) {
        if (previousRed != null &&
            (sample.red - previousRed).abs() >
                mean * SignalConfig.jumpFractionOfMean) {
          return (QualityLevel.poor, LiveQualityIssue.motion);
        }
        var acc = 0.0;
        for (final v in _redWindow) {
          acc += (v - mean) * (v - mean);
        }
        final variation = math.sqrt(acc / _redWindow.length) / mean;
        if (variation > SignalConfig.livePoorVariation) {
          return (QualityLevel.poor, LiveQualityIssue.motion);
        }
        if (variation > SignalConfig.liveFairVariation) {
          return (QualityLevel.fair, LiveQualityIssue.motion);
        }
      }
    }

    if (sample.red >= SignalConfig.saturationRedLevel) {
      return (QualityLevel.fair, LiveQualityIssue.overexposed);
    }
    return (QualityLevel.good, LiveQualityIssue.none);
  }
}
