import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The app's own version/build, with a platform that may not be able to answer.
///
/// `package_info_plus` has no working Apple TV implementation:
/// `package_info_plus_tvos` exists on pub.dev but requires
/// `package_info_plus_platform_interface ^4.1.0`, which no published
/// `package_info_plus` uses (10.2.1 still pins ^3.2.1), so it cannot be
/// resolved into the app at all. On tvOS the method channel is therefore
/// unimplemented and `PackageInfo.fromPlatform()` throws
/// `MissingPluginException`.
///
/// That is not a cosmetic failure. The call sat un-guarded in the middle of
/// [AppMigrationService], so the throw aborted the WHOLE migration run —
/// addon seeding, per-version migrations, the lot — on every tvOS launch.
///
/// This wrapper degrades instead: a miss yields empty strings, which every
/// caller already treats as "unknown version". Version-gated migrations then
/// simply don't advance rather than crashing, and they resume for real once
/// the plugin gains a tvOS implementation.
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

  /// Never throws. Cached after the first successful read; a failure is not
  /// cached, so a platform that gains an implementation later recovers
  /// without a restart.
  static Future<PackageInfo> get() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final info = await PackageInfo.fromPlatform();
      _cached = info;
      _unavailable = false;
      return info;
    } catch (e) {
      // MissingPluginException on tvOS; anything else is equally unusable
      // here, and a version lookup is never worth taking the app down for.
      _unavailable = true;
      debugPrint('AppVersionInfo: package info unavailable ($e)');
      return _unknown;
    }
  }
}
