import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/errors/app_exception.dart';
import '../../core/widgets/quality_colors.dart';
import 'recording_controller.dart';
import 'widgets/camera_preview_circle.dart';
import 'widgets/live_quality_indicator.dart';
import 'widgets/recording_status_view.dart';

/// Capture screen: live preview, instructions, countdown, live quality
/// indicator, then a processing view while the PPG is extracted.
class RecordingScreen extends GetView<RecordingController> {
  /// Creates the screen.
  const RecordingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.cancelAndExit();
      },
      child: Scaffold(
        backgroundColor: AppColors.recordingBackground,
        body: SafeArea(
          child: Obx(() {
            switch (controller.phase.value) {
              case RecordingPhase.permissionDenied:
                return RecordingStatusView(
                  icon: Icons.no_photography_outlined,
                  title: AppStrings.errorTitle(
                    AppErrorType.cameraPermissionDenied,
                  ),
                  message: AppStrings.errorMessage(
                    AppErrorType.cameraPermissionDenied,
                  ),
                  primaryLabel: AppStrings.grantPermission,
                  onPrimary: controller.retry,
                  onSecondary: controller.cancelAndExit,
                );
              case RecordingPhase.permissionPermanentlyDenied:
                return RecordingStatusView(
                  icon: Icons.no_photography_outlined,
                  title: AppStrings.errorTitle(
                    AppErrorType.cameraPermissionPermanentlyDenied,
                  ),
                  message: AppStrings.errorMessage(
                    AppErrorType.cameraPermissionPermanentlyDenied,
                  ),
                  primaryLabel: AppStrings.openSettings,
                  onPrimary: controller.openSettings,
                  onSecondary: controller.cancelAndExit,
                );
              case RecordingPhase.error:
                final error =
                    controller.error.value ??
                    const AppException(AppErrorType.cameraInitFailed);
                final isCaptureProblem =
                    error.type == AppErrorType.extractionFailed ||
                    error.type == AppErrorType.videoTooShort ||
                    error.type == AppErrorType.recordingFailed;
                return RecordingStatusView(
                  icon: Icons.error_outline,
                  title: AppStrings.errorTitle(error.type),
                  message: AppStrings.errorMessage(error.type),
                  details: error.details,
                  primaryLabel: isCaptureProblem
                      ? AppStrings.retake
                      : AppStrings.retry,
                  onPrimary: controller.retry,
                  onSecondary: controller.cancelAndExit,
                );
              case RecordingPhase.finishing:
              case RecordingPhase.processing:
                return const _ProcessingView();
              case RecordingPhase.initializing:
              case RecordingPhase.waitingForFinger:
              case RecordingPhase.starting:
              case RecordingPhase.recording:
                return const _CaptureView();
            }
          }),
        ),
      ),
    );
  }
}

class _CaptureView extends GetView<RecordingController> {
  const _CaptureView();

  String _statusText(RecordingPhase phase, bool fingerPresent) =>
      switch (phase) {
        RecordingPhase.initializing => AppStrings.preparing,
        RecordingPhase.starting => AppStrings.startingRecording,
        RecordingPhase.recording => AppStrings.recordingInProgress,
        _ => fingerPresent ? AppStrings.holdStill : AppStrings.placeFinger,
      };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final diameter = math.min(
          360.0,
          math.min(constraints.maxWidth * 0.62, constraints.maxHeight * 0.36),
        );
        return Column(
          children: [
            _TopBar(onCancel: controller.cancelAndExit),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(0, constraints.maxHeight - 72),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Obx(() {
                        final notice = controller.notice.value;
                        return notice == null
                            ? const SizedBox(height: 8)
                            : _NoticeBanner(notice: notice);
                      }),
                      const SizedBox(height: 16),
                      Obx(() {
                        final recording =
                            controller.phase.value == RecordingPhase.recording;
                        return CameraPreviewCircle(
                          controller: controller.cameraReady.value
                              ? controller.cameraController
                              : null,
                          diameter: diameter,
                          progress: controller.recordingProgress.value,
                          ringColor: recording
                              ? qualityColor(
                                  controller.liveAvailable.value
                                      ? controller.liveLevel.value
                                      : null,
                                )
                              : Colors.white24,
                        );
                      }),
                      const SizedBox(height: 20),
                      Obx(() {
                        final recording =
                            controller.phase.value == RecordingPhase.recording;
                        final seconds = controller.remainingSeconds.value
                            .ceil();
                        return Text(
                          '$seconds${AppStrings.secondsLeftSuffix}',
                          style: textTheme.displayLarge?.copyWith(
                            color: recording ? Colors.white : Colors.white38,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
                      Obx(
                        () => LiveQualityIndicator(
                          level: controller.cameraReady.value
                              ? controller.liveLevel.value
                              : null,
                          issue: controller.liveIssue.value,
                          available: controller.liveAvailable.value,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Obx(
                        () => Text(
                          _statusText(
                            controller.phase.value,
                            controller.fingerPresent.value,
                          ),
                          textAlign: TextAlign.center,
                          style: textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TopBar extends GetView<RecordingController> {
  const _TopBar({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final patientId = controller.session?.patientId ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close, color: Colors.white),
            label: const Text(
              AppStrings.cancel,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          const Spacer(),
          if (patientId.isNotEmpty)
            Flexible(
              child: Chip(
                avatar: const Icon(Icons.badge_outlined, size: 18),
                label: Text(patientId, overflow: TextOverflow.ellipsis),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.notice});

  final RecordingNotice notice;

  @override
  Widget build(BuildContext context) {
    final (icon, text, color) = switch (notice) {
      RecordingNotice.interrupted => (
        Icons.pause_circle_outline,
        AppStrings.noticeInterrupted,
        AppColors.qualityFair,
      ),
      RecordingNotice.fingerRemoved => (
        Icons.touch_app_outlined,
        AppStrings.noticeFingerRemoved,
        AppColors.qualityFair,
      ),
      RecordingNotice.liveUnavailable => (
        Icons.info_outline,
        AppStrings.noticeLiveUnavailable,
        AppColors.qualityUnknown,
      ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _ProcessingView extends GetView<RecordingController> {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Obx(() {
            final finishing =
                controller.phase.value == RecordingPhase.finishing;
            final progress = controller.extractionProgress.value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: SizedBox.square(
                    dimension: 56,
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  finishing
                      ? AppStrings.finishing
                      : AppStrings.processingTitle,
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.processingSubtitle,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: finishing ? null : progress,
                    minHeight: 8,
                    color: Colors.white,
                    backgroundColor: Colors.white12,
                  ),
                ),
                const SizedBox(height: 8),
                if (!finishing)
                  Text(
                    '${(progress * 100).round()} %',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(color: Colors.white54),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
