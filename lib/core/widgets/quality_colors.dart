import 'package:flutter/material.dart';

import '../../signal/models/quality_level.dart';
import '../constants/app_colors.dart';

/// Maps a [QualityLevel] (or `null` = unknown) to its traffic-light colour.
Color qualityColor(QualityLevel? level) => switch (level) {
  QualityLevel.good => AppColors.qualityGood,
  QualityLevel.fair => AppColors.qualityFair,
  QualityLevel.poor => AppColors.qualityPoor,
  null => AppColors.qualityUnknown,
};
