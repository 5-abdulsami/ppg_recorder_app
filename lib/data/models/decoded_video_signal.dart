/// Per-frame ROI channel means decoded natively from a video file, plus
/// details of how they were obtained.
class DecodedVideoSignal {
  /// Creates a decoded signal. All per-frame lists have equal length.
  const DecodedVideoSignal({
    required this.timestampsUs,
    required this.red,
    required this.green,
    required this.blue,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.durationMs,
    required this.colorConversion,
    required this.decoderName,
  });

  /// Presentation timestamp of each frame (µs, container time base).
  final List<int> timestampsUs;

  /// Mean red per frame.
  final List<double> red;

  /// Mean green per frame.
  final List<double> green;

  /// Mean blue per frame.
  final List<double> blue;

  /// Decoded frame width (px).
  final int width;

  /// Decoded frame height (px).
  final int height;

  /// Rotation stored in the video container (degrees).
  final int rotationDegrees;

  /// Container-reported duration (ms), 0 if unknown.
  final double durationMs;

  /// Description of the YUV→RGB conversion used.
  final String colorConversion;

  /// Name of the platform decoder.
  final String decoderName;

  /// Number of decoded frames.
  int get frameCount => timestampsUs.length;
}
