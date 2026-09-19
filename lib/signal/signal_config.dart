/// Numeric parameters of the PPG signal pipeline.
///
/// Values marked "Sphygma" are copied from the validated Sphygma app/backend
/// so both projects process signals identically. Pure Dart — no Flutter.
abstract final class SignalConfig {
  // ── Region of interest ──────────────────────────────────────────────────
  /// Side length (px) of the centred square ROI averaged per frame (Sphygma).
  static const int roiSizePx = 64;

  // ── Finger detection (Sphygma realtime controller) ──────────────────────
  /// Minimum mean red intensity for a covered, torch-lit fingertip.
  static const double fingerMinRed = 100;

  /// Minimum red / (green + blue) ratio; open air / white light is ≈ 0.33.
  static const double fingerMinRedDominance = 0.6;

  /// Rolling window (frames) for the finger variance check.
  static const int fingerVarianceWindow = 20;

  /// Below this red variance the scene is static (no pulse).
  static const double fingerMinVariance = 0.1;

  /// Above this red variance the finger is moving grossly.
  static const double fingerMaxVariance = 8000;

  // ── Exposure / saturation ───────────────────────────────────────────────
  /// Mean red at/above which the sensor is considered clipped.
  static const double saturationRedLevel = 250;

  // ── Backend stability check (check_signal_quality) ──────────────────────
  /// A single-step jump larger than this fraction of the mean = exposure reset.
  static const double jumpFractionOfMean = 0.5;

  /// A standard deviation above this fraction of the mean = gross motion.
  static const double noiseStdFractionOfMean = 0.8;

  // ── Filtering (Sphygma backend preprocess_hr_signal) ────────────────────
  /// Savitzky-Golay baseline window (samples) for robust detrending.
  static const int detrendWindowSamples = 45;

  /// Butterworth order.
  static const int filterOrder = 4;

  /// Heart-rate band lower edge (Hz).
  static const double heartRateBandLowHz = 0.7;

  /// Heart-rate band upper edge (Hz).
  static const double heartRateBandHighHz = 3.0;

  /// Final smoothing window (samples).
  static const int smoothingWindowSamples = 11;

  /// Final smoothing polynomial order.
  static const int smoothingPolyOrder = 3;

  /// Minimum samples needed by the full preprocessing chain
  /// (filtfilt padding for an order-4 band-pass is 27 samples).
  static const int minFilterableSamples = 60;

  // ── Spectral confidence (Sphygma backend HeartRateService) ──────────────
  /// Lowest plausible heart rate (bpm).
  static const double minHeartRateBpm = 40;

  /// Highest plausible heart rate (bpm).
  static const double maxHeartRateBpm = 200;

  /// Analysis window length (s).
  static const double spectralWindowSeconds = 8;

  /// Analysis window stride (s).
  static const double spectralStrideSeconds = 2;

  /// Maximum Welch segment length (samples).
  static const int welchMaxSegment = 256;

  // ── Quality score weights / thresholds (this app) ───────────────────────
  /// Weight of finger coverage in the 0–100 score.
  static const double weightCoverage = 0.40;

  /// Weight of spectral (pulse) confidence in the 0–100 score.
  static const double weightSpectral = 0.40;

  /// Weight of the backend stability check in the 0–100 score.
  static const double weightStability = 0.20;

  /// Maximum points deducted for a fully saturated recording.
  static const double saturationPenaltyPoints = 20;

  /// Score at or above which quality is "good".
  static const int goodScoreThreshold = 70;

  /// Score at or above which quality is "fair" (below = "poor").
  static const int fairScoreThreshold = 40;

  /// Coverage below this fraction raises a low-coverage issue.
  static const double minGoodCoverage = 0.9;

  /// Spectral confidence below this raises a weak-pulse issue.
  static const double minGoodSpectralConfidence = 0.3;

  /// Saturated-frame fraction above this raises an overexposure issue.
  static const double maxGoodSaturation = 0.1;

  /// A frame interval above this multiple of the median counts as a drop.
  static const double droppedFrameIntervalFactor = 1.5;

  /// Dropped-frame fraction above this raises a frame-drop issue.
  static const double maxGoodDroppedFraction = 0.02;

  // ── Live indicator (this app) ───────────────────────────────────────────
  /// Rolling window (frames) for live motion checks (≈ 1 s at 30 fps).
  static const int liveWindowFrames = 30;

  /// Minimum frames in the window before motion is assessed.
  static const int liveMinFramesForMotion = 10;

  /// Red coefficient of variation above which motion is "fair".
  static const double liveFairVariation = 0.04;

  /// Red coefficient of variation above which motion is "poor".
  static const double livePoorVariation = 0.10;

  /// Displayed level = worst level over this many recent frames (debounce).
  static const int liveDebounceFrames = 10;
}
