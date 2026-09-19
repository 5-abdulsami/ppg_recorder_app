import 'package:intl/intl.dart';

import '../../core/constants/app_config.dart';

/// Builds file names following `ppg_{patientID}_{yyyyMMdd_HHmmss}`.
abstract final class FileNaming {
  /// Base name (without extension) for a recording started at [startedAt].
  ///
  /// [patientId] must already be validated as file-name safe.
  static String baseName(String patientId, DateTime startedAt) {
    final stamp = DateFormat(AppConfig.fileTimestampFormat).format(startedAt);
    return 'ppg_${patientId}_$stamp';
  }
}
