import 'package:get/get.dart';

import '../../data/repositories/recording_repository.dart';
import '../../data/services/app_info_service.dart';
import '../../data/services/share_service.dart';
import 'results_controller.dart';

/// Dependencies for the results screen.
class ResultsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ResultsController>(
      () => ResultsController(
        repository: Get.find<RecordingRepository>(),
        appInfo: Get.find<AppInfoService>(),
        share: Get.find<ShareService>(),
      ),
    );
  }
}
