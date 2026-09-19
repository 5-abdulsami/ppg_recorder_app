import 'package:get/get.dart';

import '../data/repositories/recording_repository.dart';
import '../data/services/app_info_service.dart';
import '../data/services/camera_service.dart';
import '../data/services/haptics_service.dart';
import '../data/services/native_platform_bridge.dart';
import '../data/services/permission_service.dart';
import '../data/services/ppg_extraction_service.dart';
import '../data/services/share_service.dart';

/// Registers app-wide services behind their interfaces (dependency
/// inversion — controllers depend on abstractions, swappable in tests).
class InitialBinding extends Bindings {
  @override
  void dependencies() {
    final bridge = NativePlatformBridge();
    Get
      ..put<CameraService>(PluginCameraService(), permanent: true)
      ..put<PermissionService>(PluginPermissionService(), permanent: true)
      ..put<HapticsService>(PlatformHapticsService(), permanent: true)
      ..put<ShareService>(PluginShareService(), permanent: true)
      ..put<AppInfoService>(PluginAppInfoService(), permanent: true)
      ..put<PpgExtractionService>(
        PpgExtractionService(decoder: bridge),
        permanent: true,
      )
      ..put<RecordingRepository>(
        RecordingRepository(storage: bridge),
        permanent: true,
      );
  }
}
