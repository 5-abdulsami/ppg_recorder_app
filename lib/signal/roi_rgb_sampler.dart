import 'dart:typed_data';

import 'models/rgb_mean.dart';
import 'signal_config.dart';

/// Raw bytes and layout of one image plane, decoupled from the camera plugin
/// so frame sampling can be unit-tested with synthetic buffers.
class ImagePlane {
  /// Creates a plane description.
  const ImagePlane({
    required this.bytes,
    required this.bytesPerRow,
    this.bytesPerPixel,
  });

  /// Plane pixel data.
  final Uint8List bytes;

  /// Row stride in bytes.
  final int bytesPerRow;

  /// Pixel stride in bytes (1 = planar, 2 = interleaved chroma). `null` is
  /// treated as 1.
  final int? bytesPerPixel;
}

/// Averages R/G/B over a centred square ROI of a camera frame.
///
/// Same ROI as Sphygma (centre 64×64 px) and the same full-range BT.601
/// YUV→RGB equations, with one correction: chroma samples are addressed
/// using the plane's pixel stride. Sphygma ignores it, which on most Android
/// devices (interleaved chroma, stride 2) reads the wrong U/V bytes.
///
/// Used for the live quality indicator only; the saved signal is extracted
/// from the recorded video by the native decoder.
class RoiRgbSampler {
  /// Creates a sampler with the given ROI side length in pixels.
  const RoiRgbSampler({this.roiSize = SignalConfig.roiSizePx});

  /// ROI side length in pixels.
  final int roiSize;

  /// Samples a YUV 4:2:0 frame (Y, U, V planes). Returns `null` if the frame
  /// layout is not usable.
  RgbMean? sampleYuv420({
    required int width,
    required int height,
    required List<ImagePlane> planes,
  }) {
    if (planes.length < 3 || width <= 0 || height <= 0) return null;
    final yPlane = planes[0];
    final uPlane = planes[1];
    final vPlane = planes[2];
    final yPixelStride = yPlane.bytesPerPixel ?? 1;
    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;
    final (x0, y0, x1, y1) = _roiBounds(width, height);

    var rSum = 0.0, gSum = 0.0, bSum = 0.0;
    var count = 0;
    for (var y = y0; y < y1; y++) {
      final yRow = y * yPlane.bytesPerRow;
      final uRow = (y >> 1) * uPlane.bytesPerRow;
      final vRow = (y >> 1) * vPlane.bytesPerRow;
      for (var x = x0; x < x1; x++) {
        final yIndex = yRow + x * yPixelStride;
        final uIndex = uRow + (x >> 1) * uPixelStride;
        final vIndex = vRow + (x >> 1) * vPixelStride;
        if (yIndex >= yPlane.bytes.length ||
            uIndex >= uPlane.bytes.length ||
            vIndex >= vPlane.bytes.length) {
          continue;
        }
        final luma = yPlane.bytes[yIndex].toDouble();
        final u = uPlane.bytes[uIndex] - 128.0;
        final v = vPlane.bytes[vIndex] - 128.0;
        rSum += _clamp(luma + 1.402 * v);
        gSum += _clamp(luma - 0.344136 * u - 0.714136 * v);
        bSum += _clamp(luma + 1.772 * u);
        count++;
      }
    }
    if (count == 0) return null;
    return RgbMean(rSum / count, gSum / count, bSum / count);
  }

  /// Samples a packed BGRA8888 frame (iOS). Returns `null` if unusable.
  RgbMean? sampleBgra8888({
    required int width,
    required int height,
    required ImagePlane plane,
  }) {
    if (width <= 0 || height <= 0) return null;
    final bytes = plane.bytes;
    final (x0, y0, x1, y1) = _roiBounds(width, height);
    var rSum = 0.0, gSum = 0.0, bSum = 0.0;
    var count = 0;
    for (var y = y0; y < y1; y++) {
      final row = y * plane.bytesPerRow;
      for (var x = x0; x < x1; x++) {
        final index = row + x * 4;
        if (index + 2 >= bytes.length) continue;
        bSum += bytes[index];
        gSum += bytes[index + 1];
        rSum += bytes[index + 2];
        count++;
      }
    }
    if (count == 0) return null;
    return RgbMean(rSum / count, gSum / count, bSum / count);
  }

  (int, int, int, int) _roiBounds(int width, int height) {
    final half = roiSize ~/ 2;
    final cx = width ~/ 2;
    final cy = height ~/ 2;
    return (
      (cx - half).clamp(0, width),
      (cy - half).clamp(0, height),
      (cx + half).clamp(0, width),
      (cy + half).clamp(0, height),
    );
  }

  static double _clamp(double value) =>
      value < 0 ? 0 : (value > 255 ? 255 : value);
}
