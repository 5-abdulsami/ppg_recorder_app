import 'dart:math' as math;

import 'dsp/filters.dart';
import 'dsp/spectral.dart';
import 'finger_detector.dart';
import 'models/ppg_sample.dart';
import 'models/quality_level.dart';
import 'models/rgb_mean.dart';
import 'ppg_preprocessing.dart';
import 'signal_config.dart';

/// Colour channel of the PPG signal.
enum PpgChannel {
  /// Red channel (Sphygma's blood-pressure input).
  red,

  /// Green channel (Sphygma's heart-rate input).
  green,
}

/// Specific problems found in a recording.
enum QualityIssue {
  /// Too few frames to analyse.
  tooShort,

  /// The fingertip did not cover the lens for a large part of the recording.
  lowFingerCoverage,

  /// A sudden brightness jump (exposure reset) was detected.
  exposureJump,

  /// The signal fluctuates far more than a pulse would (gross motion).
  excessiveNoise,

  /// No clear periodic pulse in the heart-rate band.
  weakPulse,

  /// Many frames are clipped at the sensor maximum.
  overexposed,

  /// The video has gaps between frames.
  droppedFrames,
}

/// Frame timing statistics derived from presentation timestamps.
class SamplingStats {
  /// Creates sampling statistics.
  const SamplingStats({
    required this.frameCount,
    required this.durationMs,
    required this.measuredFps,
    required this.medianIntervalMs,
    required this.droppedFrames,
  });

  /// Number of frames.
  final int frameCount;

  /// Time between the first and last frame (ms).
  final double durationMs;

  /// Average frame rate from timestamps.
  final double measuredFps;

  /// Median frame interval (ms).
  final double medianIntervalMs;

  /// Estimated number of missing frames (from over-long intervals).
  final int droppedFrames;

  /// Computes statistics from ascending timestamps in milliseconds.
  factory SamplingStats.fromTimestamps(List<double> timestampsMs) {
    final n = timestampsMs.length;
    if (n < 2) {
      return SamplingStats(
        frameCount: n,
        durationMs: 0,
        measuredFps: 0,
        medianIntervalMs: 0,
        droppedFrames: 0,
      );
    }
    final duration = timestampsMs.last - timestampsMs.first;
    final intervals = [
      for (var i = 1; i < n; i++) timestampsMs[i] - timestampsMs[i - 1],
    ];
    final medianInterval = median(intervals);
    var dropped = 0;
    if (medianInterval > 0) {
      for (final interval in intervals) {
        if (interval > medianInterval * SignalConfig.droppedFrameIntervalFactor) {
          dropped += math.max(1, (interval / medianInterval).round() - 1);
        }
      }
    }
    return SamplingStats(
      frameCount: n,
      durationMs: duration,
      measuredFps: duration > 0 ? (n - 1) * 1000 / duration : 0,
      medianIntervalMs: medianInterval,
      droppedFrames: dropped,
    );
  }
}

/// Post-capture signal quality assessment.
class SignalQualityReport {
  /// Creates a report.
  const SignalQualityReport({
    required this.score,
    required this.level,
    required this.fingerCoverage,
    required this.saturationFraction,
    required this.stabilityOk,
    required this.spectralConfidenceRed,
    required this.spectralConfidenceGreen,
    required this.estimatedHeartRateBpm,
    required this.preferredChannel,
    required this.sampling,
    required this.issues,
  });

  /// Overall score, 0 (unusable) – 100 (excellent).
  final int score;

  /// Traffic-light classification of [score].
  final QualityLevel level;

  /// Fraction of frames (0–1) in which a fingertip covered the lens.
  final double fingerCoverage;

  /// Fraction of frames (0–1) with a clipped red channel.
  final double saturationFraction;

  /// Whether the Sphygma backend stability check passed.
  final bool stabilityOk;

  /// Pulse confidence (0–1) of the red channel.
  final double spectralConfidenceRed;

  /// Pulse confidence (0–1) of the green channel.
  final double spectralConfidenceGreen;

  /// Spectral heart-rate estimate from the preferred channel, if any.
  final double? estimatedHeartRateBpm;

