import 'models/rgb_mean.dart';
import 'signal_config.dart';

/// Decides whether a torch-lit fingertip is covering the lens.
///
/// Identical rules to Sphygma's realtime controller:
///  1. Mean red ≥ 100 (enough transmitted light).
///  2. Red / (green + blue) ≥ 0.6 — haemoglobin passes red far more than
///     green/blue; open air or white light gives ≈ 0.33.
///  3. With ≥ 5 frames of history, red variance in `[0.1, 8000]`
///     (too low = static object, too high = gross movement).
class FingerDetector {
  /// Creates a stateless detector.
  const FingerDetector();

  /// Returns `true` if [current] looks like a covered fingertip, using
  /// [recentRed] (most recent red values, including the current one) for the
  /// variance check.
  bool isFingerPresent(RgbMean current, List<double> recentRed) {
    if (current.red < SignalConfig.fingerMinRed) return false;
    final others = current.green + current.blue;
    if (others > 0 &&
        current.red / others < SignalConfig.fingerMinRedDominance) {
      return false;
    }
    if (recentRed.length >= 5) {
      final variance = _variance(recentRed);
      if (variance < SignalConfig.fingerMinVariance) return false;
      if (variance > SignalConfig.fingerMaxVariance) return false;
    }
    return true;
  }

  static double _variance(List<double> values) {
    var sum = 0.0;
    for (final v in values) {
      sum += v;
    }
    final m = sum / values.length;
    var acc = 0.0;
    for (final v in values) {
      acc += (v - m) * (v - m);
    }
    return acc / values.length;
  }
}
