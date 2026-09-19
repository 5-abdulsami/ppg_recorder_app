import 'dart:math' as math;

import 'complex.dart';

/// Transfer-function coefficients of a digital IIR filter (`b` numerator,
/// `a` denominator), in the same layout SciPy returns with `output='ba'`.
class FilterCoefficients {
  /// Creates filter coefficients.
  const FilterCoefficients({required this.b, required this.a});

  /// Numerator coefficients, highest power first.
  final List<double> b;

  /// Denominator coefficients, highest power first (`a[0]` is 1).
  final List<double> a;
}

/// Designs a digital Butterworth band-pass filter.
///
/// This is a direct port of SciPy's `butter(order, [low, high], btype='band')`
/// (analog prototype → band-pass transform → bilinear transform → polynomial
/// expansion), so the coefficients match the Sphygma backend's
/// `bandpass_filter` exactly for the same parameters.
///
/// Throws [ArgumentError] if the cut-offs are not `0 < low < high < fs/2`.
FilterCoefficients butterworthBandpass({
  required int order,
  required double lowHz,
  required double highHz,
  required double sampleRateHz,
}) {
  if (order < 1) {
    throw ArgumentError.value(order, 'order', 'Must be at least 1.');
  }
  final nyquist = sampleRateHz / 2;
  final low = lowHz / nyquist;
  final high = highHz / nyquist;
  if (!(low > 0 && high < 1 && low < high)) {
    throw ArgumentError(
      'Invalid band-pass cut-offs: low=$lowHz Hz, high=$highHz Hz '
      'for a sample rate of $sampleRateHz Hz.',
    );
  }

  // 1. Analog Butterworth prototype poles (scipy.signal.buttap).
  final prototypePoles = <Complex>[
    for (var m = -order + 1; m < order; m += 2)
      -Complex.expI(math.pi * m / (2 * order)),
  ];

  // 2. Pre-warp the cut-offs (SciPy uses fs = 2 for normalised frequencies).
  const designFs = 2.0;
  final warpedLow = 2 * designFs * math.tan(math.pi * low / designFs);
  final warpedHigh = 2 * designFs * math.tan(math.pi * high / designFs);
  final bandwidth = warpedHigh - warpedLow;
  final centre = math.sqrt(warpedLow * warpedHigh);

  // 3. Low-pass → band-pass transform (scipy.signal.lp2bp_zpk).
  final scaledPoles = prototypePoles.map((p) => p.scale(bandwidth / 2));
  final centreSquared = Complex(centre * centre);
  final bandPoles = <Complex>[
    for (final p in scaledPoles) p + (p * p - centreSquared).sqrt(),
    for (final p in scaledPoles) p - (p * p - centreSquared).sqrt(),
  ];
  final bandZeros = List<Complex>.filled(order, const Complex(0));
  final bandGain = math.pow(bandwidth, order).toDouble();

  // 4. Bilinear transform (scipy.signal.bilinear_zpk).
  const fs2 = Complex(2 * designFs);
  final digitalZeros = <Complex>[
    for (final z in bandZeros) (fs2 + z) / (fs2 - z),
    for (var i = 0; i < bandPoles.length - bandZeros.length; i++)
      const Complex(-1),
  ];
  final digitalPoles = [for (final p in bandPoles) (fs2 + p) / (fs2 - p)];
  var zerosProduct = const Complex(1);
  for (final z in bandZeros) {
    zerosProduct = zerosProduct * (fs2 - z);
  }
  var polesProduct = const Complex(1);
  for (final p in bandPoles) {
    polesProduct = polesProduct * (fs2 - p);
  }
  final digitalGain = bandGain * (zerosProduct / polesProduct).re;

  // 5. Zeros/poles → polynomial coefficients (scipy.signal.zpk2tf).
  final b = _polyFromRoots(digitalZeros).map((c) => c * digitalGain).toList();
  final a = _polyFromRoots(digitalPoles);
  return FilterCoefficients(b: b, a: a);
}

/// Expands `Π (x - root)` into real polynomial coefficients, highest power
/// first (equivalent to `numpy.poly(...).real`).
List<double> _polyFromRoots(List<Complex> roots) {
  var coefficients = <Complex>[const Complex(1)];
  for (final root in roots) {
    final next = List<Complex>.filled(coefficients.length + 1, const Complex(0));
    for (var i = 0; i < coefficients.length; i++) {
      next[i] = next[i] + coefficients[i];
      next[i + 1] = next[i + 1] - coefficients[i] * root;
    }
    coefficients = next;
  }
  return [for (final c in coefficients) c.re];
}
