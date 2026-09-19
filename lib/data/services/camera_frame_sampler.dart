import 'package:camera/camera.dart';

import '../../signal/models/rgb_mean.dart';
import '../../signal/roi_rgb_sampler.dart';

/// Adapts `camera` plugin frames to the plugin-independent [RoiRgbSampler].
class CameraFrameSampler {
  /// Creates an adapter around [sampler].
  const CameraFrameSampler({RoiRgbSampler sampler = const RoiRgbSampler()})
    : _sampler = sampler;

  final RoiRgbSampler _sampler;

  /// ROI channel means of [image], or `null` if the format is unsupported
  /// or the frame is malformed.
  RgbMean? sample(CameraImage image) {
    try {
      final planes = [
        for (final p in image.planes)
          ImagePlane(
            bytes: p.bytes,
            bytesPerRow: p.bytesPerRow,
            bytesPerPixel: p.bytesPerPixel,
          ),
      ];
      return switch (image.format.group) {
        ImageFormatGroup.bgra8888 when planes.isNotEmpty =>
          _sampler.sampleBgra8888(
            width: image.width,
            height: image.height,
            plane: planes.first,
          ),
        ImageFormatGroup.yuv420 => _sampler.sampleYuv420(
          width: image.width,
          height: image.height,
          planes: planes,
        ),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }
}
