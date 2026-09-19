import 'package:get/get.dart';

import '../modules/recording/recording_binding.dart';
import '../modules/recording/recording_screen.dart';
import '../modules/results/results_binding.dart';
import '../modules/results/results_screen.dart';
import '../modules/setup/setup_binding.dart';
import '../modules/setup/setup_screen.dart';

/// Named routes.
abstract final class AppRoutes {
  /// Patient ID / notes entry.
  static const String setup = '/setup';

  /// Camera capture and signal extraction.
  static const String recording = '/recording';

  /// Waveform, quality summary, save and export.
  static const String results = '/results';
}

/// GetX page table.
abstract final class AppPages {
  /// All pages with their dependency bindings.
  static final List<GetPage<dynamic>> pages = [
    GetPage<dynamic>(
      name: AppRoutes.setup,
      page: () => const SetupScreen(),
      binding: SetupBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.recording,
      page: () => const RecordingScreen(),
      binding: RecordingBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.results,
      page: () => const ResultsScreen(),
      binding: ResultsBinding(),
    ),
  ];
}