  /// Channel with the stronger pulse.
  final PpgChannel preferredChannel;

  /// Frame timing statistics.
  final SamplingStats sampling;

  /// Problems found (empty = none).
  final List<QualityIssue> issues;

  /// Best of the two channel confidences.
  double get spectralConfidence =>
      math.max(spectralConfidenceRed, spectralConfidenceGreen);
}

/// Output of [SignalQualityAnalyzer.analyze]: report plus filtered waveforms
/// for display.
class SignalAnalysis {
  /// Creates an analysis result.
  const SignalAnalysis({
    required this.report,
    required this.filteredRed,
    required this.filteredGreen,
  });

  /// Quality report.
  final SignalQualityReport report;

  /// Band-passed red signal, or `null` if it could not be filtered.
  final List<double>? filteredRed;

  /// Band-passed green signal, or `null` if it could not be filtered.
  final List<double>? filteredGreen;
}

/// Scores a complete recording.
///
/// Score = 100 × (0.40·finger coverage + 0.40·pulse confidence +
/// 0.20·stability) − up to 20 points for sensor saturation, where
///  * finger coverage uses Sphygma's finger rules on every frame,
///  * pulse confidence is the backend heart-rate confidence (Welch peak-to-mean
///    power in 40–200 bpm, 8 s windows, 2 s stride) on the backend-preprocessed
///    signal, best of red/green,
///  * stability is the backend `check_signal_quality` on the raw red signal.
class SignalQualityAnalyzer {
  /// Creates an analyzer. [detector] is injectable for testing.
  const SignalQualityAnalyzer({FingerDetector detector = const FingerDetector()})
    : _detector = detector;

  final FingerDetector _detector;

  /// Analyses [samples] (ascending timestamps).
  SignalAnalysis analyze(List<PpgSample> samples) {
    final sampling = SamplingStats.fromTimestamps([
      for (final s in samples) s.timestampMs,
    ]);
    final red = [for (final s in samples) s.red];
    final green = [for (final s in samples) s.green];
    final issues = <QualityIssue>[];

    if (samples.length < SignalConfig.minFilterableSamples ||
        sampling.measuredFps <= 0) {
      return SignalAnalysis(
        report: SignalQualityReport(
          score: 0,
          level: QualityLevel.poor,
          fingerCoverage: _fingerCoverage(samples),
          saturationFraction: _saturationFraction(red),
          stabilityOk: false,
          spectralConfidenceRed: 0,
          spectralConfidenceGreen: 0,
          estimatedHeartRateBpm: null,
          preferredChannel: PpgChannel.green,
          sampling: sampling,
          issues: const [QualityIssue.tooShort],
        ),
        filteredRed: null,
        filteredGreen: null,
      );
    }

    final fs = sampling.measuredFps;
    final coverage = _fingerCoverage(samples);
    final saturation = _saturationFraction(red);
    final stability = _stabilityIssue(red);
    final filteredRed = _tryPreprocess(red, fs);
    final filteredGreen = _tryPreprocess(green, fs);
    final redPulse = _pulseEstimate(filteredRed, fs);
    final greenPulse = _pulseEstimate(filteredGreen, fs);

    // Ties go to green, matching the backend's heart-rate channel preference.
    final preferRed = redPulse.confidence > greenPulse.confidence;
    final preferred = preferRed ? redPulse : greenPulse;
    final confidence = preferred.confidence;

    if (coverage < SignalConfig.minGoodCoverage) {
      issues.add(QualityIssue.lowFingerCoverage);
    }
    if (stability != null) issues.add(stability);
    if (confidence < SignalConfig.minGoodSpectralConfidence) {
      issues.add(QualityIssue.weakPulse);
    }
    if (saturation > SignalConfig.maxGoodSaturation) {
      issues.add(QualityIssue.overexposed);
    }
    if (sampling.frameCount > 0 &&
        sampling.droppedFrames / sampling.frameCount >
            SignalConfig.maxGoodDroppedFraction) {
      issues.add(QualityIssue.droppedFrames);
    }

    final raw =
        100 *
            (SignalConfig.weightCoverage * coverage +
                SignalConfig.weightSpectral * confidence +
                SignalConfig.weightStability * (stability == null ? 1 : 0)) -
        SignalConfig.saturationPenaltyPoints * saturation;
    final score = raw.round().clamp(0, 100);

    return SignalAnalysis(
      report: SignalQualityReport(
        score: score,
        level: levelForScore(score),
        fingerCoverage: coverage,
        saturationFraction: saturation,
        stabilityOk: stability == null,
        spectralConfidenceRed: redPulse.confidence,
        spectralConfidenceGreen: greenPulse.confidence,
        estimatedHeartRateBpm: preferred.heartRateBpm,
        preferredChannel: preferRed ? PpgChannel.red : PpgChannel.green,
        sampling: sampling,
        issues: List.unmodifiable(issues),
      ),
      filteredRed: filteredRed,
      filteredGreen: filteredGreen,
    );
  }

