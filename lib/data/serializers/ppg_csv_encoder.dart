import '../../signal/models/ppg_sample.dart';

/// Encodes raw PPG samples as CSV.
///
/// Columns: `frame_index, timestamp_ms, red_channel_value,
/// green_channel_value, blue_channel_value`. Timestamps have µs resolution
/// (3 decimals); channel means have 4 decimals. Values are unfiltered.
abstract final class PpgCsvEncoder {
  /// CSV header row.
  static const List<String> header = [
    'frame_index',
    'timestamp_ms',
    'red_channel_value',
    'green_channel_value',
    'blue_channel_value',
  ];

  /// Returns the full CSV document (header + one row per sample, `\n` line
  /// endings, trailing newline).
  static String encode(List<PpgSample> samples) {
    final buffer = StringBuffer()..writeln(header.join(','));
    for (final s in samples) {
      buffer
        ..write(s.frameIndex)
        ..write(',')
        ..write(s.timestampMs.toStringAsFixed(3))
        ..write(',')
        ..write(s.red.toStringAsFixed(4))
        ..write(',')
        ..write(s.green.toStringAsFixed(4))
        ..write(',')
        ..writeln(s.blue.toStringAsFixed(4));
    }
    return buffer.toString();
  }
}
