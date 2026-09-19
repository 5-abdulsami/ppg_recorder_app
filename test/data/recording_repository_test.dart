import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:ppg_recorder_app/core/errors/app_exception.dart';
import 'package:ppg_recorder_app/data/models/app_info.dart';
import 'package:ppg_recorder_app/data/models/processed_recording.dart';
import 'package:ppg_recorder_app/data/models/recording_session.dart';
import 'package:ppg_recorder_app/data/repositories/recording_repository.dart';
import 'package:ppg_recorder_app/data/services/native_platform_bridge.dart';
import 'package:ppg_recorder_app/signal/signal_quality_analyzer.dart';

import '../signal/test_signals.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(root, 'docs');

  @override
  Future<String?> getApplicationSupportPath() async => p.join(root, 'support');

  @override
  Future<String?> getExternalStoragePath() async => null;
}

class _FakeStorage implements StorageSpaceProvider {
  _FakeStorage(this.bytes);

  int? bytes;

  @override
  Future<int?> freeBytes(String directoryPath) async => bytes;
}

const _appInfo = AppInfo(
  appName: 'PPG Recorder',
  version: '1.0.0',
  buildNumber: '1',
  platform: 'test',
  osVersion: 'test',
  manufacturer: 'test',
  model: 'test',
);

void main() {
  late Directory root;
  late _FakeStorage storage;
  late RecordingRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ppg_repo_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    storage = _FakeStorage(10 * 1024 * 1024 * 1024);
    repository = RecordingRepository(storage: storage);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<ProcessedRecording> makeRecording() async {
    final cameraFile = File(p.join(root.path, 'camera_output.mp4'));
    await cameraFile.writeAsBytes(List.filled(2048, 7));
    final pending = await repository.adoptPendingVideo(cameraFile.path);
    final samples = syntheticFingerPpg();
    return ProcessedRecording(
      session: const RecordingSession(patientId: 'P001', notes: 'seated'),
      startedAt: DateTime(2026, 9, 19, 10, 30, 5),
      pendingVideoPath: pending,
      samples: samples,
      analysis: const SignalQualityAnalyzer().analyze(samples),
      video: const VideoInfo(
        width: 640,
        height: 480,
        rotationDegrees: 90,
        durationMs: 30000,
        colorConversion: 'test',
        decoderName: 'fake',
      ),
      capture: const CaptureInfo(
        resolutionPreset: 'medium',
        targetFps: 30,
        exposureLocked: true,
        focusLocked: true,
        liveMonitoringAvailable: true,
      ),
    );
  }

  test('adoptPendingVideo moves the camera file into the pending folder', () async {
    final recording = await makeRecording();
    expect(File(recording.pendingVideoPath).existsSync(), isTrue);
    expect(File(p.join(root.path, 'camera_output.mp4')).existsSync(), isFalse);
  });

  test('save writes CSV, JSON and MP4 with the naming convention', () async {
    final recording = await makeRecording();
    final saved = await repository.save(recording, appInfo: _appInfo);

    expect(p.basename(saved.csvPath), 'ppg_P001_20260919_103005.csv');
    expect(p.basename(saved.metadataPath), 'ppg_P001_20260919_103005.json');
    expect(p.basename(saved.videoPath), 'ppg_P001_20260919_103005.mp4');
    expect(File(recording.pendingVideoPath).existsSync(), isFalse);
    expect(File(saved.videoPath).lengthSync(), 2048);

    final csvLines = File(saved.csvPath).readAsLinesSync();
    expect(csvLines.first, startsWith('frame_index,timestamp_ms,'));
    expect(csvLines, hasLength(901));

    final json =
        jsonDecode(File(saved.metadataPath).readAsStringSync())
            as Map<String, dynamic>;
    expect(json['patient_id'], 'P001');
    expect(json['notes'], 'seated');
    expect(json['total_frames'], 900);
    expect(json['target_fps'], 30);
    expect(json['video_duration_ms'], 30000);
    expect((json['app'] as Map)['version'], '1.0.0');
    expect((json['signal_quality'] as Map)['score'], isA<int>());
    expect(json['recording_started_at'], startsWith('2026-09-19T10:30:05'));

    // No temporary files left behind.
    final leftovers = Directory(saved.directoryPath)
        .listSync()
        .where((e) => e.path.endsWith('.part'));
    expect(leftovers, isEmpty);
  });

  test('a second save in the same second gets a unique name', () async {
    final first = await repository.save(
      await makeRecording(),
      appInfo: _appInfo,
    );
    final second = await repository.save(
      await makeRecording(),
      appInfo: _appInfo,
    );
    expect(p.basename(second.csvPath), 'ppg_P001_20260919_103005_2.csv');
    expect(first.csvPath, isNot(second.csvPath));
  });

  test('insufficient storage fails without writing anything', () async {
    final recording = await makeRecording();
    storage.bytes = 1024;
    await expectLater(
      repository.save(recording, appInfo: _appInfo),
      throwsA(
        isA<AppException>().having(
          (e) => e.type,
          'type',
          AppErrorType.insufficientStorage,
        ),
      ),
    );
    final dir = await repository.recordingsDirectory();
    expect(dir.listSync(), isEmpty);
    expect(File(recording.pendingVideoPath).existsSync(), isTrue);
  });

  test('hasSufficientStorage respects the minimum', () async {
    storage.bytes = 10;
    expect(await repository.hasSufficientStorage(), isFalse);
    storage.bytes = null; // unknown → allow
    expect(await repository.hasSufficientStorage(), isTrue);
  });

  test('discard and clearPendingVideos remove unsaved videos', () async {
    final a = await makeRecording();
    await repository.discardPendingVideo(a.pendingVideoPath);
    expect(File(a.pendingVideoPath).existsSync(), isFalse);

    final b = await makeRecording();
    await repository.clearPendingVideos();
    expect(File(b.pendingVideoPath).existsSync(), isFalse);
  });
}
