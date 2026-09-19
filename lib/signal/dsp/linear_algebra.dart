/// Solves the dense linear system `A·x = b` with Gaussian elimination and
/// partial pivoting.
///
/// Intended for the tiny systems used in filter initial conditions and
/// Savitzky-Golay design (≤ 10 unknowns). [matrix] and [rhs] are not modified.
///
/// Throws [StateError] if the matrix is singular.
List<double> solveLinearSystem(List<List<double>> matrix, List<double> rhs) {
  final n = rhs.length;
  if (matrix.length != n || matrix.any((row) => row.length != n)) {
    throw ArgumentError('Matrix must be square and match the right-hand side.');
  }
  final a = [for (final row in matrix) List<double>.of(row)];
  final b = List<double>.of(rhs);

  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var row = col + 1; row < n; row++) {
      if (a[row][col].abs() > a[pivot][col].abs()) pivot = row;
    }
    if (a[pivot][col].abs() < 1e-300) {
      throw StateError('Singular matrix in linear solve.');
    }
    if (pivot != col) {
      final tmpRow = a[col];
      a[col] = a[pivot];
      a[pivot] = tmpRow;
      final tmp = b[col];
      b[col] = b[pivot];
      b[pivot] = tmp;
    }
    for (var row = col + 1; row < n; row++) {
      final factor = a[row][col] / a[col][col];
      if (factor == 0) continue;
      for (var k = col; k < n; k++) {
        a[row][k] -= factor * a[col][k];
      }
      b[row] -= factor * b[col];
    }
  }

  final x = List<double>.filled(n, 0);
  for (var row = n - 1; row >= 0; row--) {
    var sum = b[row];
    for (var k = row + 1; k < n; k++) {
      sum -= a[row][k] * x[k];
    }
    x[row] = sum / a[row][row];
  }
  return x;
}
