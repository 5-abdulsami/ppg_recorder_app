import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../models/app_info.dart';
import '../models/processed_recording.dart';
import '../models/saved_recording.dart';
import '../serializers/file_naming.dart';
import '../serializers/ppg_csv_encoder.dart';
import '../serializers/recording_metadata_builder.dart';
import '../services/native_platform_bridge.dart';

/// Owns every file the app writes: pending (unsaved) videos and saved
/// recordings (CSV + metadata JSON + MP4).
///
/// Saves are all-or-nothing: files are written under temporary names and
/// renamed into place, and anything already written is removed if a later
/// step fails, so a partial or corrupt recording is never left behind.
class RecordingRepository {
  /// Creates the repository.
  RecordingRepository({required StorageSpaceProvider storage})
    : _storage = storage;

  final StorageSpaceProvider _storage;
  static const String _tempSuffix = '.part';

  /// Folder where saved recordings are written.
  ///
  /// Android: app-specific external storage
  /// (`Android/data/<package>/files/PPG_Recordings`, reachable over USB, no
  /// permission needed), falling back to the documents folder. iOS: the
  /// app's Documents folder (visible in the Files app).
  Future<Directory> recordingsDirectory() async {
    Directory? base;
    if (Platform.isAndroid) {
      try {
        base = await getExternalStorageDirectory();
      } catch (_) {
        base = null;
      }
    }
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, AppConfig.recordingsFolderName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _pendingDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, AppConfig.pendingFolderName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Whether enough free space exists to record and save. Returns `true`
  /// when the platform cannot report free space.
  Future<bool> hasSufficientStorage() async {
    try {
      final dir = await recordingsDirectory();
      final free = await _storage.freeBytes(dir.path);
      return free == null || free >= AppConfig.minFreeStorageBytes;
    } catch (_) {
      return true;
    }
  }

  /// Moves a freshly recorded camera file into the private pending folder
  /// and returns its new path.
  Future<String> adoptPendingVideo(String cameraFilePath) async {
    final source = File(cameraFilePath);
    if (!await source.exists()) {
      throw AppException(
        AppErrorType.recordingFailed,
        details: 'Recorded file not found: $cameraFilePath',
      );
    }
    final dir = await _pendingDirectory();
    final target = p.join(
      dir.path,
      'pending_${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
    try {
      return (await _moveFile(source, target)).path;
    } catch (e) {
      await _deleteQuietly(source.path);
      throw AppException(
        AppErrorType.recordingFailed,
        details: 'Could not store recording: $e',
        cause: e,
      );
    }
  }

  /// Deletes an unsaved video. Never throws.
  Future<void> discardPendingVideo(String path) => _deleteQuietly(path);

  /// Removes pending videos left over from a previous session (e.g. the app
  /// was killed before saving). Never throws.
  Future<void> clearPendingVideos() async {
    try {
      final dir = await _pendingDirectory();
      await for (final entity in dir.list()) {
        await _deleteQuietly(entity.path);
      }
    } catch (_) {}
  }

  /// Saves [recording] as `ppg_{id}_{yyyyMMdd_HHmmss}.csv/.json/.mp4`.
  ///
  /// On success the pending video has been moved into the recordings
  /// folder. On failure nothing new remains in the recordings folder and the
  /// pending video is kept so saving can be retried.
  ///
  /// Throws [AppException] ([AppErrorType.saveFailed] or
  /// [AppErrorType.insufficientStorage]).
  Future<SavedRecording> save(
    ProcessedRecording recording, {
    required AppInfo appInfo,
  }) async {
    final Directory dir;
    try {
      dir = await recordingsDirectory();
    } catch (e) {
      throw AppException(
        AppErrorType.saveFailed,
        details: 'Storage folder unavailable: $e',
        cause: e,
      );
    }
    final pendingVideo = File(recording.pendingVideoPath);
    if (!await pendingVideo.exists()) {
      throw const AppException(
        AppErrorType.saveFailed,
        details: 'The recorded video is no longer available.',
      );
    }
    final free = await _storage.freeBytes(dir.path);
    final needed = await pendingVideo.length() + 5 * 1024 * 1024;
    if (free != null && free < needed) {
      throw const AppException(AppErrorType.insufficientStorage);
    }

    final baseName = await _uniqueBaseName(
      dir,
      FileNaming.baseName(recording.session.patientId, recording.startedAt),
    );
    final csvPath = p.join(dir.path, '$baseName.csv');
    final jsonPath = p.join(dir.path, '$baseName.json');
    final videoPath = p.join(dir.path, '$baseName.mp4');
    final written = <String>[];

    try {
      await _writeAtomically(
        csvPath,
        PpgCsvEncoder.encode(recording.samples),
      );
      written.add(csvPath);

      final metadata = RecordingMetadataBuilder.build(
        recording: recording,
        appInfo: appInfo,
        csvFileName: p.basename(csvPath),
        videoFileName: p.basename(videoPath),
      );
      await _writeAtomically(
        jsonPath,
        const JsonEncoder.withIndent('  ').convert(metadata),
      );
      written.add(jsonPath);

      // Last step: after this succeeds the recording is complete.
      await _moveFile(pendingVideo, videoPath);
      written.add(videoPath);
    } catch (e) {
      for (final path in written.where((path) => path != videoPath)) {
        await _deleteQuietly(path);
      }
      for (final path in [csvPath, jsonPath, videoPath]) {
        await _deleteQuietly('$path$_tempSuffix');
      }
      if (e is AppException) rethrow;
      throw AppException(AppErrorType.saveFailed, details: '$e', cause: e);
    }

    return SavedRecording(
      directoryPath: dir.path,
      csvPath: csvPath,
      metadataPath: jsonPath,
      videoPath: videoPath,
    );
  }

  Future<String> _uniqueBaseName(Directory dir, String base) async {
    var candidate = base;
    var suffix = 2;
    while (await _anyExists(dir, candidate)) {
      candidate = '${base}_$suffix';
      suffix++;
    }
    return candidate;
  }

  Future<bool> _anyExists(Directory dir, String base) async {
    for (final ext in const ['.csv', '.json', '.mp4']) {
      if (await File(p.join(dir.path, '$base$ext')).exists()) return true;
    }
    return false;
  }

  Future<void> _writeAtomically(String path, String contents) async {
    final temp = File('$path$_tempSuffix');
    await temp.writeAsString(contents, flush: true);
    await temp.rename(path);
  }

  /// Moves [source] to [targetPath]; falls back to copy + delete across
  /// file systems, copying under a temporary name first.
  Future<File> _moveFile(File source, String targetPath) async {
    try {
      return await source.rename(targetPath);
    } on FileSystemException {
      final temp = '$targetPath$_tempSuffix';
      try {
        await source.copy(temp);
        final moved = await File(temp).rename(targetPath);
        await _deleteQuietly(source.path);
        return moved;
      } catch (_) {
        await _deleteQuietly(temp);
        rethrow;
      }
    }
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
