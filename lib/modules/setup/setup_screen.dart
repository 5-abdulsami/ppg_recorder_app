import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_config.dart';
import '../../core/constants/app_strings.dart';
import '../../core/errors/app_exception.dart';
import '../../core/widgets/responsive_body.dart';
import 'setup_controller.dart';

/// Home screen: patient ID, optional notes, instructions, start button.
class SetupScreen extends GetView<SetupController> {
  /// Creates the screen.
  const SetupScreen({super.key});

  Future<void> _onStart(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final outcome = await controller.startRecording();
    if (outcome == StartRecordingOutcome.insufficientStorage &&
        context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.sd_storage_outlined),
          title: Text(AppStrings.errorTitle(AppErrorType.insufficientStorage)),
          content: Text(
            AppStrings.errorMessage(AppErrorType.insufficientStorage),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(AppStrings.close),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.appName)),
      body: Form(
        key: controller.formKey,
        child: ResponsiveBody(
          children: [
            Text(AppStrings.setupHeadline, style: textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              AppStrings.setupSubtitle,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: controller.patientIdController,
              decoration: const InputDecoration(
                labelText: AppStrings.patientIdLabel,
                hintText: AppStrings.patientIdHint,
                helperText: AppStrings.patientIdHelper,
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: AppConfig.patientIdMaxLength,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              validator: controller.validatePatientId,
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: controller.notesController,
              decoration: const InputDecoration(
                labelText: AppStrings.notesLabel,
                hintText: AppStrings.notesHint,
                prefixIcon: Icon(Icons.notes_outlined),
                alignLabelWithHint: true,
              ),
              minLines: 2,
              maxLines: 5,
              maxLength: AppConfig.notesMaxLength,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            const _InstructionsCard(),
            const SizedBox(height: 24),
            Obx(
              () => FilledButton.icon(
                onPressed: controller.isChecking.value
                    ? null
                    : () => _onStart(context),
                icon: controller.isChecking.value
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fiber_manual_record),
                label: Text(
                  controller.isChecking.value
                      ? AppStrings.checkingStorage
                      : AppStrings.startRecording,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Obx(() {
              final location = controller.saveLocation.value;
              if (location == null) return const SizedBox.shrink();
              return _SaveLocation(path: location);
            }),
          ],
        ),
      ),
    );
  }
}

class _InstructionsCard extends StatelessWidget {
  const _InstructionsCard();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(AppStrings.instructionsTitle, style: textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            for (final (index, step) in AppStrings.instructionsSteps.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${index + 1}.',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(child: Text(step, style: textTheme.bodyMedium)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SaveLocation extends StatelessWidget {
  const _SaveLocation({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.folder_outlined, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: SelectableText(
            '${AppStrings.saveLocationLabel}:\n$path',
            style: style,
          ),
        ),
      ],
    );
  }
}
