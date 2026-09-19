import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Circular, cover-fitted live camera preview with a progress ring around it.
class CameraPreviewCircle extends StatelessWidget {
  /// Creates the preview. [controller] may be `null` (shows a placeholder).
  const CameraPreviewCircle({
    super.key,
    required this.controller,
    required this.diameter,
    required this.progress,
    required this.ringColor,
  });

  /// Initialised camera controller, or `null`.
  final CameraController? controller;

  /// Preview diameter in logical pixels.
  final double diameter;

  /// Ring fill, 0–1.
  final double progress;

  /// Ring colour.
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    const ringWidth = 8.0;
    const gap = 6.0;
    final outer = diameter + 2 * (ringWidth + gap);
    return SizedBox.square(
      dimension: outer,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.square(
            dimension: outer - ringWidth,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: ringWidth,
              color: ringColor,
              backgroundColor: Colors.white12,
              strokeCap: StrokeCap.round,
            ),
          ),
          ClipOval(
            child: SizedBox.square(
              dimension: diameter,
              child: _preview(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview() {
    final c = controller;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white54)),
      );
    }
    final size = c.value.previewSize;
    // previewSize is reported in landscape; swap for the portrait UI.
    final width = size?.height ?? diameter;
    final height = size?.width ?? diameter;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(width: width, height: height, child: CameraPreview(c)),
    );
  }
}
