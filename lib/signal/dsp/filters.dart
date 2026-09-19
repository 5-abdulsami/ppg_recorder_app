import 'dart:math' as math;

import 'butterworth.dart';
import 'linear_algebra.dart';

/// Pure signal-conditioning primitives ported from the Sphygma backend
/// (`app/services/signal_processing.py`), which itself relies on SciPy.
///
/// Every function is side-effect free and returns a new list.

/// Arithmetic mean. Returns 0 for an empty list.
double mean(List<double> values) {
  if (values.isEmpty) return 0;
  var sum = 0.0;
  for (final v in values) {
    sum += v;
  }
  return sum / values.length;
}

/// Population standard deviation (NumPy `np.std`, `ddof=0`).
double standardDeviation(List<double> values) {
  if (values.isEmpty) return 0;
  final m = mean(values);
  var sum = 0.0;
  for (final v in values) {
    sum += (v - m) * (v - m);
  }
  return math.sqrt(sum / values.length);
}

/// Median. Returns 0 for an empty list.
double median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = List<double>.of(values)..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Removes the least-squares linear trend (backend `detrend`).
List<double> detrendLinear(List<double> signal) {
  final n = signal.length;
  if (n < 2) return List<double>.filled(n, 0);
  final xMean = (n - 1) / 2;
  final yMean = mean(signal);
  var numerator = 0.0;
  var denominator = 0.0;
  for (var i = 0; i < n; i++) {
    numerator += (i - xMean) * (signal[i] - yMean);
    denominator += (i - xMean) * (i - xMean);
  }
  final slope = numerator / denominator;
  final intercept = yMean - slope * xMean;
  return [for (var i = 0; i < n; i++) signal[i] - (slope * i + intercept)];
}

/// Removes slow baseline drift by subtracting a wide Savitzky-Golay (order 1)
/// estimate of the baseline (backend `robust_detrend`, default window 45).
///
/// Falls back to [detrendLinear] when the signal is shorter than the window.
List<double> robustDetrend(List<double> signal, {int windowSize = 45}) {
  if (signal.length < windowSize) return detrendLinear(signal);
  final window = windowSize.isEven ? windowSize + 1 : windowSize;
  if (signal.length < window) return detrendLinear(signal);
  final baseline = savitzkyGolay(signal, windowLength: window, polyOrder: 1);
  return [for (var i = 0; i < signal.length; i++) signal[i] - baseline[i]];
}

/// Zero-mean, unit-variance normalisation (backend `normalize`).
///
/// Throws [ArgumentError] if the signal has zero variance.
List<double> zScore(List<double> signal) {
  final std = standardDeviation(signal);
  if (std == 0) {
    throw ArgumentError('Signal has zero variance; cannot normalise.');
  }
  final m = mean(signal);
  return [for (final v in signal) (v - m) / std];
}

/// Savitzky-Golay smoothing, equivalent to
/// `scipy.signal.savgol_filter(x, windowLength, polyOrder)` with the default
/// `mode='interp'` (polynomial fit on the edge windows).
///
/// Throws [ArgumentError] if [windowLength] is even, not greater than
/// [polyOrder], or longer than the signal.
List<double> savitzkyGolay(
  List<double> signal, {
  required int windowLength,
  required int polyOrder,
}) {
  if (windowLength.isEven || windowLength <= polyOrder) {
    throw ArgumentError(
      'windowLength must be odd and greater than polyOrder '
      '(got $windowLength, $polyOrder).',
    );
  }
  final n = signal.length;
  if (n < windowLength) {
    throw ArgumentError(
      'Signal length $n is shorter than the window length $windowLength.',
    );
  }
  final half = windowLength ~/ 2;
  final output = List<double>.filled(n, 0);

  // Interior: fixed convolution weights evaluating the fit at the centre.
  final centreWeights = _polyFitWeights(windowLength, polyOrder, half);
  for (var i = half; i < n - half; i++) {
    var sum = 0.0;
    for (var k = 0; k < windowLength; k++) {
      sum += centreWeights[k] * signal[i - half + k];
    }
    output[i] = sum;
  }

  // Edges: fit one polynomial to the first/last window and evaluate it.
  for (var pos = 0; pos < half; pos++) {
    final weights = _polyFitWeights(windowLength, polyOrder, pos);
    var sum = 0.0;
    for (var k = 0; k < windowLength; k++) {
      sum += weights[k] * signal[k];
    }
    output[pos] = sum;
  }
  final tailStart = n - windowLength;
  for (var pos = windowLength - half; pos < windowLength; pos++) {
    final weights = _polyFitWeights(windowLength, polyOrder, pos);
    var sum = 0.0;
    for (var k = 0; k < windowLength; k++) {
      sum += weights[k] * signal[tailStart + k];
    }
    output[tailStart + pos] = sum;
  }
  return output;
}

