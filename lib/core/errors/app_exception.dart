/// Categories of failures the UI knows how to explain and recover from.
enum AppErrorType {
  /// Camera permission refused (can be asked again).
  cameraPermissionDenied,

  /// Camera permission refused permanently / restricted (settings needed).
  cameraPermissionPermanentlyDenied,

  /// No usable rear camera on the device.
  cameraUnavailable,

  /// The camera failed to start.
  cameraInitFailed,

  /// The flash/torch could not be switched on.
  torchUnavailable,

  /// Video recording failed to start or stop.
  recordingFailed,

  /// Not enough free storage.
  insufficientStorage,

  /// The recorded video could not be decoded.
  extractionFailed,

  /// The recorded video is too short or empty.
  videoTooShort,

  /// Writing result files failed.
  saveFailed,
}

/// Typed exception carrying an [AppErrorType] plus technical details for
/// logs / the error screen.
class AppException implements Exception {
  /// Creates an exception.
  const AppException(this.type, {this.details, this.cause});

  /// Failure category.
  final AppErrorType type;

  /// Optional technical details (shown in small print, never required).
  final String? details;

  /// Underlying error, if any.
  final Object? cause;

  @override
  String toString() =>
      'AppException(${type.name}${details == null ? '' : ': $details'})';
}
