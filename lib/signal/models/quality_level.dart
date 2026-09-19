/// Traffic-light signal quality classification shared by the live indicator
/// and the post-capture report.
enum QualityLevel {
  /// Clean, usable signal.
  good,

  /// Usable but degraded; the researcher may want to retake.
  fair,

  /// Likely unusable.
  poor;

  /// Higher value = worse quality (used to pick the worst of several levels).
  int get severity => index;

  /// Stable identifier written to metadata files.
  String get id => name;
}
