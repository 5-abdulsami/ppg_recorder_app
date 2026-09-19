import 'dsp/filters.dart';
import 'signal_config.dart';

/// Sphygma backend heart-rate preprocessing chain
/// (`preprocess_hr_signal` in `app/services/signal_processing.py`):
///
/// validate → robust detrend (Savitzky-Golay baseline, window 45) →
/// z-score → 4th-order Butterworth band-pass 0.7–3.0 Hz (zero-phase) →
/// Savitzky-Golay smoothing (11, 3).
///
/// Used only for display and quality scoring — the saved CSV stays raw.
///
/// Throws [ArgumentError] if the signal is too short or flat to filter.
List<double> preprocessHeartRateSignal(
  List<double> raw, {
  required double sampleRateHz,
}) {
  final valid = raw.where((v) => !v.isNaN).toList();
  if (valid.length < SignalConfig.minFilterableSamples) {
    throw ArgumentError(
      'Signal has ${valid.length} valid samples; '
      'at least ${SignalConfig.minFilterableSamples} are required.',
    );
  }
  final detrended = robustDetrend(
    valid,
    windowSize: SignalConfig.detrendWindowSamples,
  );
  final normalised = zScore(detrended);
  final filtered = bandpassFilter(
    normalised,
    sampleRateHz: sampleRateHz,
    lowHz: SignalConfig.heartRateBandLowHz,
    highHz: SignalConfig.heartRateBandHighHz,
    order: SignalConfig.filterOrder,
  );
  return savitzkyGolay(
    filtered,
    windowLength: SignalConfig.smoothingWindowSamples,
    polyOrder: SignalConfig.smoothingPolyOrder,
  );
}
