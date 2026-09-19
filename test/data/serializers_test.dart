import 'package:flutter_test/flutter_test.dart';
import 'package:ppg_recorder_app/core/utils/patient_id_validator.dart';
import 'package:ppg_recorder_app/data/serializers/file_naming.dart';
import 'package:ppg_recorder_app/data/serializers/ppg_csv_encoder.dart';
import 'package:ppg_recorder_app/signal/models/ppg_sample.dart';

void main() {
  test('CSV has the required header and raw values', () {
    final csv = PpgCsvEncoder.encode(const [
      PpgSample(
        frameIndex: 0,
        timestampMs: 0,
        red: 181.23456,
        green: 40.5,
        blue: 20,
      ),
      PpgSample(
        frameIndex: 1,
        timestampMs: 33.3333,
        red: 182,
        green: 41,
        blue: 21,
      ),
    ]);
    final lines = csv.split('\n');
    expect(
      lines[0],
      'frame_index,timestamp_ms,red_channel_value,green_channel_value,'
      'blue_channel_value',
    );
    expect(lines[1], '0,0.000,181.2346,40.5000,20.0000');
    expect(lines[2], '1,33.333,182.0000,41.0000,21.0000');
    expect(lines.last, isEmpty); // trailing newline
  });

  test('file name follows ppg_{patientID}_{yyyyMMdd_HHmmss}', () {
    expect(
      FileNaming.baseName('P-001_a', DateTime(2026, 9, 19, 8, 5, 3)),
      'ppg_P-001_a_20260919_080503',
    );
  });

  group('PatientIdValidator', () {
    test('accepts safe IDs', () {
      expect(PatientIdValidator.validate('P001'), isNull);
      expect(PatientIdValidator.validate('  sub-12_B  '), isNull);
    });

    test('rejects empty, unsafe and overlong IDs', () {
      expect(PatientIdValidator.validate(''), PatientIdError.empty);
      expect(PatientIdValidator.validate('   '), PatientIdError.empty);
      expect(PatientIdValidator.validate(null), PatientIdError.empty);
      expect(
        PatientIdValidator.validate('a/b'),
        PatientIdError.invalidCharacters,
      );
      expect(
        PatientIdValidator.validate('john doe'),
        PatientIdError.invalidCharacters,
      );
      expect(PatientIdValidator.validate('x' * 41), PatientIdError.tooLong);
    });
  });
}
