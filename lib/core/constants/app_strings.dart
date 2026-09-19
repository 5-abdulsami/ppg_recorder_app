import '../../signal/live_quality_monitor.dart';
import '../../signal/models/quality_level.dart';
import '../../signal/signal_quality_analyzer.dart';
import '../errors/app_exception.dart';
import '../utils/patient_id_validator.dart';
import 'app_config.dart';

/// Every user-facing string in the app.
abstract final class AppStrings {
  // ── App ──────────────────────────────────────────────────────────────────
  static const String appName = 'PPG Recorder';

  // ── Setup screen ─────────────────────────────────────────────────────────
  static const String setupTitle = 'New Recording';
  static const String setupHeadline = 'Fingertip PPG capture';
  static const String setupSubtitle =
      'Records a 30-second rear-camera video with the flash on and extracts '
      'the raw red, green and blue PPG signal on this device.';
  static const String patientIdLabel = 'Patient ID';
  static const String patientIdHint = 'e.g. P001';
  static const String patientIdHelper = 'Letters, numbers, "-" and "_" only';
  static const String notesLabel = 'Notes (optional)';
  static const String notesHint = 'Posture, conditions, anything relevant…';
  static const String startRecording = 'Start Recording';
  static const String checkingStorage = 'Checking storage…';
  static const String saveLocationLabel = 'Files are saved to';
  static const String instructionsTitle = 'Before you start';
  static const List<String> instructionsSteps = [
    'Sit still and rest the hand on a table.',
    'Cover the rear camera lens AND the flash completely with a fingertip.',
    'Press gently — too much pressure blocks blood flow.',
    'Recording starts automatically once the finger is steady.',
  ];

  static String patientIdError(PatientIdError error) => switch (error) {
    PatientIdError.empty => 'Please enter a patient ID.',
    PatientIdError.tooLong =>
      'Use at most ${AppConfig.patientIdMaxLength} characters.',
    PatientIdError.invalidCharacters =>
      'Only letters, numbers, "-" and "_" are allowed.',
  };

  // ── Recording screen ─────────────────────────────────────────────────────
  static const String recordingTitle = 'Recording';
  static const String placeFinger =
      'Place fingertip fully over camera lens and flash';
  static const String holdStill = 'Finger detected — hold still…';
  static const String preparing = 'Preparing camera…';
  static const String startingRecording = 'Starting recording…';
  static const String recordingInProgress = 'Recording — keep still';
  static const String finishing = 'Finishing recording…';
  static const String secondsLeftSuffix = 's';
  static const String cancel = 'Cancel';
  static const String processingTitle = 'Extracting PPG signal';
  static const String processingSubtitle =
      'Decoding every video frame. This takes a few seconds.';
  static const String liveQualityLabel = 'Signal';
  static const String noticeInterrupted =
      'Recording was interrupted — nothing was saved. Place your finger to '
      'start again.';
  static const String noticeFingerRemoved =
      'Finger moved off the lens — recording restarted. Nothing was saved.';
  static const String noticeLiveUnavailable =
      'Live signal check is not supported on this device while recording. '
      'The signal is checked after capture.';
  static const String retry = 'Retry';
  static const String retake = 'Retake';
  static const String goBack = 'Go Back';
  static const String openSettings = 'Open Settings';
  static const String grantPermission = 'Grant Permission';

  static String liveQualityText(QualityLevel level, LiveQualityIssue issue) {
    return switch (issue) {
      LiveQualityIssue.noFinger => 'No finger — cover lens & flash',
      LiveQualityIssue.motion =>
        level == QualityLevel.poor ? 'Too much movement' : 'Slight movement',
      LiveQualityIssue.overexposed => 'Too bright — adjust finger',
      LiveQualityIssue.none => 'Good signal',
    };
  }

  static const String liveQualityUnavailable = 'Live check unavailable';
  static const String liveQualityWaiting = 'Waiting for camera…';

  // ── Errors ───────────────────────────────────────────────────────────────
  static String errorTitle(AppErrorType type) => switch (type) {
    AppErrorType.cameraPermissionDenied => 'Camera access needed',
    AppErrorType.cameraPermissionPermanentlyDenied => 'Camera access blocked',
    AppErrorType.cameraUnavailable => 'No rear camera',
    AppErrorType.cameraInitFailed => 'Camera failed to start',
    AppErrorType.torchUnavailable => 'Flash unavailable',
    AppErrorType.recordingFailed => 'Recording failed',
    AppErrorType.insufficientStorage => 'Not enough storage',
    AppErrorType.extractionFailed => 'Signal extraction failed',
    AppErrorType.videoTooShort => 'Recording too short',
    AppErrorType.saveFailed => 'Saving failed',
  };

