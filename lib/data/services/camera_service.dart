import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/async_mutex.dart';

/// Which camera auto-routines were successfully locked.
class CameraLockResult {
  /// Creates a lock result.
  const CameraLockResult({required this.exposure, required this.focus});

  /// Auto-exposure locked.
  final bool exposure;

  /// Auto-focus locked.
  final bool focus;
}

/// Rear-camera control for fingertip PPG capture: torch, exposure lock,
/// live frame streaming and video recording.
///
/// All methods are safe to call in any order; implementations serialise
/// them internally.
abstract interface class CameraService {
  /// Active controller for building a preview, or `null` when released.
  CameraController? get controller;

  /// Name of the resolution preset used (for metadata).
  String get resolutionPresetName;

  /// Opens the rear camera. Throws [AppException].
  Future<void> initialize();

  /// Switches the torch on/off. Throws [AppException]
  /// ([AppErrorType.torchUnavailable]) if it cannot be switched on.
  Future<void> setTorch({required bool on});

  /// Meters on the lens centre, then locks auto-exposure and auto-focus.
  Future<CameraLockResult> lockExposureAndFocus();

  /// Restores automatic exposure and focus.
  Future<void> unlockExposureAndFocus();

  /// Starts delivering preview frames to [onFrame].
  Future<void> startFrameStream(void Function(CameraImage image) onFrame);

  /// Stops preview frame delivery.
  Future<void> stopFrameStream();

  /// Starts video recording. If [onFrame] is given, tries to also stream
  /// frames; returns whether streaming was enabled. Throws [AppException].
  Future<bool> startRecording({void Function(CameraImage image)? onFrame});

  /// Stops recording and returns the video file path. Throws [AppException].
  Future<String> stopRecording();

  /// Stops any recording and deletes its file (no partial files remain).
  Future<void> cancelRecording();

  /// Releases the camera (cancelling any recording). Idempotent.
  Future<void> dispose();
}

/// [CameraService] backed by the `camera` plugin.
class PluginCameraService implements CameraService {
  static const ResolutionPreset _preset = ResolutionPreset.medium;

  final AsyncMutex _mutex = AsyncMutex();
  CameraController? _controller;

  @override
  CameraController? get controller => _controller;

  @override
  String get resolutionPresetName => _preset.name;

