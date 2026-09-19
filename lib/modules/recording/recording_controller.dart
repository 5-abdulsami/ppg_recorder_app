import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/app_routes.dart';
import '../../core/constants/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../data/models/processed_recording.dart';
import '../../data/models/recording_session.dart';
import '../../data/repositories/recording_repository.dart';
import '../../data/services/camera_frame_sampler.dart';
import '../../data/services/camera_service.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/permission_service.dart';
import '../../data/services/ppg_extraction_service.dart';
import '../../signal/live_quality_monitor.dart';
import '../../signal/models/quality_level.dart';

/// Stages of the recording screen.
enum RecordingPhase {
  /// Checking storage/permission and opening the camera.
  initializing,

  /// Camera permission refused (can ask again).
  permissionDenied,

  /// Camera permission blocked (settings required).
  permissionPermanentlyDenied,

  /// A recoverable error occurred (see [RecordingController.error]).
  error,

  /// Torch on, waiting for a steady fingertip.
  waitingForFinger,

  /// Locking exposure and starting the recorder.
  starting,

  /// Recording the 30 s video.
  recording,

  /// Stopping the recorder and storing the video.
  finishing,

  /// Decoding the video and extracting the PPG signal.
  processing,
}

/// Informational banners shown while waiting/recording.
enum RecordingNotice {
  /// A recording was aborted because the app lost the foreground.
  interrupted,

  /// A recording was restarted because the finger left the lens.
  fingerRemoved,

  /// Live frames are unavailable while recording on this device.
  liveUnavailable,
}

/// Drives capture: permission → camera + torch → wait for a steady finger →
/// lock exposure → record 30 s → decode video → hand off to results.
///
/// Guarantees: an aborted or failed attempt never leaves a video behind, and
/// stale async continuations (after interruption or exit) are ignored via a
/// generation counter.
class RecordingController extends GetxController with WidgetsBindingObserver {
  /// Creates the controller.
  RecordingController({
    required CameraService camera,
    required PermissionService permissions,
    required PpgExtractionService extraction,
    required RecordingRepository repository,
    required HapticsService haptics,
    LiveQualityMonitor? monitor,
    CameraFrameSampler sampler = const CameraFrameSampler(),
  }) : _camera = camera,
       _permissions = permissions,
       _extraction = extraction,
       _repository = repository,
       _haptics = haptics,
       _monitor = monitor ?? LiveQualityMonitor(),
       _sampler = sampler;

  final CameraService _camera;
  final PermissionService _permissions;
  final PpgExtractionService _extraction;
  final RecordingRepository _repository;
  final HapticsService _haptics;
  final LiveQualityMonitor _monitor;
  final CameraFrameSampler _sampler;

  // ── Observable state ─────────────────────────────────────────────────────

  /// Current stage.
  final Rx<RecordingPhase> phase = RecordingPhase.initializing.obs;

  /// Whether [cameraController] can be used to build a preview.
  final RxBool cameraReady = false.obs;

  /// Debounced live quality level (`null` = unknown / unavailable).
  final Rxn<QualityLevel> liveLevel = Rxn<QualityLevel>();

  /// Issue behind [liveLevel].
  final Rx<LiveQualityIssue> liveIssue = LiveQualityIssue.none.obs;

  /// Whether a finger is detected in the latest frame.
  final RxBool fingerPresent = false.obs;

  /// Whether live frames are available (false on some devices while
  /// recording).
  final RxBool liveAvailable = true.obs;

  /// Seconds left in the recording.
  final RxDouble remainingSeconds =
      (AppConfig.recordingDuration.inMilliseconds / 1000).obs;

  /// Recording progress, 0–1.
  final RxDouble recordingProgress = 0.0.obs;

  /// Video decoding progress, 0–1.
  final RxDouble extractionProgress = 0.0.obs;

  /// Banner to show, if any.
  final Rxn<RecordingNotice> notice = Rxn<RecordingNotice>();

  /// Error shown in [RecordingPhase.error].
  final Rxn<AppException> error = Rxn<AppException>();

  /// Camera controller for the preview (valid while [cameraReady]).
  CameraController? get cameraController => _camera.controller;

  /// Patient/session info, or `null` if the route was opened without it.
  RecordingSession? get session => _session;

  // ── Internal state ───────────────────────────────────────────────────────

