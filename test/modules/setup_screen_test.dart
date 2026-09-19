import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:ppg_recorder_app/app/app_routes.dart';
import 'package:ppg_recorder_app/core/constants/app_strings.dart';
import 'package:ppg_recorder_app/core/errors/app_exception.dart';
import 'package:ppg_recorder_app/data/models/recording_session.dart';
import 'package:ppg_recorder_app/data/repositories/recording_repository.dart';
import 'package:ppg_recorder_app/data/services/native_platform_bridge.dart';
import 'package:ppg_recorder_app/modules/setup/setup_binding.dart';
import 'package:ppg_recorder_app/modules/setup/setup_screen.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async => '/tmp/ppg_docs';
}

class _FakeRepository extends RecordingRepository {
  _FakeRepository({required this.sufficient})
    : super(storage: _NoStorage());

  bool sufficient;

  @override
  Future<bool> hasSufficientStorage() async => sufficient;
}

class _NoStorage implements StorageSpaceProvider {
  @override
  Future<int?> freeBytes(String directoryPath) async => null;
}

void main() {
  late _FakeRepository repository;
  RecordingSession? openedWith;

  setUp(() {
    PathProviderPlatform.instance = _FakePathProvider();
    repository = _FakeRepository(sufficient: true);
    openedWith = null;
    Get.testMode = true;
  });

  tearDown(Get.reset);

  Future<void> pumpSetup(WidgetTester tester) async {
    Get.put<RecordingRepository>(repository);
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: AppRoutes.setup,
        getPages: [
          GetPage<dynamic>(
            name: AppRoutes.setup,
            page: () => const SetupScreen(),
            binding: SetupBinding(),
          ),
          GetPage<dynamic>(
            name: AppRoutes.recording,
            page: () {
              openedWith = Get.arguments as RecordingSession?;
              return const Scaffold(body: Text('recording-route'));
            },
          ),
        ],
      ),
    );
    await tester.pump();
  }

  Future<void> tapStart(WidgetTester tester) async {
    final button = find.text(AppStrings.startRecording);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('empty patient ID blocks recording with a message', (
    tester,
  ) async {
    await pumpSetup(tester);
    await tapStart(tester);
    expect(find.text('Please enter a patient ID.'), findsOneWidget);
    expect(find.text('recording-route'), findsNothing);
  });

  testWidgets('unsafe characters are rejected', (tester) async {
    await pumpSetup(tester);
    await tester.enterText(find.byType(TextFormField).first, 'P/01');
    await tapStart(tester);
    expect(
      find.text('Only letters, numbers, "-" and "_" are allowed.'),
      findsOneWidget,
    );
    expect(find.text('recording-route'), findsNothing);
  });

  testWidgets('valid input opens recording with the session', (tester) async {
    await pumpSetup(tester);
    await tester.enterText(find.byType(TextFormField).at(0), 'P001');
    await tester.enterText(find.byType(TextFormField).at(1), 'seated');
    await tapStart(tester);
    expect(find.text('recording-route'), findsOneWidget);
    expect(openedWith?.patientId, 'P001');
    expect(openedWith?.notes, 'seated');
  });

  testWidgets('insufficient storage shows a warning instead', (tester) async {
    repository.sufficient = false;
    await pumpSetup(tester);
    await tester.enterText(find.byType(TextFormField).first, 'P001');
    await tapStart(tester);
    expect(
      find.text(AppStrings.errorTitle(AppErrorType.insufficientStorage)),
      findsOneWidget,
    );
    expect(find.text('recording-route'), findsNothing);
  });
}
