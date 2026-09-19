import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppg_recorder_app/signal/dsp/butterworth.dart';
import 'package:ppg_recorder_app/signal/dsp/filters.dart';
import 'package:ppg_recorder_app/signal/dsp/spectral.dart';
import 'package:ppg_recorder_app/signal/ppg_preprocessing.dart';

/// Verifies the Dart DSP port against outputs produced by SciPy with the
/// Sphygma backend's exact code (see tool/generate_scipy_reference.py).
void main() {
  final fixture =
      jsonDecode(File('test/fixtures/scipy_reference.json').readAsStringSync())
          as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  List<double> list(Map<String, dynamic> c, String key) =>
      (c[key] as List).map((v) => (v as num).toDouble()).toList();

  void expectClose(
    List<double> actual,
    List<double> expected, {
    required double tolerance,
    required String label,
  }) {
    expect(actual.length, expected.length, reason: '$label length');
    for (var i = 0; i < expected.length; i++) {
      final scale = expected[i].abs() > 1 ? expected[i].abs() : 1.0;
      expect(
        (actual[i] - expected[i]).abs() / scale,
        lessThan(tolerance),
        reason: '$label[$i]: ${actual[i]} vs ${expected[i]}',
      );
    }
  }

  for (final c in cases) {
    final fs = (c['fs'] as num).toDouble();
    final x = list(c, 'x');

    group('fs = $fs Hz', () {
      final coefficients = butterworthBandpass(
        order: 4,
        lowHz: 0.7,
        highHz: 3.0,
        sampleRateHz: fs,
      );

      test('butter matches scipy', () {
        expectClose(coefficients.b, list(c, 'b'), tolerance: 1e-9, label: 'b');
        expectClose(coefficients.a, list(c, 'a'), tolerance: 1e-9, label: 'a');
      });

      test('lfilter_zi matches scipy', () {
        expectClose(
          lfilterZi(coefficients),
          list(c, 'zi'),
          tolerance: 1e-7,
          label: 'zi',
        );
      });

      test('filtfilt matches scipy', () {
        expectClose(
          filtfilt(coefficients, x),
          list(c, 'filtfilt'),
          tolerance: 1e-6,
          label: 'filtfilt',
        );
      });

      test('savgol_filter matches scipy', () {
        expectClose(
          savitzkyGolay(x, windowLength: 45, polyOrder: 1),
          list(c, 'savgol_45_1'),
          tolerance: 1e-9,
          label: 'savgol(45,1)',
        );
        expectClose(
          savitzkyGolay(x, windowLength: 11, polyOrder: 3),
          list(c, 'savgol_11_3'),
          tolerance: 1e-9,
          label: 'savgol(11,3)',
        );
      });

      test('welch matches scipy', () {
        final spectrum = welch(x, sampleRateHz: fs, segmentLength: 240);
        expectClose(
          spectrum.frequencies,
          list(c, 'welch_f'),
          tolerance: 1e-9,
          label: 'welch f',
        );
        expectClose(
          spectrum.power,
          list(c, 'welch_p'),
          tolerance: 1e-6,
          label: 'welch p',
        );
      });

      test('backend preprocess_hr_signal chain matches scipy', () {
        expectClose(
          preprocessHeartRateSignal(x, sampleRateHz: fs),
          list(c, 'preprocess_hr'),
          tolerance: 1e-6,
          label: 'preprocess_hr',
        );
      });
    });
  }
}