  RecordingSession? _session;
  int _generation = 0;
  bool _closed = false;
  bool _needsReinit = false;
  bool _permissionPromptActive = false;
  Timer? _ticker;
  final Stopwatch _recordingClock = Stopwatch();
  final Stopwatch _uptime = Stopwatch();
  Duration? _lastFrameAt;
  DateTime? _recordingStartedAt;
  CameraLockResult _locks = const CameraLockResult(
    exposure: false,
    focus: false,
  );
  CameraController? _listenedController;

  bool _isStale(int generation) => _closed || generation != _generation;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args is RecordingSession) {
      _session = args;
    } else {
      // Opened without a session (e.g. after a hot restart): go home.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => Get.offAllNamed<void>(AppRoutes.setup),
      );
      return;
    }
    _uptime.start();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_setWakelock(enabled: true));
  }

  @override
  void onReady() {
    super.onReady();
    if (_session != null) unawaited(_initialize());
  }

  @override
  void onClose() {
    _closed = true;
    _generation++;
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _detachCameraListener();
    unawaited(_camera.dispose());
    unawaited(_setWakelock(enabled: false));
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closed || _session == null) return;
    final capturing =
        phase.value == RecordingPhase.starting ||
        phase.value == RecordingPhase.recording;
    switch (state) {
      case AppLifecycleState.inactive:
        // iOS reports calls / system overlays as "inactive"; Android also
        // uses it for mere focus loss (e.g. notification shade), which does
        // not stop the camera, so only iOS aborts here.
        if (Platform.isIOS && capturing) _interrupt();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (_permissionPromptActive) return;
        if (capturing) {
          _interrupt();
        } else if (phase.value == RecordingPhase.waitingForFinger ||
            phase.value == RecordingPhase.initializing) {
          _suspend();
        }
      case AppLifecycleState.resumed:
        if (_needsReinit) {
          _needsReinit = false;
          unawaited(_initialize());
        } else if (phase.value == RecordingPhase.permissionDenied ||
            phase.value == RecordingPhase.permissionPermanentlyDenied) {
          unawaited(_recheckPermission());
        }
    }
  }

  // ── Public actions ───────────────────────────────────────────────────────

  /// Retries after an error or a denied permission.
  Future<void> retry() => _initialize();

  /// Opens system settings (for a permanently denied permission).
  Future<void> openSettings() => _permissions.openSettings();

  /// Whether the user may leave the screen now.
  bool get canLeave =>
      phase.value != RecordingPhase.finishing &&
      phase.value != RecordingPhase.processing;

  /// Aborts any capture (deleting the partial video) and leaves the screen.
  Future<void> cancelAndExit() async {
    if (!canLeave) return;
    _generation++;
    _ticker?.cancel();
    await _releaseCamera();
    if (!_closed) Get.back<void>();
  }

  // ── Initialisation ───────────────────────────────────────────────────────

  Future<void> _initialize() async {
    final generation = ++_generation;
    _ticker?.cancel();
    _resetCountdown();
    _monitor.reset();
    error.value = null;
    liveLevel.value = null;
    liveAvailable.value = true;
    phase.value = RecordingPhase.initializing;
    await _releaseCamera();
    if (_isStale(generation)) return;

    if (!await _repository.hasSufficientStorage()) {
      if (_isStale(generation)) return;
      _showError(const AppException(AppErrorType.insufficientStorage));
      return;
    }
    if (_isStale(generation)) return;

    final CameraPermissionStatus permission;
    _permissionPromptActive = true;
    try {
      permission = await _permissions.requestCamera();
    } finally {
      _permissionPromptActive = false;
    }
    if (_isStale(generation)) return;
    if (permission != CameraPermissionStatus.granted) {
      phase.value = permission == CameraPermissionStatus.denied
          ? RecordingPhase.permissionDenied
          : RecordingPhase.permissionPermanentlyDenied;
      return;
    }

    try {
      await _camera.initialize();
      if (_isStale(generation)) return;
      await _camera.setTorch(on: true);
      if (_isStale(generation)) return;
      await _camera.startFrameStream(_onFrame);
      if (_isStale(generation)) return;
      _attachCameraListener();
      cameraReady.value = true;
      phase.value = RecordingPhase.waitingForFinger;
    } on AppException catch (e) {
      if (_isStale(generation)) return;
      await _releaseCamera();
      _showError(e);
    }
  }

  Future<void> _recheckPermission() async {
    final generation = _generation;
    final status = await _permissions.checkCamera();
    if (_isStale(generation)) return;
    if (status == CameraPermissionStatus.granted) await _initialize();
  }

  // ── Frame handling ───────────────────────────────────────────────────────

  void _onFrame(CameraImage image) {
    if (_closed) return;
    final current = phase.value;
    if (current != RecordingPhase.waitingForFinger &&
        current != RecordingPhase.recording) {
      return;
    }
    final rgb = _sampler.sample(image);
    if (rgb == null) return;
    _lastFrameAt = _uptime.elapsed;

    final reading = _monitor.addSample(rgb);
    liveLevel.value = reading.level;
    liveIssue.value = reading.issue;
    fingerPresent.value = reading.fingerPresent;

    if (current == RecordingPhase.waitingForFinger &&
        _monitor.consecutiveFingerFrames >= AppConfig.fingerStableFrames) {
      unawaited(_beginRecording());
    } else if (current == RecordingPhase.recording &&
        _monitor.consecutiveMissingFrames > AppConfig.fingerLostGraceFrames) {
      unawaited(_restartAfterFingerLoss());
    }
  }

  // ── Recording ────────────────────────────────────────────────────────────

  Future<void> _beginRecording() async {
    if (phase.value != RecordingPhase.waitingForFinger) return;
    phase.value = RecordingPhase.starting;
    final generation = _generation;
    try {
      _locks = await _camera.lockExposureAndFocus();
      if (_isStale(generation)) return;
      final streaming = await _camera.startRecording(onFrame: _onFrame);
      if (_isStale(generation)) return;

      _monitor.reset();
      _lastFrameAt = null;
      _recordingStartedAt = DateTime.now();
      _recordingClock
        ..reset()
        ..start();
      _resetCountdown();
      liveAvailable.value = streaming;
      if (streaming) {
        notice.value = null;
      } else {
        liveLevel.value = null;
        notice.value = RecordingNotice.liveUnavailable;
      }
      phase.value = RecordingPhase.recording;
      unawaited(_haptics.recordingStarted());
      _ticker = Timer.periodic(AppConfig.countdownTick, (_) => _onTick());
    } on AppException catch (e) {
      if (_isStale(generation)) return;
      await _releaseCamera();
      _showError(e);
    }
  }

  void _onTick() {
    if (phase.value != RecordingPhase.recording) return;
    final total = AppConfig.recordingDuration;
    final elapsed = _recordingClock.elapsed;
    recordingProgress.value = (elapsed.inMicroseconds / total.inMicroseconds)
        .clamp(0.0, 1.0);
    final left = (total - elapsed).inMilliseconds / 1000;
    remainingSeconds.value = left < 0 ? 0 : left;

    if (liveAvailable.value && elapsed > AppConfig.liveFrameTimeout) {
      final last = _lastFrameAt;
      final silentFor = last == null ? elapsed : _uptime.elapsed - last;
      if (silentFor > AppConfig.liveFrameTimeout) {
        liveAvailable.value = false;
        liveLevel.value = null;
        notice.value = RecordingNotice.liveUnavailable;
      }
    }
    if (elapsed >= total) unawaited(_finishRecording());
  }

  Future<void> _restartAfterFingerLoss() async {
    if (phase.value != RecordingPhase.recording) return;
    phase.value = RecordingPhase.starting;
    _ticker?.cancel();
    _recordingClock.stop();
    final generation = _generation;
    unawaited(_haptics.warning());
    try {
      await _camera.cancelRecording();
      if (_isStale(generation)) return;
      await _camera.unlockExposureAndFocus();
      if (_isStale(generation)) return;
      await _camera.setTorch(on: true);
      if (_isStale(generation)) return;
      _monitor.reset();
      liveAvailable.value = true;
      await _camera.startFrameStream(_onFrame);
      if (_isStale(generation)) return;
      _resetCountdown();
      notice.value = RecordingNotice.fingerRemoved;
      phase.value = RecordingPhase.waitingForFinger;
    } on AppException catch (e) {
      if (_isStale(generation)) return;
      await _releaseCamera();
      _showError(e);
    }
  }

  Future<void> _finishRecording() async {
    if (phase.value != RecordingPhase.recording) return;
    phase.value = RecordingPhase.finishing;
    _ticker?.cancel();
    _recordingClock.stop();
    final generation = _generation;
    final session = _session!;
    final startedAt = _recordingStartedAt ?? DateTime.now();
    String? pendingPath;
    try {
      final cameraPath = await _camera.stopRecording();
      unawaited(_haptics.recordingStopped());
      await _releaseCamera();
      if (_isStale(generation)) {
        await _repository.discardPendingVideo(cameraPath);
        return;
      }
      pendingPath = await _repository.adoptPendingVideo(cameraPath);
      if (_isStale(generation)) {
        await _repository.discardPendingVideo(pendingPath);
        return;
      }

      extractionProgress.value = 0;
      phase.value = RecordingPhase.processing;
      final result = await _extraction.extract(
        pendingPath,
        onProgress: (value) => extractionProgress.value = value,
      );
      if (_isStale(generation)) {
        await _repository.discardPendingVideo(pendingPath);
        return;
      }
      extractionProgress.value = 1;

      final recording = ProcessedRecording(
        session: session,
        startedAt: startedAt,
        pendingVideoPath: pendingPath,
        samples: result.samples,
        analysis: result.analysis,
        video: result.video,
        capture: CaptureInfo(
          resolutionPreset: _camera.resolutionPresetName,
          targetFps: AppConfig.targetFps,
          exposureLocked: _locks.exposure,
          focusLocked: _locks.focus,
          liveMonitoringAvailable: liveAvailable.value,
        ),
      );
      Get.offNamed<void>(AppRoutes.results, arguments: recording);
    } on AppException catch (e) {
      if (pendingPath != null) {
        await _repository.discardPendingVideo(pendingPath);
      }
      if (_isStale(generation)) return;
      await _releaseCamera();
      _showError(e);
    }
  }

  // ── Interruptions ────────────────────────────────────────────────────────

  /// App lost the foreground mid-capture: abort (the camera service deletes
  /// the partial video) and re-initialise on resume.
  void _interrupt() {
    _generation++;
    _ticker?.cancel();
    _recordingClock.stop();
    _needsReinit = true;
    notice.value = RecordingNotice.interrupted;
    phase.value = RecordingPhase.initializing;
    unawaited(_releaseCamera());
  }

  /// App backgrounded while idle: release the camera, reopen on resume.
  void _suspend() {
    _generation++;
    _needsReinit = true;
    phase.value = RecordingPhase.initializing;
    unawaited(_releaseCamera());
  }

  void _attachCameraListener() {
    _detachCameraListener();
    final c = _camera.controller;
    if (c == null) return;
    _listenedController = c;
    c.addListener(_onCameraValueChanged);
  }

  void _detachCameraListener() {
    _listenedController?.removeListener(_onCameraValueChanged);
    _listenedController = null;
  }

  /// Camera failed at runtime (e.g. disconnected by the system).
  void _onCameraValueChanged() {
    final c = _listenedController;
    if (c == null || !c.value.hasError || _closed) return;
    final current = phase.value;
    if (current != RecordingPhase.waitingForFinger &&
        current != RecordingPhase.starting &&
        current != RecordingPhase.recording) {
      return;
    }
    final details = c.value.errorDescription;
    _generation++;
    _ticker?.cancel();
    unawaited(
      _releaseCamera().then((_) {
        if (_closed) return;
        _showError(
          AppException(
            current == RecordingPhase.waitingForFinger
                ? AppErrorType.cameraInitFailed
                : AppErrorType.recordingFailed,
            details: details,
          ),
        );
      }),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Hides the preview, waits for it to leave the tree, then releases the
  /// camera (stopping torch/stream and deleting any in-progress recording).
  Future<void> _releaseCamera() async {
    _detachCameraListener();
    if (cameraReady.value) {
      cameraReady.value = false;
      try {
        await WidgetsBinding.instance.endOfFrame.timeout(
          const Duration(milliseconds: 150),
        );
      } on TimeoutException {
        // App is backgrounded (no frames); the preview is not being drawn.
      }
    }
    await _camera.dispose();
  }

  void _showError(AppException e) {
    switch (e.type) {
      case AppErrorType.cameraPermissionDenied:
        phase.value = RecordingPhase.permissionDenied;
      case AppErrorType.cameraPermissionPermanentlyDenied:
        phase.value = RecordingPhase.permissionPermanentlyDenied;
      default:
        error.value = e;
        phase.value = RecordingPhase.error;
    }
  }

  void _resetCountdown() {
    recordingProgress.value = 0;
    remainingSeconds.value = AppConfig.recordingDuration.inMilliseconds / 1000;
  }

  static Future<void> _setWakelock({required bool enabled}) async {
    try {
      await (enabled ? WakelockPlus.enable() : WakelockPlus.disable());
    } catch (_) {
      // Keeping the screen on is best effort.
    }
  }
}
