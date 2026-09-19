import 'dart:isolate';

import '../../core/constants/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../signal/models/ppg_sample.dart';
import '../../signal/signal_config.dart';
import '../../signal/signal_quality_analyzer.dart';
import '../models/decoded_video_signal.dart';
import '../models/processed_recording.dart';
import 'native_platform_bridge.dart';

/// Result of extracting the PPG signal from a recorded video.
class PpgExtractionResult {
  /// Creates an extraction result.
  const PpgExtractionResult({
    required this.samples,
    required this.analysis,
    required this.video,
  });

  /// Raw per-frame samples, in presentation order.
  final List<PpgSample> samples;

  /// Quality report and filtered waveforms.
  final SignalAnalysis analysis;

  /// Video properties.
  final VideoInfo video;
}

/// Turns a recorded video into a raw PPG sample series and quality analysis.
///
/// Decoding is delegated to a [VideoSignalDecoder] (native); ordering,
/// validation and analysis are pure Dart so this service is testable with a
/// fake decoder.
class PpgExtractionService {
  /// Creates the service.
  const PpgExtractionService({
    required VideoSignalDecoder decoder,
    SignalQualityAnalyzer analyzer = const SignalQualityAnalyzer(),
  }) : _decoder = decoder,
       _analyzer = analyzer;

  final VideoSignalDecoder _decoder;
  final SignalQualityAnalyzer _analyzer;

  /// Extracts and analyses [videoPath]. [onProgress] reports decode progress
  /// in `[0, 1]`.
  ///
  /// Throws [AppException] with [AppErrorType.extractionFailed] or
  /// [AppErrorType.videoTooShort].
  Future<PpgExtractionResult> extract(
    String videoPath, {
    void Function(double progress)? onProgress,
  }) async {
    final decoded = await _decoder.decode(
      videoPath,
      roiSize: SignalConfig.roiSizePx,
      onProgress: onProgress,
    );
    final samples = buildSamples(decoded);
    if (samples.length < AppConfig.minValidFrames) {
      throw AppException(
        AppErrorType.videoTooShort,
        details: 'Decoded ${samples.length} frames '
            '(minimum ${AppConfig.minValidFrames}).',
      );
    }
    final analyzer = _analyzer;
    final SignalAnalysis analysis;
    try {
      analysis = await Isolate.run(() => analyzer.analyze(samples));
    } catch (e) {
      throw AppException(
        AppErrorType.extractionFailed,
        details: 'Signal analysis failed: $e',
        cause: e,
      );
    }
    return PpgExtractionResult(
      samples: samples,
      analysis: analysis,
      video: VideoInfo(
        width: decoded.width,
        height: decoded.height,
        rotationDegrees: decoded.rotationDegrees,
        durationMs: decoded.durationMs,
        colorConversion: decoded.colorConversion,
        decoderName: decoded.decoderName,
      ),
    );
  }

  /// Converts decoder output into samples: sorts by presentation time,
  /// drops duplicate timestamps and non-finite values, and rebases time to
  /// the first frame.
  static List<PpgSample> buildSamples(DecodedVideoSignal decoded) {
    final order = List<int>.generate(decoded.frameCount, (i) => i)
      ..sort((a, b) {
        final byTime = decoded.timestampsUs[a].compareTo(
          decoded.timestampsUs[b],
        );
        return byTime != 0 ? byTime : a.compareTo(b);
      });

    final samples = <PpgSample>[];
    int? firstUs;
    int? previousUs;
    for (final i in order) {
      final t = decoded.timestampsUs[i];
      final r = decoded.red[i];
      final g = decoded.green[i];
      final b = decoded.blue[i];
      if (t == previousUs) continue;
      if (!r.isFinite || !g.isFinite || !b.isFinite) continue;
      firstUs ??= t;
      previousUs = t;
      samples.add(
        PpgSample(
          frameIndex: samples.length,
          timestampMs: (t - firstUs) / 1000,
          red: r,
          green: g,
          blue: b,
        ),
      );
    }
    return samples;
  }
}
