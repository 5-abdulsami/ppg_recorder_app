import '../../signal/models/ppg_sample.dart';
import '../../signal/signal_quality_analyzer.dart';
import 'recording_session.dart';

/// Properties of the recorded video file.
class VideoInfo {
  /// Creates video info.
  const VideoInfo({
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.durationMs,
    required this.colorConversion,
    required this.decoderName,
  });

  /// Frame width (px).
  final int width;

  /// Frame height (px).
  final int height;

  /// Container rotation (degrees).
  final int rotationDegrees;

  /// Container duration (ms).
  final double durationMs;

  /// YUV→RGB conversion description.
  final String colorConversion;

  /// Platform decoder name.
  final String decoderName;
}

/// Camera conditions during capture.
class CaptureInfo {
  /// Creates capture info.
  const CaptureInfo({
    required this.resolutionPreset,
    required this.targetFps,
    required this.exposureLocked,
    required this.focusLocked,
    required this.liveMonitoringAvailable,
  });

  /// Camera resolution preset name.
  final String resolutionPreset;

  /// Requested frame rate.
  final int targetFps;

  /// Whether auto-exposure was locked before recording.
  final bool exposureLocked;

  /// Whether auto-focus was locked before recording.
  final bool focusLocked;

  /// Whether live frames (finger / motion checks) were available while
  /// recording.
  final bool liveMonitoringAvailable;
}

/// A captured and analysed recording that has not been saved yet.
///
/// The video lives in the app's private pending folder until saved or
/// discarded.
class ProcessedRecording {
  /// Creates a processed recording.
  const ProcessedRecording({
    required this.session,
    required this.startedAt,
    required this.pendingVideoPath,
    required this.samples,
    required this.analysis,
    required this.video,
    required this.capture,
  });

  /// Patient ID and notes.
  final RecordingSession session;

  /// Local wall-clock time recording started.
  final DateTime startedAt;

  /// Path of the unsaved video.
  final String pendingVideoPath;

  /// Raw per-frame RGB samples (the CSV rows).
  final List<PpgSample> samples;

  /// Quality report and filtered waveforms.
  final SignalAnalysis analysis;

  /// Video file properties.
  final VideoInfo video;

  /// Camera conditions.
  final CaptureInfo capture;
}
