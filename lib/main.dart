import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'app/app_routes.dart';
import 'app/app_theme.dart';
import 'app/initial_binding.dart';
import 'core/constants/app_strings.dart';
import 'data/repositories/recording_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  InitialBinding().dependencies();
  // Remove videos left unsaved by a previous session (e.g. app was killed).
  await Get.find<RecordingRepository>().clearPendingVideos();
  runApp(const PpgRecorderApp());
}

/// Root widget.
class PpgRecorderApp extends StatelessWidget {
  /// Creates the app.
  const PpgRecorderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: AppRoutes.setup,
      getPages: AppPages.pages,
      defaultTransition: Transition.cupertino,
    );
  }
}
