import 'dart:math' as math;

/// Minimal immutable complex number used by the IIR filter-design routines.
///
/// Only the operations required for Butterworth design (arithmetic, principal
/// square root) are implemented.
class Complex {
  /// Creates a complex number `re + i·im`.
  const Complex(this.re, [this.im = 0]);

  /// Real part.
  final double re;

  /// Imaginary part.
  final double im;

  /// Returns `e^(i·theta)`.
  factory Complex.expI(double theta) =>
      Complex(math.cos(theta), math.sin(theta));

  /// Complex addition.
  Complex operator +(Complex other) => Complex(re + other.re, im + other.im);

  /// Complex subtraction.
  Complex operator -(Complex other) => Complex(re - other.re, im - other.im);

  /// Negation.
  Complex operator -() => Complex(-re, -im);

  /// Complex multiplication.
  Complex operator *(Complex other) =>
      Complex(re * other.re - im * other.im, re * other.im + im * other.re);

  /// Complex division.
  Complex operator /(Complex other) {
    final denominator = other.re * other.re + other.im * other.im;
    return Complex(
      (re * other.re + im * other.im) / denominator,
      (im * other.re - re * other.im) / denominator,
    );
  }

  /// Multiplies by a real scalar.
  Complex scale(double factor) => Complex(re * factor, im * factor);

  /// Principal square root (same branch as NumPy's `sqrt` for complex input).
  Complex sqrt() {
    final magnitude = math.sqrt(re * re + im * im);
    if (magnitude == 0) return const Complex(0);
    final t = math.sqrt((magnitude + re.abs()) / 2);
    if (re >= 0) return Complex(t, im / (2 * t));
    return Complex(im.abs() / (2 * t), im >= 0 ? t : -t);
  }

  @override
  String toString() => '($re${im >= 0 ? '+' : '-'}${im.abs()}i)';
}
