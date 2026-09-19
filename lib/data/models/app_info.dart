/// Application and device details recorded in metadata for provenance.
class AppInfo {
  /// Creates app info.
  const AppInfo({
    required this.appName,
    required this.version,
    required this.buildNumber,
    required this.platform,
    required this.osVersion,
    required this.manufacturer,
    required this.model,
  });

  /// App display name.
  final String appName;

  /// Semantic version (e.g. `1.0.0`).
  final String version;

  /// Build number.
  final String buildNumber;

  /// `android` or `ios`.
  final String platform;

  /// OS version string.
  final String osVersion;

  /// Device manufacturer.
  final String manufacturer;

  /// Device model.
  final String model;
}
