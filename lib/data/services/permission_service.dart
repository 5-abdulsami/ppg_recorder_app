import 'package:permission_handler/permission_handler.dart';

/// Outcome of a camera permission check.
enum CameraPermissionStatus {
  /// Access granted.
  granted,

  /// Refused, but the system dialog can be shown again.
  denied,

  /// Refused permanently or restricted — only app settings can fix it.
  permanentlyDenied,
}

/// Camera permission handling.
abstract interface class PermissionService {
  /// Current status without prompting.
  Future<CameraPermissionStatus> checkCamera();

  /// Prompts if needed and returns the resulting status.
  Future<CameraPermissionStatus> requestCamera();

  /// Opens this app's page in system settings. Returns `false` on failure.
  Future<bool> openSettings();
}

/// [PermissionService] backed by `permission_handler`.
class PluginPermissionService implements PermissionService {
  @override
  Future<CameraPermissionStatus> checkCamera() async =>
      _map(await Permission.camera.status);

  @override
  Future<CameraPermissionStatus> requestCamera() async {
    final current = await Permission.camera.status;
    if (current.isGranted || current.isLimited) {
      return CameraPermissionStatus.granted;
    }
    if (current.isPermanentlyDenied || current.isRestricted) {
      return CameraPermissionStatus.permanentlyDenied;
    }
    return _map(await Permission.camera.request());
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  static CameraPermissionStatus _map(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return CameraPermissionStatus.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return CameraPermissionStatus.permanentlyDenied;
    }
    return CameraPermissionStatus.denied;
  }
}
