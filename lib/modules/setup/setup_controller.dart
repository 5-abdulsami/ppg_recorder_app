import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../app/app_routes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/patient_id_validator.dart';
import '../../data/models/recording_session.dart';
import '../../data/repositories/recording_repository.dart';

/// Outcome of tapping "Start Recording".
enum StartRecordingOutcome {
  /// Navigated to the recording screen.
  started,

  /// Form validation failed.
  invalidInput,

  /// Not enough free storage.
  insufficientStorage,
}

/// State and actions of the setup (patient ID / notes) screen.
class SetupController extends GetxController {
  /// Creates the controller.
  SetupController({required RecordingRepository repository})
    : _repository = repository;

  final RecordingRepository _repository;

  /// Form key for validation.
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  /// Patient ID input.
  final TextEditingController patientIdController = TextEditingController();

  /// Notes input.
  final TextEditingController notesController = TextEditingController();

  /// True while the storage pre-check runs.
  final RxBool isChecking = false.obs;

  /// Folder where recordings are saved (shown to the user).
  final RxnString saveLocation = RxnString();

  @override
  void onInit() {
    super.onInit();
    _loadSaveLocation();
  }

  Future<void> _loadSaveLocation() async {
    try {
      saveLocation.value = (await _repository.recordingsDirectory()).path;
    } catch (_) {
      saveLocation.value = null;
    }
  }

  /// Form validator for the patient ID field.
  String? validatePatientId(String? value) {
    final error = PatientIdValidator.validate(value);
    return error == null ? null : AppStrings.patientIdError(error);
  }

  /// Validates input, checks free storage and opens the recording screen.
  Future<StartRecordingOutcome> startRecording() async {
    if (isChecking.value) return StartRecordingOutcome.invalidInput;
    if (!(formKey.currentState?.validate() ?? false)) {
      return StartRecordingOutcome.invalidInput;
    }
    isChecking.value = true;
    try {
      if (!await _repository.hasSufficientStorage()) {
        return StartRecordingOutcome.insufficientStorage;
      }
    } finally {
      isChecking.value = false;
    }
    final session = RecordingSession(
      patientId: patientIdController.text.trim(),
      notes: notesController.text.trim(),
    );
    await Get.toNamed<void>(AppRoutes.recording, arguments: session);
    return StartRecordingOutcome.started;
  }

  @override
  void onClose() {
    patientIdController.dispose();
    notesController.dispose();
    super.onClose();
  }
}
