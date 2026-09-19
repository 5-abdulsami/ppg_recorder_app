import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';

/// Full-screen message with an icon, explanation and action buttons, used
/// for permission problems and errors on the dark recording screen.
class RecordingStatusView extends StatelessWidget {
  /// Creates the view.
  const RecordingStatusView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onSecondary,
    this.details,
  });

  /// Leading icon.
  final IconData icon;

  /// Headline.
  final String title;

  /// Explanation.
  final String message;

  /// Optional technical details (small print).
  final String? details;

  /// Main action label.
  final String primaryLabel;

  /// Main action.
  final VoidCallback onPrimary;

  /// "Go back" action.
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 64, color: Colors.white70),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(color: Colors.white70),
              ),
              if (details != null && details!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '${AppStrings.technicalDetails}: $details',
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: Colors.white38),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onSecondary,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                ),
                child: const Text(AppStrings.goBack),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
