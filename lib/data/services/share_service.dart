import 'dart:ui';

import 'package:share_plus/share_plus.dart';

import '../../core/errors/app_exception.dart';

/// Opens the native share sheet for files.
abstract interface class ShareService {
  /// Shares [paths]. [origin] anchors the popover on iPad.
  /// Throws [AppException] ([AppErrorType.shareFailed]).
  Future<void> shareFiles(
    List<String> paths, {
    required String subject,
    required String text,
    Rect? origin,
  });
}

/// [ShareService] backed by `share_plus`.
class PluginShareService implements ShareService {
  @override
  Future<void> shareFiles(
    List<String> paths, {
    required String subject,
    required String text,
    Rect? origin,
  }) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            for (final p in paths) XFile(p, mimeType: _mimeType(p)),
          ],
          subject: subject,
          text: text,
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      throw AppException(
        AppErrorType.shareFailed,
        details: e.toString(),
        cause: e,
      );
    }
  }

  static String _mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    return 'application/octet-stream';
  }
}
