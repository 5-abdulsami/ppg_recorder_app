import 'package:flutter_test/flutter_test.dart';
import 'package:ppg_recorder_app/core/errors/app_exception.dart';
import 'package:ppg_recorder_app/data/models/decoded_video_signal.dart';
import 'package:ppg_recorder_app/data/services/native_platform_bridge.dart';
import 'package:ppg_recorder_app/data/services/ppg_extraction_service.dart';
import 'package:ppg_recorder_app/signal/models/quality_level.dart';

import '../signal/test_signals.dart';

class _FakeDecoder implements VideoSignalDecoder {
  _FakeDecoder(this.signal);

  final DecodedVideoSignal signal;
  final List<double> progress = [];

  @override
  Future<DecodedVideoSignal> decode(
    String videoPath, {
    required int roiSize,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.5);
    onProgress?.call(1);
    progress.addAll([0.5, 1]);
    return signal;
  }
}

DecodedVideoSignal _decoded({
  required List<int> timestampsUs,
  required List<double> red,
  List<double>? green,
  List<double>? blue,
}) => DecodedVideoSignal(
  timestampsUs: timestampsUs,
  red: red,
  green: green ?? List.filled(red.length, 40),
  blue: blue ?? List.filled(red.length, 20),
  width: 640,
  height: 480,
  rotationDegrees: 90,
  durationMs: 30000,
  colorConversion: 'test',
  decoderName: 'fake',
);

void main() {
  test('buildSamples sorts by time, drops duplicates/NaN and rebases time', () {
    final samples = PpgExtractionService.buildSamples(
      _decoded(
        timestampsUs: [1066666, 1000000, 1033333, 1033333, 1100000],
        red: [3, 1, 2, 99, double.nan],
      ),
    );
    expect(samples.map((s) => s.red), [1, 2, 3]);
    expect(samples.map((s) => s.frameIndex), [0, 1, 2]);
    expect(samples.first.timestampMs, 0);
    expect(samples[1].timestampMs, closeTo(33.333, 1e-9));
  });

  test('extract returns samples, analysis and video info', () async {
    final synthetic = syntheticFingerPpg();
    final decoder = _FakeDecoder(
      _decoded(
        timestampsUs: [
          for (final s in synthetic) (s.timestampMs * 1000).round() + 5000,
        ],
        red: [for (final s in synthetic) s.red],
        green: [for (final s in synthetic) s.green],
        blue: [for (final s in synthetic) s.blue],
      ),
    );
    final progress = <double>[];
    final result = await PpgExtractionService(decoder: decoder).extract(
      'video.mp4',
      onProgress: progress.add,
    );
    expect(result.samples, hasLength(900));
    expect(result.samples.first.timestampMs, 0);
    expect(result.analysis.report.level, QualityLevel.good);
    expect(result.video.rotationDegrees, 90);
    expect(progress, [0.5, 1]);
  });

  test('extract rejects videos with too few frames', () async {
    final decoder = _FakeDecoder(
      _decoded(
        timestampsUs: [for (var i = 0; i < 30; i++) i * 33333],
        red: List.filled(30, 180),
      ),
    );
    await expectLater(
      PpgExtractionService(decoder: decoder).extract('video.mp4'),
      throwsA(
        isA<AppException>().having(
          (e) => e.type,
          'type',
          AppErrorType.videoTooShort,
        ),
      ),
    );
  });
}
