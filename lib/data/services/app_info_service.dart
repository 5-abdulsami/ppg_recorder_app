import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_info.dart';

/// Provides app version and device details for metadata files.
abstract interface class AppInfoService {
  /// Loads (and caches) app and device information. Never throws; unknown
  /// fields are reported as `unknown`.
  Future<AppInfo> load();
}

/// [AppInfoService] backed by `package_info_plus` / `device_info_plus`.
class PluginAppInfoService implements AppInfoService {
  static const String _unknown = 'unknown';
  AppInfo? _cached;

  @override
  Future<AppInfo> load() async {
    final cached = _cached;
    if (cached != null) return cached;

    var appName = _unknown, version = _unknown, build = _unknown;
    try {
      final package = await PackageInfo.fromPlatform();
      appName = package.appName;
      version = package.version;
      build = package.buildNumber;
    } catch (_) {}

    var platform = Platform.operatingSystem;
    var osVersion = Platform.operatingSystemVersion;
    var manufacturer = _unknown, model = _unknown;
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        osVersion = 'Android ${info.version.release} (SDK ${info.version.sdkInt})';
        manufacturer = info.manufacturer;
        model = info.model;
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        osVersion = '${info.systemName} ${info.systemVersion}';
        manufacturer = 'Apple';
        model = info.utsname.machine;
      }
    } catch (_) {
      platform = Platform.operatingSystem;
    }

    return _cached = AppInfo(
      appName: appName,
      version: version,
      buildNumber: build,
      platform: platform,
      osVersion: osVersion,
      manufacturer: manufacturer,
      model: model,
    );
  }
}