/// Least-squares weights `w` such that `Σ w[k]·y[k]` is the value at [position]
/// of the degree-[order] polynomial fitted to `y[0..length-1]`.
List<double> _polyFitWeights(int length, int order, int position) {
  final terms = order + 1;
  // Design matrix with the evaluation point at t = 0 for good conditioning.
  final design = [
    for (var k = 0; k < length; k++)
      [for (var j = 0; j < terms; j++) math.pow(k - position, j).toDouble()],
  ];
  final normal = [
    for (var r = 0; r < terms; r++)
      [
        for (var c = 0; c < terms; c++)
          [for (var k = 0; k < length; k++) design[k][r] * design[k][c]]
              .fold<double>(0, (a, b) => a + b),
      ],
  ];
  final unitVector = [for (var j = 0; j < terms; j++) j == 0 ? 1.0 : 0.0];
  final u = solveLinearSystem(normal, unitVector);
  return [
    for (var k = 0; k < length; k++)
      [for (var j = 0; j < terms; j++) design[k][j] * u[j]]
          .fold<double>(0, (a, b) => a + b),
  ];
}

/// Direct-form II transposed IIR filter (`scipy.signal.lfilter`), optionally
/// seeded with initial state [initialState] (length `max(len(a),len(b)) - 1`).
List<double> lfilter(
  FilterCoefficients coefficients,
  List<double> signal, {
  List<double>? initialState,
}) {
  final (b, a) = _normalisedCoefficients(coefficients);
  final order = b.length - 1;
  final state = initialState == null
      ? List<double>.filled(order, 0)
      : List<double>.of(initialState);
  if (state.length != order) {
    throw ArgumentError('Initial state must have length $order.');
  }
  final output = List<double>.filled(signal.length, 0);
  for (var n = 0; n < signal.length; n++) {
    final x = signal[n];
    final y = b[0] * x + (order > 0 ? state[0] : 0);
    for (var i = 0; i < order - 1; i++) {
      state[i] = b[i + 1] * x + state[i + 1] - a[i + 1] * y;
    }
    if (order > 0) state[order - 1] = b[order] * x - a[order] * y;
    output[n] = y;
  }
  return output;
}

/// Steady-state initial conditions for a step response
/// (`scipy.signal.lfilter_zi`).
List<double> lfilterZi(FilterCoefficients coefficients) {
  final (b, a) = _normalisedCoefficients(coefficients);
  final n = a.length;
  if (n < 2) return const [];
  // (I - companion(a).T) · zi = b[1:] - a[1:]·b[0]
  final matrix = [
    for (var i = 0; i < n - 1; i++)
      [
        for (var j = 0; j < n - 1; j++)
          (i == j ? 1.0 : 0.0) -
              (j == 0 ? -a[i + 1] : 0.0) -
              (j == i + 1 ? 1.0 : 0.0),
      ],
  ];
  final rhs = [for (var i = 1; i < n; i++) b[i] - a[i] * b[0]];
  return solveLinearSystem(matrix, rhs);
}

/// Zero-phase forward-backward filtering, equivalent to
/// `scipy.signal.filtfilt(b, a, x)` with its defaults (`padtype='odd'`,
/// `padlen = 3·max(len(a), len(b))`, steady-state initial conditions).
///
/// Throws [ArgumentError] if the signal is not longer than the padding.
List<double> filtfilt(FilterCoefficients coefficients, List<double> signal) {
  final taps = math.max(coefficients.a.length, coefficients.b.length);
  final edge = 3 * taps;
  final n = signal.length;
  if (n <= edge) {
    throw ArgumentError(
      'Signal length $n must be greater than the filter padding $edge.',
    );
  }

  // Odd extension at both ends.
  final extended = <double>[
    for (var i = edge; i >= 1; i--) 2 * signal[0] - signal[i],
    ...signal,
    for (var i = n - 2; i >= n - 1 - edge; i--) 2 * signal[n - 1] - signal[i],
  ];

  final zi = lfilterZi(coefficients);
  final forward = lfilter(
    coefficients,
    extended,
    initialState: [for (final z in zi) z * extended.first],
  );
  final reversed = forward.reversed.toList();
  final backward = lfilter(
    coefficients,
    reversed,
    initialState: [for (final z in zi) z * reversed.first],
  );
  final result = backward.reversed.toList();
  return result.sublist(edge, edge + n);
}

/// Butterworth band-pass applied with [filtfilt] (backend `bandpass_filter`).
List<double> bandpassFilter(
  List<double> signal, {
  required double sampleRateHz,
  required double lowHz,
  required double highHz,
  int order = 4,
}) {
  final coefficients = butterworthBandpass(
    order: order,
    lowHz: lowHz,
    highHz: highHz,
    sampleRateHz: sampleRateHz,
  );
  return filtfilt(coefficients, signal);
}

/// Normalises `b`/`a` so `a[0] == 1` and pads both to equal length.
(List<double>, List<double>) _normalisedCoefficients(FilterCoefficients c) {
  final a0 = c.a.first;
  if (a0 == 0) throw ArgumentError('a[0] must be non-zero.');
  final length = math.max(c.a.length, c.b.length);
  final b = [
    for (var i = 0; i < length; i++) i < c.b.length ? c.b[i] / a0 : 0.0,
  ];
  final a = [
    for (var i = 0; i < length; i++) i < c.a.length ? c.a[i] / a0 : 0.0,
  ];
  return (b, a);
}
