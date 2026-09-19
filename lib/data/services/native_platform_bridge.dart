import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../../core/errors/app_exception.dart';
import '../models/decoded_video_signal.dart';

/// Decodes a video file into per-frame ROI channel means.
abstract interface class VideoSignalDecoder {
  /// Decodes every frame of [videoPath] and averages R/G/B over a centred
  /// [roiSize]×[roiSize] square. [onProgress] receives values in `[0, 1]`.
  ///
  /// Throws [AppException] ([AppErrorType.extractionFailed]) on failure.
  Future<DecodedVideoSignal> decode(
    String videoPath, {
    required int roiSize,
    void Function(double progress)? onProgress,
  });
}

/// Reports free storage space.
abstract interface class StorageSpaceProvider {
  /// Free bytes on the volume containing [directoryPath], or `null` if the
  /// platform cannot tell.
  Future<int?> freeBytes(String directoryPath);
}

/// Method-channel bridge to the native code in `MainActivity.kt` (Android,
/// MediaExtractor + MediaCodec) and `AppDelegate.swift` (iOS, AVAssetReader).
class NativePlatformBridge implements VideoSignalDecoder, StorageSpaceProvider {
  /// Creates the bridge and registers the progress callback handler.
  NativePlatformBridge() {
    _channel.setMethodCallHandler(_handleCall);
  }

  static const MethodChannel _channel = MethodChannel(
    'com.samionyx.ppg_recorder/native',
  );

  void Function(double progress)? _progressListener;

  Future<void> _handleCall(MethodCall call) async {
    if (call.method == 'onDecodeProgress') {
      final value = call.arguments;
      if (value is num) _progressListener?.call(value.toDouble().clamp(0, 1));
    }
  }

  @override
  Future<DecodedVideoSignal> decode(
    String videoPath, {
    required int roiSize,
    void Function(double progress)? onProgress,
  }) async {
    _progressListener = onProgress;
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'decodeVideoSignal',
        {'path': videoPath, 'roiSize': roiSize},
      );
      if (result == null) {
        throw const AppException(
          AppErrorType.extractionFailed,
          details: 'Native decoder returned no data.',
        );
      }
      return _parse(result);
    } on PlatformException catch (e) {
      throw AppException(
        AppErrorType.extractionFailed,
        details: '${e.code}: ${e.message ?? ''}',
        cause: e,
      );
    } on MissingPluginException catch (e) {
      throw AppException(
        AppErrorType.extractionFailed,
        details: 'Native decoder unavailable on this platform.',
        cause: e,
      );
    } finally {
      _progressListener = null;
    }
  }

  @override
  Future<int?> freeBytes(String directoryPath) async {
    try {
      final value = await _channel.invokeMethod<Object?>('getFreeDiskSpace', {
        'path': directoryPath,
      });
      return value is int ? value : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  DecodedVideoSignal _parse(Map<String, Object?> map) {
    List<double> doubles(String key) {
      final value = map[key];
      if (value is Float64List) return List<double>.of(value);
      if (value is List) return [for (final v in value) (v as num).toDouble()];
      throw AppException(
        AppErrorType.extractionFailed,
        details: 'Malformed native result: "$key".',
      );
    }

    List<int> ints(String key) {
      final value = map[key];
      if (value is Int64List) return List<int>.of(value);
      if (value is List) return [for (final v in value) (v as num).toInt()];
      throw AppException(
        AppErrorType.extractionFailed,
        details: 'Malformed native result: "$key".',
      );
    }

    final timestamps = ints('timestampsUs');
    final red = doubles('red');
    final green = doubles('green');
    final blue = doubles('blue');
    if (red.length != timestamps.length ||
        green.length != timestamps.length ||
        blue.length != timestamps.length) {
      throw const AppException(
        AppErrorType.extractionFailed,
        details: 'Native result arrays have mismatched lengths.',
      );
    }
    return DecodedVideoSignal(
      timestampsUs: timestamps,
      red: red,
      green: green,
      blue: blue,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      rotationDegrees: (map['rotationDegrees'] as num?)?.toInt() ?? 0,
      durationMs: ((map['durationUs'] as num?)?.toDouble() ?? 0) / 1000,
      colorConversion: map['colorConversion'] as String? ?? 'unknown',
      decoderName: map['decoderName'] as String? ?? 'unknown',
    );
  }
}
