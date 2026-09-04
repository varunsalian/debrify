import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

/// Utility class for platform-specific detection and helpers
class PlatformUtil {
  PlatformUtil._();

  static const MethodChannel _channel = MethodChannel('com.debrify.app/downloader');

  static bool? _isAndroidTVCached;

  /// Last-resolved TV detection, read synchronously. Defaults to false until
  /// [isAndroidTV] has run once (it's called early in app startup, so this is
  /// reliably warm by the time playback starts). For UI that can't await.
  ///
  /// ANDROID ONLY, and deliberately so — see [isTelevision] for the question
  /// most callers actually mean. [isAndroidTV] short-circuits to false when
  /// `!Platform.isAndroid`, so this is always false on Apple TV.
  static bool get isAndroidTvCached => _isAndroidTVCached ?? false;

  /// TEST-ONLY: force the cached TV verdict.
  ///
  /// The TV policies in the theme layer (grain off, grid off, shadows capped,
  /// focus floor) are all reads of this, and a test that cannot flip it can
  /// only ever verify the phone branch — which is how the details page ended
  /// up painting a full-screen rule on TV unnoticed.
  @visibleForTesting
  static void debugSetAndroidTvCached(bool? value) =>
      _isAndroidTVCached = value;

  /// Whether this build is running on Apple TV.
  ///
  /// `Platform.isIOS` is **true** on tvOS (it is the same Darwin/UIKit
  /// family), so `isIOS` alone can never distinguish an Apple TV from an
  /// iPhone — every iPhone-only branch needs `&& !isTvOS`. The operating
  /// system name is the only reliable discriminator.
  ///
  /// `static final` so the string compare happens once, not per call.
  static final bool isTvOS = Platform.operatingSystem == 'tvos';

  /// iPhone / iPad ONLY — the thing `Platform.isIOS` is usually meant to say.
  ///
  /// Use for anything that assumes a hand-held Apple device: touch gestures,
  /// device rotation, the iOS external-player URL schemes (VLC / Infuse /
  /// nPlayer handoff, which Apple TV has no working equivalent for).
  static bool get isIosMobile => Platform.isIOS && !isTvOS;

  /// A windowed desktop OS. Unlike phones and televisions, a "paused"
  /// lifecycle state here usually means the window is merely occluded or
  /// minimized while the machine keeps running on wall power.
  static bool get isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// Whether this device is a TELEVISION — Android TV **or** Apple TV.
  ///
  /// This is the right question for anything about the EXPERIENCE: 10-foot
  /// layouts, DPAD focus handling, no touch input, constrained memory. Reach
  /// for [isAndroidTvCached] only when something is specific to Android the
  /// platform (the native player handoff, Android intents, the recording
  /// engine) — those have no Apple TV counterpart and must NOT light up here.
  static bool get isTelevision => isAndroidTvCached || isTvOS;

  /// Platforms whose bundled libmpv carries the passive auto-sync analysis
  /// filters (astats/aspectralstats/ametadata), verified per build source:
  /// patched Android/macOS media_kit builds (verify scripts enforce), Linux's
  /// private full-FFmpeg libmpv (build script enforces), and the tvOS full
  /// build (filters confirmed in libavfilter.a). Windows and iPhone ship
  /// trimmed stock libs without them. Single source of truth for the install
  /// gate, the settings toggle, and the settings-search index — these must
  /// never drift apart.
  static bool get supportsSubtitleAutoSync =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isMacOS ||
          Platform.isLinux ||
          isTvOS);

  /// A hand-held phone or tablet — not a TV, a desktop or the web.
  ///
  /// The predicate for anything that only makes sense in the hand: forcing
  /// device rotation, portrait layouts, touch-only affordances. Gated on
  /// [isTelevision], not [isAndroidTvCached] — `Platform.isIOS` is true on
  /// Apple TV, so the narrower check would call a living-room box a phone.
  /// Inherits [isAndroidTvCached]'s "false until the startup probe lands"
  /// caveat — fine for UI, not for the very first frame of a cold start.
  static bool get isPhone =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      !isTelevision;

  /// Whether the most recent [isAndroidTV] probe threw instead of answering.
  /// Callers that gate MEMORY safety on TV detection (the image-cache cap)
  /// must treat "the probe failed" differently from "definitely not a TV":
  /// defaulting a 1 GB TV box to phone-sized caches because one early channel
  /// call failed is an OOM, while the reverse merely costs a phone some cache.
  static bool get lastProbeFailed => _lastProbeFailed;
  static bool _lastProbeFailed = false;

  /// Check if the current device is an Android TV
  ///
  /// Returns `true` if running on Android TV, `false` otherwise.
  /// On non-Android platforms, always returns `false`.
  ///
  /// The result is cached after first call for performance.
  static Future<bool> isAndroidTV() async {
    // Return cached value if available
    if (_isAndroidTVCached != null) {
      return _isAndroidTVCached!;
    }

    // Non-Android platforms are never TV
    if (!Platform.isAndroid) {
      _isAndroidTVCached = false;
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('isTelevision');
      _isAndroidTVCached = result ?? false;
      _lastProbeFailed = false;
      return _isAndroidTVCached!;
    } catch (e) {
      // Answer "not TV" for this call, but do NOT cache it: a transient
      // early-startup failure (engine still attaching) would otherwise stick
      // for the whole session and silently skip every TV-only accommodation.
      // The next caller re-probes.
      _lastProbeFailed = true;
      return false;
    }
  }

  /// Clear the cached TV detection result
  ///
  /// This is useful for testing or if the app needs to re-check.
  static void clearCache() {
    _isAndroidTVCached = null;
  }

  /// Check if the current platform requires focus-based navigation
  ///
  /// Returns `true` for Android TV and other TV platforms.
  /// Returns `false` for touch-based devices like phones and tablets.
  static Future<bool> requiresFocusNavigation() async {
    return await isAndroidTV();
  }

  /// Get the device name (e.g., "Sony BRAVIA VU31", "Chromecast with Google TV")
  ///
  /// On Android, tries to get the user-set device name first, then falls back
  /// to manufacturer + model. On non-Android platforms, returns null.
  static Future<String?> getDeviceName() async {
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      final result = await _channel.invokeMethod<String>('getDeviceName');
      return result;
    } catch (e) {
      return null;
    }
  }
}
