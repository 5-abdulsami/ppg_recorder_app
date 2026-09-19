/// Mean red/green/blue intensity (0–255) over a frame's region of interest.
class RgbMean {
  /// Creates an RGB mean triple.
  const RgbMean(this.red, this.green, this.blue);

  /// Mean red channel intensity.
  final double red;

  /// Mean green channel intensity.
  final double green;

  /// Mean blue channel intensity.
  final double blue;

  @override
  String toString() =>
      'RgbMean(r: ${red.toStringAsFixed(2)}, g: ${green.toStringAsFixed(2)}, '
      'b: ${blue.toStringAsFixed(2)})';
}
