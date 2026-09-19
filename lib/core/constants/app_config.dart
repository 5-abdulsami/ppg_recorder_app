/// App-level (non-signal) configuration constants.
///
/// Signal-processing parameters live in `signal/signal_config.dart`.
abstract final class AppConfig {
  /// Recording length.
  static const Duration recordingDuration = Duration(seconds: 30);

  /// Requested camera frame rate.
  static const int targetFps = 30;

  /// Requested video bitrate (bps). High, to minimise compression artefacts
  /// in the saved video (honoured on iOS; Android uses the CameraX default).
  static const int videoBitrate = 8000000;

  /// Consecutive finger frames (≈ 1 s at 30 fps) required before recording
  /// starts, giving auto-exposure time to settle before it is locked
  /// (Sphygma uses the same value).
  static const int fingerStableFrames = 30;

  /// Consecutive missing-finger frames (≈ 0.5 s) tolerated during recording
  /// before it is restarted (Sphygma grace period).
  static const int fingerLostGraceFrames = 15;

  /// Delay after setting the metering point before locking exposure.
  static const Duration meteringSettleDelay = Duration(milliseconds: 300);

  /// If no live frame arrives for this long during recording, the live
  /// indicator is reported as unavailable.
  static const Duration liveFrameTimeout = Duration(milliseconds: 1500);

  /// Countdown refresh interval.
  static const Duration countdownTick = Duration(milliseconds: 100);

  /// Minimum free storage required before recording (video + CSV + margin).
  static const int minFreeStorageBytes = 100 * 1024 * 1024;

  /// Minimum decoded frames for a recording to be considered valid (≈ 5 s).
  static const int minValidFrames = 150;

  /// Maximum patient ID length.
  static const int patientIdMaxLength = 40;

  /// Maximum notes length.
  static const int notesMaxLength = 500;

  /// Folder (inside app storage) holding saved recordings.
  static const String recordingsFolderName = 'PPG_Recordings';

  /// Folder (inside app support storage) for unsaved videos.
  static const String pendingFolderName = 'pending_videos';

  /// Timestamp format used in file names.
  static const String fileTimestampFormat = 'yyyyMMdd_HHmmss';

  /// Version of the metadata JSON layout.
  static const int metadataSchemaVersion = 1;

  /// Maximum content width on large screens (tablets).
  static const double maxContentWidth = 600;
}
