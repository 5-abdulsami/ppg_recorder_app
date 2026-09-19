import '../../core/constants/app_config.dart';
import '../../signal/signal_config.dart';
import '../../signal/signal_quality_analyzer.dart';
import '../models/app_info.dart';
import '../models/processed_recording.dart';

/// Builds the companion metadata JSON object for a saved recording.
abstract final class RecordingMetadataBuilder {
  /// Returns a JSON-encodable map describing [recording].
  ///
  /// [csvFileName], [videoFileName] are the final file names (not paths).
  static Map<String, Object?> build({
    required ProcessedRecording recording,
    required AppInfo appInfo,
    required String csvFileName,
    required String videoFileName,
  }) {
    final report = recording.analysis.report;
    final sampling = report.sampling;
    return {
      'schema_version': AppConfig.metadataSchemaVersion,
      'patient_id': recording.session.patientId,
      'notes': recording.session.notes,
      'recording_started_at': _isoWithOffset(recording.startedAt),
      'recording_started_at_utc': recording.startedAt.toUtc().toIso8601String(),
      'video_duration_ms': _round(recording.video.durationMs, 1),
      'signal_duration_ms': _round(sampling.durationMs, 3),
      'target_fps': recording.capture.targetFps,
      'measured_fps': _round(sampling.measuredFps, 3),
      'total_frames': sampling.frameCount,
      'median_frame_interval_ms': _round(sampling.medianIntervalMs, 3),
      'dropped_frames_estimate': sampling.droppedFrames,
      'signal_quality': {
        'score': report.score,
        'level': report.level.id,
        'finger_coverage': _round(report.fingerCoverage, 4),
        'saturation_fraction': _round(report.saturationFraction, 4),
        'stability_check_passed': report.stabilityOk,
        'pulse_confidence_red': _round(report.spectralConfidenceRed, 4),
        'pulse_confidence_green': _round(report.spectralConfidenceGreen, 4),
        'preferred_channel': report.preferredChannel.name,
        'estimated_heart_rate_bpm': report.estimatedHeartRateBpm == null
            ? null
            : _round(report.estimatedHeartRateBpm!, 1),
        'issues': [for (final issue in report.issues) _issueId(issue)],
        'method':
            'score = 100*(0.40*finger_coverage + 0.40*max(pulse_confidence) '
            '+ 0.20*stability) - 20*saturation_fraction; pulse confidence = '
            'Welch peak/mean power ratio in 40-200 bpm on the detrended, '
            'band-passed (0.7-3.0 Hz) signal (8 s windows, 2 s stride)',
      },
      'extraction': {
        'source': 'recorded video (post-capture decode)',
        'method': 'mean of centred ${SignalConfig.roiSizePx}x'
            '${SignalConfig.roiSizePx} px ROI per decoded frame',
        'roi_size_px': SignalConfig.roiSizePx,
        'timestamps': 'video presentation timestamps relative to first frame',
        'color_conversion': recording.video.colorConversion,
        'decoder': recording.video.decoderName,
        'video_width': recording.video.width,
        'video_height': recording.video.height,
        'video_rotation_degrees': recording.video.rotationDegrees,
        'csv_values': 'raw (unfiltered) channel means, 0-255',
      },
      'capture': {
        'camera': 'rear',
        'torch': true,
        'resolution_preset': recording.capture.resolutionPreset,
        'exposure_locked': recording.capture.exposureLocked,
        'focus_locked': recording.capture.focusLocked,
        'live_quality_monitoring': recording.capture.liveMonitoringAvailable,
      },
      'files': {'csv': csvFileName, 'video': videoFileName},
      'app': {
        'name': appInfo.appName,
        'version': appInfo.version,
        'build_number': appInfo.buildNumber,
      },
      'device': {
        'platform': appInfo.platform,
        'os_version': appInfo.osVersion,
        'manufacturer': appInfo.manufacturer,
        'model': appInfo.model,
      },
    };
  }

  static String _issueId(QualityIssue issue) => switch (issue) {
    QualityIssue.tooShort => 'too_short',
    QualityIssue.lowFingerCoverage => 'low_finger_coverage',
    QualityIssue.exposureJump => 'exposure_jump',
    QualityIssue.excessiveNoise => 'excessive_noise',
    QualityIssue.weakPulse => 'weak_pulse',
    QualityIssue.overexposed => 'overexposed',
    QualityIssue.droppedFrames => 'dropped_frames',
  };

  /// Rounds for readability; non-finite values (which JSON cannot encode)
  /// become `null`.
  static double? _round(double value, int decimals) =>
      value.isFinite ? double.parse(value.toStringAsFixed(decimals)) : null;

  /// ISO-8601 local time with explicit UTC offset, e.g.
  /// `2026-09-19T14:03:22.120+05:00`.
  static String _isoWithOffset(DateTime time) {
    final local = time.toLocal();
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    final hours = abs.inHours.toString().padLeft(2, '0');
    final minutes = (abs.inMinutes % 60).toString().padLeft(2, '0');
    final base = local.toIso8601String();
    return '$base$sign$hours:$minutes';
  }
}
