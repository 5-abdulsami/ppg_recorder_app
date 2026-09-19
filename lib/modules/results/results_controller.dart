import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../app/app_routes.dart';
import '../../core/constants/app_strings.dart';
import '../../data/models/processed_recording.dart';
import '../../data/models/saved_recording.dart';
import '../../data/repositories/recording_repository.dart';
import '../../data/services/app_info_service.dart';
import '../../data/services/share_service.dart';
import '../../signal/models/quality_level.dart';
import '../../signal/signal_quality_analyzer.dart';

/// Save state of the results screen.
enum SaveStatus {
  /// Not saved yet.
  unsaved,

  /// Writing files.
  saving,

  /// Files written.
  saved,
}

/// Waveform series prepared for plotting.
class WaveformSeries {
  /// Creates a series with equal-length [timesSeconds] and [values].
  const WaveformSeries({required this.timesSeconds, required this.values});

  /// Sample times (s).
  final List<double> timesSeconds;

  /// Sample values.
  final List<double> values;
}

/// State and actions of the results screen: waveform selection, saving,
/// sharing and navigation. Discards the pending video if the screen is left
/// without saving.
class ResultsController extends GetxController {
  /// Creates the controller.
  ResultsController({
    required RecordingRepository repository,
    required AppInfoService appInfo,
    required ShareService share,
  }) : _repository = repository,
       _appInfo = appInfo,
       _share = share;

  final RecordingRepository _repository;
  final AppInfoService _appInfo;
  final ShareService _share;

  ProcessedRecording? _recording;
  bool _pendingReleased = false;

  /// The recording being reviewed (valid when [hasRecording]).
  ProcessedRecording get recording => _recording!;

  /// Whether the screen received a recording.
  bool get hasRecording => _recording != null;

  /// Channel shown in the chart.
  final Rx<PpgChannel> channel = PpgChannel.green.obs;

  /// Filtered (true) or raw (false) view.
  final RxBool showFiltered = true.obs;

  /// Save progress.
  final Rx<SaveStatus> status = SaveStatus.unsaved.obs;

  /// Written files, once saved.
  final Rxn<SavedRecording> saved = Rxn<SavedRecording>();

  /// True while the share sheet is being opened.
  final RxBool isSharing = false.obs;

  /// Quality report shortcut.
  SignalQualityReport get report => recording.analysis.report;

  /// Whether to warn before saving.
  bool get needsQualityWarning => report.level != QualityLevel.good;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args is! ProcessedRecording) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => Get.offAllNamed<void>(AppRoutes.setup),
      );
      return;
    }
    _recording = args;
    channel.value = args.analysis.report.preferredChannel;
    showFiltered.value =
        args.analysis.filteredRed != null ||
        args.analysis.filteredGreen != null;
  }

  @override
  void onClose() {
    // Leaving without saving must not leave the video behind.
    final r = _recording;
    if (r != null && status.value != SaveStatus.saved && !_pendingReleased) {
      unawaited(_repository.discardPendingVideo(r.pendingVideoPath));
    }
    super.onClose();
  }

  final Map<(PpgChannel, bool), WaveformSeries?> _seriesCache = {};
  List<double>? _times;

  /// Series for the current channel/view, or `null` if the filtered signal
  /// is unavailable.
  WaveformSeries? get currentSeries {
    final key = (channel.value, showFiltered.value);
    return _seriesCache.putIfAbsent(key, () {
      final r = recording;
      final times = _times ??= [
        for (final s in r.samples) s.timestampMs / 1000,
      ];
      final List<double>? values;
      if (key.$2) {
        values = key.$1 == PpgChannel.red
            ? r.analysis.filteredRed
            : r.analysis.filteredGreen;
      } else {
        values = key.$1 == PpgChannel.red
            ? [for (final s in r.samples) s.red]
            : [for (final s in r.samples) s.green];
      }
      if (values == null || values.length != times.length) return null;
      return WaveformSeries(timesSeconds: times, values: values);
    });
  }

  /// Writes CSV + JSON + video. Throws `AppException` on failure (the
  /// recording stays available for another attempt).
  Future<SavedRecording> save() async {
    final existing = saved.value;
    if (existing != null) return existing;
    if (status.value == SaveStatus.saving) {
      throw StateError('Save already in progress.');
    }
    status.value = SaveStatus.saving;
    try {
      final info = await _appInfo.load();
      final result = await _repository.save(recording, appInfo: info);
      saved.value = result;
      status.value = SaveStatus.saved;
      return result;
    } catch (_) {
      status.value = SaveStatus.unsaved;
      rethrow;
    }
  }

  /// Opens the share sheet for the saved files. Throws `AppException`.
  Future<void> shareSaved({Rect? origin}) async {
    final files = saved.value;
    if (files == null || isSharing.value) return;
    isSharing.value = true;
    try {
      await _share.shareFiles(
        files.allPaths,
        subject: AppStrings.shareSubject,
        text: AppStrings.shareText(recording.session.patientId),
        origin: origin,
      );
    } finally {
      isSharing.value = false;
    }
  }

  /// Deletes the unsaved video and records again for the same patient.
  Future<void> discardAndRetake() async {
    if (status.value == SaveStatus.saving) return;
    await _releasePending();
    Get.offNamed<void>(AppRoutes.recording, arguments: recording.session);
  }

  /// Deletes the unsaved video and returns to the setup screen.
  Future<void> discardAndExit() async {
    if (status.value == SaveStatus.saving) return;
    await _releasePending();
    Get.back<void>();
  }

  /// After saving: record again with the same patient ID and notes.
  void recordAgainSamePatient() =>
      Get.offNamed<void>(AppRoutes.recording, arguments: recording.session);

  /// After saving: start over with a new patient.
  void newPatient() => Get.offAllNamed<void>(AppRoutes.setup);

  Future<void> _releasePending() async {
    if (status.value == SaveStatus.saved || _pendingReleased) return;
    _pendingReleased = true;
    await _repository.discardPendingVideo(recording.pendingVideoPath);
  }
}