  CameraController _require() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      throw const AppException(
        AppErrorType.cameraInitFailed,
        details: 'Camera is not initialised.',
      );
    }
    return c;
  }

  @override
  Future<void> initialize() => _mutex.run(() async {
    await _disposeUnlocked();
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException catch (e) {
      throw _mapCameraException(e);
    }
    final rear = cameras
        .where((c) => c.lensDirection == CameraLensDirection.back)
        .firstOrNull;
    if (rear == null) {
      throw const AppException(
        AppErrorType.cameraUnavailable,
        details: 'No rear camera found.',
      );
    }
    final controller = CameraController(
      rear,
      _preset,
      enableAudio: false,
      fps: AppConfig.targetFps,
      videoBitrate: AppConfig.videoBitrate,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      await _safeDispose(controller);
      throw _mapCameraException(e);
    } catch (e) {
      await _safeDispose(controller);
      throw AppException(
        AppErrorType.cameraInitFailed,
        details: e.toString(),
        cause: e,
      );
    }
    try {
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {
      // Orientation lock only affects video metadata; ROI means are unaffected.
    }
    _controller = controller;
  });

  @override
  Future<void> setTorch({required bool on}) => _mutex.run(() async {
    final c = on ? _require() : _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.setFlashMode(on ? FlashMode.torch : FlashMode.off);
    } catch (e) {
      if (on) {
        throw AppException(
          AppErrorType.torchUnavailable,
          details: e.toString(),
          cause: e,
        );
      }
    }
  });

  @override
  Future<CameraLockResult> lockExposureAndFocus() => _mutex.run(() async {
    final c = _require();
    // Meter on the lens centre so light leaking at the edges is ignored
    // (same approach as Sphygma), then let metering settle before locking.
    try {
      await c.setExposurePoint(const Offset(0.5, 0.5));
    } catch (_) {}
    try {
      await c.setFocusPoint(const Offset(0.5, 0.5));
    } catch (_) {}
    await Future<void>.delayed(AppConfig.meteringSettleDelay);
    var exposure = false;
    var focus = false;
    try {
      await c.setExposureMode(ExposureMode.locked);
      exposure = true;
    } catch (_) {}
    try {
      await c.setFocusMode(FocusMode.locked);
      focus = true;
    } catch (_) {}
    return CameraLockResult(exposure: exposure, focus: focus);
  });

  @override
  Future<void> unlockExposureAndFocus() => _mutex.run(() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.setExposureMode(ExposureMode.auto);
    } catch (_) {}
    try {
      await c.setFocusMode(FocusMode.auto);
    } catch (_) {}
    try {
      await c.setExposurePoint(null);
    } catch (_) {}
    try {
      await c.setFocusPoint(null);
    } catch (_) {}
  });

  @override
  Future<void> startFrameStream(void Function(CameraImage image) onFrame) =>
      _mutex.run(() async {
        final c = _require();
        if (c.value.isStreamingImages) return;
        try {
          await c.startImageStream(onFrame);
        } catch (e) {
          throw AppException(
            AppErrorType.cameraInitFailed,
            details: 'Image stream failed: $e',
            cause: e,
          );
        }
      });

  @override
  Future<void> stopFrameStream() => _mutex.run(_stopStreamUnlocked);

  Future<void> _stopStreamUnlocked() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || !c.value.isStreamingImages) {
      return;
    }
    try {
      await c.stopImageStream();
    } catch (_) {}
  }

  @override
  Future<bool> startRecording({void Function(CameraImage image)? onFrame}) =>
      _mutex.run(() async {
        final c = _require();
        if (c.value.isRecordingVideo) {
          throw const AppException(
            AppErrorType.recordingFailed,
            details: 'A recording is already in progress.',
          );
        }
        await _stopStreamUnlocked();

        var streaming = false;
        Object? lastError;
        if (onFrame != null) {
          try {
            await c.startVideoRecording(onAvailable: onFrame);
            streaming = true;
          } catch (e) {
            lastError = e;
          }
        }
        if (!c.value.isRecordingVideo) {
          try {
            await c.startVideoRecording();
          } catch (e) {
            throw AppException(
              AppErrorType.recordingFailed,
              details: (lastError ?? e).toString(),
              cause: e,
            );
          }
        }

        // Binding the video use case can reconfigure the capture session on
        // some devices; re-assert torch and exposure lock (best effort).
        try {
          await c.setFlashMode(FlashMode.torch);
        } catch (_) {}
        if (c.value.exposureMode == ExposureMode.locked) {
          try {
            await c.setExposureMode(ExposureMode.locked);
          } catch (_) {}
        }
        return streaming;
      });

  @override
  Future<String> stopRecording() => _mutex.run(() async {
    final c = _require();
    if (!c.value.isRecordingVideo) {
      throw const AppException(
        AppErrorType.recordingFailed,
        details: 'No recording in progress.',
      );
    }
    try {
      final file = await c.stopVideoRecording();
      return file.path;
    } catch (e) {
      throw AppException(
        AppErrorType.recordingFailed,
        details: e.toString(),
        cause: e,
      );
    }
  });

  @override
  Future<void> cancelRecording() => _mutex.run(_cancelRecordingUnlocked);

  Future<void> _cancelRecordingUnlocked() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || !c.value.isRecordingVideo) {
      return;
    }
    try {
      final file = await c.stopVideoRecording();
      await _deleteQuietly(file.path);
    } catch (_) {}
  }

  @override
  Future<void> dispose() => _mutex.run(_disposeUnlocked);

  Future<void> _disposeUnlocked() async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    if (c.value.isInitialized) {
      if (c.value.isRecordingVideo) {
        try {
          final file = await c.stopVideoRecording();
          await _deleteQuietly(file.path);
        } catch (_) {}
      }
      if (c.value.isStreamingImages) {
        try {
          await c.stopImageStream();
        } catch (_) {}
      }
      try {
        await c.setFlashMode(FlashMode.off);
      } catch (_) {}
    }
    await _safeDispose(c);
  }

  static Future<void> _safeDispose(CameraController c) async {
    try {
      await c.dispose();
    } catch (_) {}
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static AppException _mapCameraException(CameraException e) {
    final code = e.code.toLowerCase();
    if (code.contains('restricted') || code.contains('withoutprompt')) {
      return AppException(
        AppErrorType.cameraPermissionPermanentlyDenied,
        details: e.description,
        cause: e,
      );
    }
    if (code.contains('accessdenied') || code.contains('permission')) {
      return AppException(
        AppErrorType.cameraPermissionDenied,
        details: e.description,
        cause: e,
      );
    }
    return AppException(
      AppErrorType.cameraInitFailed,
      details: '${e.code}: ${e.description ?? ''}',
      cause: e,
    );
  }
}