  static String errorMessage(AppErrorType type) => switch (type) {
    AppErrorType.cameraPermissionDenied =>
      'PPG Recorder needs the camera to record the fingertip video. '
          'Please allow camera access.',
    AppErrorType.cameraPermissionPermanentlyDenied =>
      'Camera access was denied. Enable it for PPG Recorder in the system '
          'settings, then come back.',
    AppErrorType.cameraUnavailable =>
      'This device has no usable rear camera, so it cannot record PPG.',
    AppErrorType.cameraInitFailed =>
      'The camera could not be started. Close other apps using the camera '
          'and try again.',
    AppErrorType.torchUnavailable =>
      'The flash could not be switched on. A flash is required to light the '
          'fingertip. Close other apps using the camera and try again.',
    AppErrorType.recordingFailed =>
      'The video could not be recorded. Nothing was saved. Please try again.',
    AppErrorType.insufficientStorage =>
      'Free up at least ${AppConfig.minFreeStorageBytes ~/ (1024 * 1024)} MB '
          'of storage before recording.',
    AppErrorType.extractionFailed =>
      'The PPG signal could not be extracted from the video. Nothing was '
          'saved. Please retake the recording.',
    AppErrorType.videoTooShort =>
      'The video contained too few frames to extract a signal. Nothing was '
          'saved. Please retake the recording.',
    AppErrorType.saveFailed =>
      'The files could not be saved. The recording is still here — try '
          'saving again.',
  };

  static const String technicalDetails = 'Details';

  // ── Results screen ───────────────────────────────────────────────────────
  static const String resultsTitle = 'Results';
  static const String signalQuality = 'Signal quality';
  static const String waveformTitle = 'PPG waveform';
  static const String channelRed = 'Red';
  static const String channelGreen = 'Green';
  static const String viewFiltered = 'Filtered';
  static const String viewRaw = 'Raw';
  static const String filteredCaption =
      'Band-pass 0.7–3.0 Hz — display only. The CSV '
      'stores raw values.';
  static const String rawCaption = 'Raw ROI mean intensity (as saved in CSV).';
  static const String waveformUnavailable =
      'Waveform unavailable — the signal is too short or flat to filter.';
  static const String timeAxisUnit = 's';
  static const String summaryTitle = 'Summary';
  static const String metricDuration = 'Duration';
  static const String metricFrames = 'Frames';
  static const String metricFps = 'Frame rate';
  static const String metricHeartRate = 'Est. heart rate';
  static const String metricCoverage = 'Finger coverage';
  static const String metricDropped = 'Dropped frames';
  static const String notAvailable = '—';
  static const String saveAndExport = 'Save & Export';
  static const String discardAndRetake = 'Discard & Retake';
  static const String saving = 'Saving…';
  static const String recordAgainSamePatient = 'Record Again (Same Patient)';
  static const String newPatient = 'New Patient';
  static const String savedTitle = 'Recording saved';
  static const String savedMessage = 'Files were written to:';
  static const String close = 'Close';
  static const String liveCheckUnavailableNote =
      'Live finger check was unavailable during capture on this device.';

  static const String lowQualityTitle = 'Low signal quality';
  static String lowQualityMessage(int score) =>
      'The signal quality score is $score/100. The recording may not be '
      'usable. Save it anyway?';
  static const String saveAnyway = 'Save Anyway';

  static const String discardTitle = 'Discard recording?';
  static const String discardMessage =
      'The video and extracted signal will be deleted. This cannot be undone.';
  static const String discard = 'Discard';
  static const String keep = 'Keep';

  static String qualityLevelLabel(QualityLevel level) => switch (level) {
    QualityLevel.good => 'Good',
    QualityLevel.fair => 'Fair',
    QualityLevel.poor => 'Poor',
  };

  static String qualityIssueText(QualityIssue issue) => switch (issue) {
    QualityIssue.tooShort => 'Too few frames to analyse.',
    QualityIssue.lowFingerCoverage =>
      'Finger did not fully cover the lens for part of the recording.',
    QualityIssue.exposureJump =>
      'Sudden brightness jump (finger moved or exposure changed).',
    QualityIssue.excessiveNoise => 'Signal is very noisy (movement).',
    QualityIssue.weakPulse => 'No clear pulse detected.',
    QualityIssue.overexposed =>
      'Image too bright (clipped) for part of the recording.',
    QualityIssue.droppedFrames => 'Some video frames were dropped.',
  };

  static const String noIssues = 'No problems detected.';

  static String formatSeconds(double seconds) =>
      '${seconds.toStringAsFixed(1)} s';
  static String formatFps(double fps) => '${fps.toStringAsFixed(1)} fps';
  static String formatBpm(double bpm) => '${bpm.round()} bpm';
  static String formatPercent(double fraction) =>
      '${(fraction * 100).round()} %';
}
