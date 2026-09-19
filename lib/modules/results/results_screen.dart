import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/errors/app_exception.dart';
import '../../core/widgets/quality_colors.dart';
import '../../core/widgets/responsive_body.dart';
import '../../data/models/saved_recording.dart';
import '../../signal/signal_quality_analyzer.dart';
import 'results_controller.dart';
import 'widgets/waveform_chart.dart';

/// Shows the extracted waveform and quality summary, and saves / exports or
/// discards the recording.
class ResultsScreen extends GetView<ResultsController> {
  /// Creates the screen.
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!controller.hasRecording) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Obx(() {
      final saved = controller.status.value == SaveStatus.saved;
      final saving = controller.status.value == SaveStatus.saving;
      return PopScope(
        canPop: saved,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !saving) _confirmDiscard(context, retake: false);
        },
        child: Scaffold(
          appBar: AppBar(title: const Text(AppStrings.resultsTitle)),
          body: ResponsiveBody(
            children: [
              const _Header(),
              const SizedBox(height: 16),
              const _QualityCard(),
              const SizedBox(height: 16),
              const _WaveformCard(),
              const SizedBox(height: 16),
              const _SummaryCard(),
              const SizedBox(height: 24),
              if (saved)
                _SavedActions(files: controller.saved.value!)
              else
                _UnsavedActions(
                  saving: saving,
                  onSave: () => _onSave(context),
                  onDiscard: () => _confirmDiscard(context, retake: true),
                ),
            ],
          ),
        ),
      );
    });
  }

  Future<void> _onSave(BuildContext context) async {
    if (controller.needsQualityWarning) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          iconColor: qualityColor(controller.report.level),
          title: const Text(AppStrings.lowQualityTitle),
          content: Text(AppStrings.lowQualityMessage(controller.report.score)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(AppStrings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              child: const Text(AppStrings.saveAnyway),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    try {
      final files = await controller.save();
      if (context.mounted) await _showSavedDialog(context, files);
    } on AppException catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  Future<void> _showSavedDialog(
    BuildContext context,
    SavedRecording files,
  ) async {
    final share = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: AppColors.qualityGood),
        title: const Text(AppStrings.savedTitle),
        content: SingleChildScrollView(child: _SavedPaths(files: files)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.close),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.ios_share),
            label: const Text(AppStrings.share),
          ),
        ],
      ),
    );
    if (share == true && context.mounted) await _share(context, null);
  }

  Future<void> _confirmDiscard(
    BuildContext context, {
    required bool retake,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.discardTitle),
        content: const Text(AppStrings.discardMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.keep),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.qualityPoor),
            child: const Text(AppStrings.discard),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (retake) {
      await controller.discardAndRetake();
    } else {
      await controller.discardAndExit();
    }
  }
}

Future<void> _share(BuildContext context, Rect? origin) async {
  final controller = Get.find<ResultsController>();
  try {
    await controller.shareSaved(origin: origin ?? _screenCentre(context));
  } on AppException catch (e) {
    if (context.mounted) _showError(context, e);
  }
}

Rect _screenCentre(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2),
    width: 1,
    height: 1,
  );
}

void _showError(BuildContext context, AppException e) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          '${AppStrings.errorTitle(e.type)}. ${AppStrings.errorMessage(e.type)}',
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
}

class _Header extends GetView<ResultsController> {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final r = controller.recording;
    final date = DateFormat.yMMMd().add_Hms().format(r.startedAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(r.session.patientId, style: textTheme.headlineSmall),
        const SizedBox(height: 2),
        Text(
          date,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        if (r.session.notes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(r.session.notes, style: textTheme.bodyMedium),
        ],
      ],
    );
  }
}

