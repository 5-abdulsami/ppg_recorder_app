import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/quality_colors.dart';
import '../../../signal/live_quality_monitor.dart';
import '../../../signal/models/quality_level.dart';

/// Traffic-light pill showing live finger coverage / motion quality.
class LiveQualityIndicator extends StatelessWidget {
  /// Creates the indicator. [level] `null` means unknown.
  const LiveQualityIndicator({
    super.key,
    required this.level,
    required this.issue,
    required this.available,
  });

  /// Current level.
  final QualityLevel? level;

  /// Current issue.
  final LiveQualityIssue issue;

  /// Whether live frames are available at all.
  final bool available;

  @override
  Widget build(BuildContext context) {
    final effectiveLevel = available ? level : null;
    final color = qualityColor(effectiveLevel);
    final text = !available
        ? AppStrings.liveQualityUnavailable
        : effectiveLevel == null
        ? AppStrings.liveQualityWaiting
        : AppStrings.liveQualityText(effectiveLevel, issue);

    return Semantics(
      liveRegion: true,
      label: '${AppStrings.liveQualityLabel}: $text',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
