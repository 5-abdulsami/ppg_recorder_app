import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';

/// Lightweight line chart of a PPG waveform over time.
///
/// Uses min/max decimation per horizontal pixel so every peak stays visible
/// regardless of screen width.
class WaveformChart extends StatelessWidget {
  /// Creates a chart. [times] (s) and [values] must have equal length.
  const WaveformChart({
    super.key,
    required this.times,
    required this.values,
    required this.color,
    this.height = 220,
  });

  /// Sample times in seconds.
  final List<double> times;

  /// Sample values.
  final List<double> values;

  /// Line colour.
  final Color color;

  /// Chart height.
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppStrings.waveformTitle,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _WaveformPainter(
            times: times,
            values: values,
            color: color,
            labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ) ??
                const TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.times,
    required this.values,
    required this.color,
    required this.labelStyle,
  });

  final List<double> times;
  final List<double> values;
  final Color color;
  final TextStyle labelStyle;

  static const double _axisHeight = 18;

  @override
  void paint(Canvas canvas, Size size) {
    if (times.length < 2 || values.length != times.length) return;
    final plot = Rect.fromLTWH(0, 4, size.width, size.height - _axisHeight - 4);
    final t0 = times.first;
    final t1 = times.last;
    final span = t1 - t0;
    if (span <= 0 || plot.width <= 0 || plot.height <= 0) return;

    var minV = double.infinity;
    var maxV = double.negativeInfinity;
    for (final v in values) {
      if (!v.isFinite) continue;
      minV = math.min(minV, v);
      maxV = math.max(maxV, v);
    }
    if (!minV.isFinite) return;
    if (maxV - minV < 1e-9) {
      maxV += 0.5;
      minV -= 0.5;
    }
    final pad = (maxV - minV) * 0.08;
    minV -= pad;
    maxV += pad;

    double x(double t) => plot.left + (t - t0) / span * plot.width;
    double y(double v) =>
        plot.bottom - (v - minV) / (maxV - minV) * plot.height;

    // Grid: vertical line every 5 s with labels.
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    final step = span > 20 ? 5.0 : (span > 8 ? 2.0 : 1.0);
    for (var t = 0.0; t <= span + 1e-6; t += step) {
      final gx = x(t0 + t);
      canvas.drawLine(Offset(gx, plot.top), Offset(gx, plot.bottom), gridPaint);
      final painter = TextPainter(
        text: TextSpan(
          text: '${t.round()}${AppStrings.timeAxisUnit}',
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final lx = (gx - painter.width / 2).clamp(0.0, size.width - painter.width);
      painter.paint(canvas, Offset(lx, plot.bottom + 3));
    }
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      gridPaint,
    );

    // Min/max decimation per pixel column.
    final columns = math.max(1, plot.width.floor());
    final path = Path();
    if (values.length <= columns * 2) {
      path.moveTo(x(times.first), y(values.first));
      for (var i = 1; i < values.length; i++) {
        path.lineTo(x(times[i]), y(values[i]));
      }
    } else {
      var started = false;
      var i = 0;
      for (var col = 0; col < columns; col++) {
        final colEnd = t0 + (col + 1) / columns * span;
        final lastColumn = col == columns - 1;
        var minIndex = -1;
        var maxIndex = -1;
        while (i < values.length && (lastColumn || times[i] <= colEnd)) {
          if (minIndex < 0 || values[i] < values[minIndex]) minIndex = i;
          if (maxIndex < 0 || values[i] > values[maxIndex]) maxIndex = i;
          i++;
        }
        if (minIndex < 0) continue;
        // Draw the column's extremes in their original time order.
        final firstValue = values[math.min(minIndex, maxIndex)];
        final secondValue = values[math.max(minIndex, maxIndex)];
        final px = plot.left + col + 0.5;
        if (started) {
          path.lineTo(px, y(firstValue));
        } else {
          path.moveTo(px, y(firstValue));
          started = true;
        }
        path.lineTo(px, y(secondValue));
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      !identical(old.values, values) ||
      !identical(old.times, times) ||
      old.color != color;
}
