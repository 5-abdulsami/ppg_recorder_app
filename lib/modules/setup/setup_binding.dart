import 'package:get/get.dart';

import '../../data/repositories/recording_repository.dart';
import 'setup_controller.dart';

/// Dependencies for the setup screen.
class SetupBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SetupController>(
      () => SetupController(repository: Get.find<RecordingRepository>()),
    );
  }
}