  /// Maps a 0–100 score to a [QualityLevel].
  static QualityLevel levelForScore(int score) {
    if (score >= SignalConfig.goodScoreThreshold) return QualityLevel.good;
    if (score >= SignalConfig.fairScoreThreshold) return QualityLevel.fair;
    return QualityLevel.poor;
  }

  double _fingerCoverage(List<PpgSample> samples) {
    if (samples.isEmpty) return 0;
    final window = <double>[];
    var covered = 0;
    for (final s in samples) {
      window.add(s.red);
      if (window.length > SignalConfig.fingerVarianceWindow) window.removeAt(0);
      if (_detector.isFingerPresent(RgbMean(s.red, s.green, s.blue), window)) {
        covered++;
      }
    }
    return covered / samples.length;
  }

  double _saturationFraction(List<double> red) {
    if (red.isEmpty) return 0;
    final clipped = red.where((v) => v >= SignalConfig.saturationRedLevel);
    return clipped.length / red.length;
  }

  /// Backend `check_signal_quality`; returns the failing issue or `null`.
  QualityIssue? _stabilityIssue(List<double> red) {
    final m = mean(red);
    for (var i = 1; i < red.length; i++) {
      if ((red[i] - red[i - 1]).abs() > m * SignalConfig.jumpFractionOfMean) {
        return QualityIssue.exposureJump;
      }
    }
    if (standardDeviation(red) > m * SignalConfig.noiseStdFractionOfMean) {
      return QualityIssue.excessiveNoise;
    }
    return null;
  }

  List<double>? _tryPreprocess(List<double> signal, double fs) {
    try {
      return preprocessHeartRateSignal(signal, sampleRateHz: fs);
    } on ArgumentError {
      return null;
    }
  }

  _PulseEstimate _pulseEstimate(List<double>? filtered, double fs) {
    if (filtered == null) return const _PulseEstimate(0, null);
    final window = (SignalConfig.spectralWindowSeconds * fs).round();
    final stride = math.max(1, (SignalConfig.spectralStrideSeconds * fs).round());
    final segments = <List<double>>[
      for (var start = 0; start + window < filtered.length; start += stride)
        filtered.sublist(start, start + window),
    ];
    // Backend falls back to the whole signal when no full window fits.
    if (segments.isEmpty) segments.add(filtered);

    final confidences = <double>[];
    final frequencies = <double>[];
    for (final segment in segments) {
      final segmentLength = math.min(segment.length, SignalConfig.welchMaxSegment);
      if (segmentLength < 2) continue;
      final peak = dominantPeakInBand(
        welch(segment, sampleRateHz: fs, segmentLength: segmentLength),
        lowHz: SignalConfig.minHeartRateBpm / 60,
        highHz: SignalConfig.maxHeartRateBpm / 60,
      );
      if (peak == null) continue;
      confidences.add(peak.confidence);
      frequencies.add(peak.frequencyHz);
    }
    if (confidences.isEmpty) return const _PulseEstimate(0, null);
    return _PulseEstimate(mean(confidences), median(frequencies) * 60);
  }
}

class _PulseEstimate {
  const _PulseEstimate(this.confidence, this.heartRateBpm);

  final double confidence;
  final double? heartRateBpm;
}
