import 'dart:math' as math;

import 'filters.dart';

/// One-sided power spectral density estimate.
class PowerSpectrum {
  /// Creates a spectrum from matching frequency / power lists.
  const PowerSpectrum({required this.frequencies, required this.power});

  /// Bin centre frequencies in Hz.
  final List<double> frequencies;

  /// Power spectral density per bin (units²/Hz).
  final List<double> power;
}

/// Dominant frequency inside a band and how strongly it stands out.
class BandPeak {
  /// Creates a band peak result.
  const BandPeak({required this.frequencyHz, required this.confidence});

  /// Frequency of the highest-power bin inside the band.
  final double frequencyHz;

  /// Peak-to-mean power ratio divided by 10 and clipped to `[0, 1]` — the
  /// Sphygma backend's heart-rate confidence heuristic.
  final double confidence;
}

/// Welch power spectral density, equivalent to
/// `scipy.signal.welch(x, fs, nperseg=segmentLength)` with SciPy defaults:
/// periodic Hann window, 50 % overlap, constant detrend per segment,
/// one-sided density scaling.
///
/// Throws [ArgumentError] if the signal is shorter than [segmentLength].
PowerSpectrum welch(
  List<double> signal, {
  required double sampleRateHz,
  required int segmentLength,
}) {
  final n = signal.length;
  if (segmentLength < 2 || n < segmentLength) {
    throw ArgumentError(
      'Welch needs 2 ≤ segmentLength ($segmentLength) ≤ signal length ($n).',
    );
  }
  final overlap = segmentLength ~/ 2;
  final step = segmentLength - overlap;
  final segmentCount = (n - overlap) ~/ step;

  final window = [
    for (var i = 0; i < segmentLength; i++)
      0.5 - 0.5 * math.cos(2 * math.pi * i / segmentLength),
  ];
  final windowPower = window.fold<double>(0, (s, w) => s + w * w);
  final scale = 1 / (sampleRateHz * windowPower);
  final binCount = segmentLength ~/ 2 + 1;
  final power = List<double>.filled(binCount, 0);

  for (var s = 0; s < segmentCount; s++) {
    final start = s * step;
    final segment = signal.sublist(start, start + segmentLength);
    final segmentMean = mean(segment);
    final windowed = [
      for (var i = 0; i < segmentLength; i++)
        (segment[i] - segmentMean) * window[i],
    ];
    for (var k = 0; k < binCount; k++) {
      var re = 0.0;
      var im = 0.0;
      final omega = -2 * math.pi * k / segmentLength;
      for (var i = 0; i < segmentLength; i++) {
        re += windowed[i] * math.cos(omega * i);
        im += windowed[i] * math.sin(omega * i);
      }
      var p = (re * re + im * im) * scale;
      final isNyquist = segmentLength.isEven && k == binCount - 1;
      if (k != 0 && !isNyquist) p *= 2;
      power[k] += p;
    }
  }
  for (var k = 0; k < binCount; k++) {
    power[k] /= segmentCount;
  }
  return PowerSpectrum(
    frequencies: [
      for (var k = 0; k < binCount; k++) k * sampleRateHz / segmentLength,
    ],
    power: power,
  );
}

/// Finds the strongest bin of [spectrum] within `[lowHz, highHz]`
/// (backend `HeartRateService._calculate_frequency_domain`).
///
/// Returns `null` if no bin falls inside the band.
BandPeak? dominantPeakInBand(
  PowerSpectrum spectrum, {
  required double lowHz,
  required double highHz,
}) {
  var peakIndex = -1;
  var peakPower = double.negativeInfinity;
  var bandSum = 0.0;
  var bandCount = 0;
  for (var k = 0; k < spectrum.frequencies.length; k++) {
    final f = spectrum.frequencies[k];
    if (f < lowHz || f > highHz) continue;
    final p = spectrum.power[k];
    bandSum += p;
    bandCount++;
    if (p > peakPower) {
      peakPower = p;
      peakIndex = k;
    }
  }
  if (bandCount == 0) return null;
  final snr = peakPower / (bandSum / bandCount + 1e-9);
  return BandPeak(
    frequencyHz: spectrum.frequencies[peakIndex],
    confidence: math.min(1.0, snr / 10.0),
  );
}
