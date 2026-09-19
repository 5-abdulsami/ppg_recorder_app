import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ppg_recorder_app/signal/roi_rgb_sampler.dart';

void main() {
  const sampler = RoiRgbSampler(roiSize: 4);

  /// Full-range BT.601 reference used by the sampler.
  (double, double, double) toRgb(int y, int u, int v) {
    double clamp(double x) => x.clamp(0, 255).toDouble();
    final du = u - 128.0, dv = v - 128.0;
    return (
      clamp(y + 1.402 * dv),
      clamp(y - 0.344136 * du - 0.714136 * dv),
      clamp(y + 1.772 * du),
    );
  }

  group('sampleYuv420', () {
    const width = 8, height = 8;

    test('interleaved chroma (pixel stride 2) reads the correct U/V', () {
      // Y everywhere 150; interleaved UV buffer where U=100 and V=200 in the
      // centre region and garbage (0) elsewhere.
      final y = Uint8List(width * height)..fillRange(0, width * height, 150);
      const chromaRowStride = width; // 4 chroma pixels * stride 2
      final uv = Uint8List(chromaRowStride * height ~/ 2);
      for (var cy = 0; cy < height ~/ 2; cy++) {
        for (var cx = 0; cx < width ~/ 2; cx++) {
          uv[cy * chromaRowStride + cx * 2] = 100; // U
          uv[cy * chromaRowStride + cx * 2 + 1] = 200; // V
        }
      }
      // Android exposes U and V as views offset by one byte into the same
      // interleaved buffer.
      final uPlane = ImagePlane(
        bytes: uv,
        bytesPerRow: chromaRowStride,
        bytesPerPixel: 2,
      );
      final vPlane = ImagePlane(
        bytes: Uint8List.sublistView(uv, 1),
        bytesPerRow: chromaRowStride,
        bytesPerPixel: 2,
      );
      final result = sampler.sampleYuv420(
        width: width,
        height: height,
        planes: [
          ImagePlane(bytes: y, bytesPerRow: width, bytesPerPixel: 1),
          uPlane,
          vPlane,
        ],
      )!;
      final expected = toRgb(150, 100, 200);
      expect(result.red, closeTo(expected.$1, 1e-9));
      expect(result.green, closeTo(expected.$2, 1e-9));
      expect(result.blue, closeTo(expected.$3, 1e-9));
    });

    test('planar chroma (pixel stride 1) and ROI centring', () {
      // Centre 4x4 has Y=200; the border has Y=0 and must be ignored.
      final y = Uint8List(width * height);
      for (var row = 2; row < 6; row++) {
        for (var col = 2; col < 6; col++) {
          y[row * width + col] = 200;
        }
      }
      final u = Uint8List(16)..fillRange(0, 16, 128);
      final v = Uint8List(16)..fillRange(0, 16, 128);
      final result = sampler.sampleYuv420(
        width: width,
        height: height,
        planes: [
          ImagePlane(bytes: y, bytesPerRow: width),
          ImagePlane(bytes: u, bytesPerRow: 4),
          ImagePlane(bytes: v, bytesPerRow: 4),
        ],
      )!;
      expect(result.red, closeTo(200, 1e-9));
      expect(result.green, closeTo(200, 1e-9));
      expect(result.blue, closeTo(200, 1e-9));
    });

    test('returns null for missing planes', () {
      expect(
        sampler.sampleYuv420(
          width: width,
          height: height,
          planes: [ImagePlane(bytes: Uint8List(64), bytesPerRow: 8)],
        ),
        isNull,
      );
    });
  });

  test('sampleBgra8888 averages the centre ROI in BGRA order', () {
    const width = 8, height = 8;
    final bytes = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i++) {
      bytes[i * 4] = 10; // B
      bytes[i * 4 + 1] = 20; // G
      bytes[i * 4 + 2] = 30; // R
      bytes[i * 4 + 3] = 255; // A
    }
    final result = sampler.sampleBgra8888(
      width: width,
      height: height,
      plane: ImagePlane(bytes: bytes, bytesPerRow: width * 4),
    )!;
    expect(result.red, 30);
    expect(result.green, 20);
    expect(result.blue, 10);
  });
}
