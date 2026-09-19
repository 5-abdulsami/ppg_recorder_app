import 'package:get/get.dart';

import '../../data/repositories/recording_repository.dart';
import '../../data/services/camera_service.dart';
import '../../data/services/haptics_service.dart';
import '../../data/services/permission_service.dart';
import '../../data/services/ppg_extraction_service.dart';
import 'recording_controller.dart';

/// Dependencies for the recording screen.
class RecordingBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<RecordingController>(
      () => RecordingController(
        camera: Get.find<CameraService>(),
        permissions: Get.find<PermissionService>(),
        extraction: Get.find<PpgExtractionService>(),
        repository: Get.find<RecordingRepository>(),
        haptics: Get.find<HapticsService>(),
      ),
    );
  }
}
