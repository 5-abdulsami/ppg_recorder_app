/// Identification entered on the setup screen for one recording.
class RecordingSession {
  /// Creates a session. [patientId] must already be validated.
  const RecordingSession({required this.patientId, required this.notes});

  /// Validated patient identifier (letters, digits, `-`, `_`).
  final String patientId;

  /// Optional free-text notes (may be empty).
  final String notes;
}
