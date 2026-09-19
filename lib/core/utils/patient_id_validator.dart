import '../constants/app_config.dart';

/// Result of validating a patient ID.
enum PatientIdError {
  /// Field is empty.
  empty,

  /// Longer than [AppConfig.patientIdMaxLength].
  tooLong,

  /// Contains characters that are unsafe in file names.
  invalidCharacters,
}

/// Validates patient IDs so they are safe to embed in file names.
///
/// Allowed: letters, digits, `-` and `_`.
abstract final class PatientIdValidator {
  static final RegExp _allowed = RegExp(r'^[A-Za-z0-9_-]+$');

  /// Returns `null` if [value] (after trimming) is valid, else the error.
  static PatientIdError? validate(String? value) {
    final id = value?.trim() ?? '';
    if (id.isEmpty) return PatientIdError.empty;
    if (id.length > AppConfig.patientIdMaxLength) return PatientIdError.tooLong;
    if (!_allowed.hasMatch(id)) return PatientIdError.invalidCharacters;
    return null;
  }
}
