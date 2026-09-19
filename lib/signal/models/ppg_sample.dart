/// One PPG sample: the ROI channel means of a single decoded video frame.
///
/// This is exactly one row of the exported CSV.
class PpgSample {
  /// Creates a sample.
  const PpgSample({
    required this.frameIndex,
    required this.timestampMs,
    required this.red,
    required this.green,
    required this.blue,
  });

  /// Zero-based frame index in presentation order.
  final int frameIndex;

  /// Presentation time relative to the first frame, in milliseconds.
  final double timestampMs;

  /// Mean red intensity (0–255).
  final double red;

  /// Mean green intensity (0–255).
  final double green;

  /// Mean blue intensity (0–255).
  final double blue;
}