class _QualityCard extends GetView<ResultsController> {
  const _QualityCard();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final report = controller.report;
    final color = qualityColor(report.level);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox.square(
                  dimension: 72,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: report.score / 100,
                          strokeWidth: 7,
                          color: color,
                          backgroundColor: color.withValues(alpha: 0.15),
                        ),
                      ),
                      Text(
                        '${report.score}',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppStrings.signalQuality, style: textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        AppStrings.qualityLevelLabel(report.level),
                        style: textTheme.titleLarge?.copyWith(color: color),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (report.issues.isEmpty)
              _IssueRow(
                icon: Icons.check_circle_outline,
                color: AppColors.qualityGood,
                text: AppStrings.noIssues,
              )
            else
              for (final issue in report.issues)
                _IssueRow(
                  icon: Icons.warning_amber_rounded,
                  color: color,
                  text: AppStrings.qualityIssueText(issue),
                ),
            if (!controller.recording.capture.liveMonitoringAvailable)
              const _IssueRow(
                icon: Icons.info_outline,
                color: AppColors.qualityUnknown,
                text: AppStrings.liveCheckUnavailableNote,
              ),
          ],
        ),
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _WaveformCard extends GetView<ResultsController> {
  const _WaveformCard();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Obx(() {
          final channel = controller.channel.value;
          final filtered = controller.showFiltered.value;
          final series = controller.currentSeries;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(AppStrings.waveformTitle, style: textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  SegmentedButton<PpgChannel>(
                    segments: const [
                      ButtonSegment(
                        value: PpgChannel.red,
                        label: Text(AppStrings.channelRed),
                      ),
                      ButtonSegment(
                        value: PpgChannel.green,
                        label: Text(AppStrings.channelGreen),
                      ),
                    ],
                    selected: {channel},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => controller.channel.value = s.first,
                  ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text(AppStrings.viewFiltered),
                      ),
                      ButtonSegment(value: false, label: Text(AppStrings.viewRaw)),
                    ],
                    selected: {filtered},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        controller.showFiltered.value = s.first,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final height = (constraints.maxWidth * 0.55).clamp(
                    180.0,
                    300.0,
                  );
                  if (series == null) {
                    return SizedBox(
                      height: height,
                      child: const Center(
                        child: Text(
                          AppStrings.waveformUnavailable,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return WaveformChart(
                    times: series.timesSeconds,
                    values: series.values,
                    color: channel == PpgChannel.red
                        ? AppColors.channelRed
                        : AppColors.channelGreen,
                    height: height,
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                filtered ? AppStrings.filteredCaption : AppStrings.rawCaption,
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _SummaryCard extends GetView<ResultsController> {
  const _SummaryCard();

  @override
  Widget build(BuildContext context) {
    final report = controller.report;
    final sampling = report.sampling;
    final hr = report.estimatedHeartRateBpm;
    final metrics = <(String, String)>[
      (
        AppStrings.metricDuration,
        AppStrings.formatSeconds(sampling.durationMs / 1000),
      ),
      (AppStrings.metricFrames, '${sampling.frameCount}'),
      (AppStrings.metricFps, AppStrings.formatFps(sampling.measuredFps)),
      (
        AppStrings.metricHeartRate,
        hr == null ? AppStrings.notAvailable : AppStrings.formatBpm(hr),
      ),
      (
        AppStrings.metricCoverage,
        AppStrings.formatPercent(report.fingerCoverage),
      ),
      (AppStrings.metricDropped, '${sampling.droppedFrames}'),
    ];
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(AppStrings.summaryTitle, style: textTheme.titleMedium),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 480 ? 3 : 2;
                const spacing = 12.0;
                final tileWidth =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final (label, value) in metrics)
                      SizedBox(
                        width: tileWidth,
                        child: _MetricTile(label: label, value: value),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _UnsavedActions extends StatelessWidget {
  const _UnsavedActions({
    required this.saving,
    required this.onSave,
    required this.onDiscard,
  });

  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: saving ? null : onSave,
          icon: saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_alt),
          label: Text(saving ? AppStrings.saving : AppStrings.saveAndExport),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: saving ? null : onDiscard,
          icon: const Icon(Icons.replay),
          label: const Text(AppStrings.discardAndRetake),
        ),
      ],
    );
  }
}

class _SavedActions extends GetView<ResultsController> {
  const _SavedActions({required this.files});

  final SavedRecording files;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.qualityGood),
                    const SizedBox(width: 8),
                    Text(
                      AppStrings.savedTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _SavedPaths(files: files),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Builder(
          builder: (buttonContext) => Obx(
            () => FilledButton.icon(
              onPressed: controller.isSharing.value
                  ? null
                  : () {
                      final box =
                          buttonContext.findRenderObject() as RenderBox?;
                      final origin = box == null || !box.hasSize
                          ? null
                          : box.localToGlobal(Offset.zero) & box.size;
                      _share(buttonContext, origin);
                    },
              icon: const Icon(Icons.ios_share),
              label: const Text(AppStrings.shareFiles),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: controller.recordAgainSamePatient,
          icon: const Icon(Icons.replay),
          label: const Text(AppStrings.recordAgainSamePatient),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: controller.newPatient,
          icon: const Icon(Icons.person_add_alt),
          label: const Text(AppStrings.newPatient),
        ),
      ],
    );
  }
}

class _SavedPaths extends StatelessWidget {
  const _SavedPaths({required this.files});

  final SavedRecording files;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    String name(String path) => path.split(RegExp(r'[\\/]')).last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(AppStrings.savedMessage),
        const SizedBox(height: 4),
        SelectableText(
          files.directoryPath,
          style: small?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        for (final path in files.allPaths)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.insert_drive_file_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(child: SelectableText(name(path), style: small)),
              ],
            ),
          ),
      ],
    );
  }
}
