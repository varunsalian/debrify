import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yaml/yaml.dart';

/// The app's own version/build, with a safe failure mode.
///
/// `package_info_plus` has no working Apple TV implementation:
/// `package_info_plus_tvos` exists on pub.dev but requires
/// `package_info_plus_platform_interface ^4.1.0`, which no published
/// `package_info_plus` uses (10.2.1 still pins ^3.2.1), so it cannot be
/// resolved into the app at all. The tvOS runner therefore implements the
/// package's `getAll` method-channel contract directly from `Bundle.main`.
///
/// This wrapper remains the last line of defence. A missing/regressed native
/// channel or malformed platform result yields an explicit unknown value
/// instead of aborting [AppMigrationService] and the rest of app startup.
class AppVersionInfo {
  AppVersionInfo._();

  static PackageInfo? _cached;

  /// Empty [PackageInfo] used when the platform can't answer. Deliberately
  /// empty rather than fabricated: a made-up version string would be written
  /// into the migration bookkeeping as if it were real, and the next launch
  /// on a platform that CAN answer would compare against that fiction.
  static final PackageInfo _unknown = PackageInfo(
    appName: '',
    packageName: '',
    version: '',
    buildNumber: '',
  );

  /// True when the last [get] fell back — i.e. this platform cannot report
  /// its own version. Lets a caller skip work that would be meaningless.
  static bool get isUnavailable => _unavailable;
  static bool _unavailable = false;

  @visibleForTesting
  static void debugReset() {
    _cached = null;
    _unavailable = false;
  }

  /// Never throws. Cached after the first successful read; a failure is not
  /// cached, so a platform that gains an implementation later recovers
  /// without a restart.
  static Future<PackageInfo> get() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final platformInfo = await PackageInfo.fromPlatform();
      final semanticVersion = await _bundledSemanticVersion();
      final restoredVersion = restoreSanitizedAppleVersion(
        reportedVersion: platformInfo.version,
        bundledVersion: semanticVersion,
      );
      final info = restoredVersion == platformInfo.version
          ? platformInfo
          : PackageInfo(
              appName: platformInfo.appName,
              packageName: platformInfo.packageName,
              version: restoredVersion,
              buildNumber: platformInfo.buildNumber,
              buildSignature: platformInfo.buildSignature,
              installerStore: platformInfo.installerStore,
              installTime: platformInfo.installTime,
              updateTime: platformInfo.updateTime,
            );
      if (info.version.trim().isEmpty || info.buildNumber.trim().isEmpty) {
        throw const FormatException('Package info omitted version/build');
      }
      _cached = info;
      _unavailable = false;
      return info;
    } catch (e) {
      // A version lookup is never worth taking the app down for. Callers that
      // gate durable work consult [isUnavailable] and skip rather than record
      // this empty sentinel as a real version.
      _unavailable = true;
      debugPrint('AppVersionInfo: package info unavailable ($e)');
      return _unknown;
    }
  }

  static Future<String?> _bundledSemanticVersion() async {
    try {
      final pubspec = await rootBundle.loadString('pubspec.yaml');
      final document = loadYaml(pubspec);
      final version = document is YamlMap
          ? document['version']?.toString().split('+').first.trim()
          : null;
      return version == null || version.isEmpty ? null : version;
    } catch (_) {
      return null;
    }
  }

  /// Restores the prerelease label Flutter strips from iOS/macOS bundle
  /// versions, but only when the bundled source version sanitizes to exactly
  /// what the platform reported. Explicit `--build-name` overrides therefore
  /// remain authoritative.
  @visibleForTesting
  static String restoreSanitizedAppleVersion({
    required String reportedVersion,
    required String? bundledVersion,
  }) {
    final source = bundledVersion?.trim().split('+').first;
    if (source == null || source.isEmpty || source == reportedVersion) {
      return reportedVersion;
    }
    final sanitized = source.replaceAll(RegExp(r'[^\d\.]'), '');
    final segments = sanitized
        .split('.')
        .where((segment) => segment.isNotEmpty)
        .toList();
    while (segments.length < 3) {
      segments.add('0');
    }
    return segments.join('.') == reportedVersion ? source : reportedVersion;
  }
}
