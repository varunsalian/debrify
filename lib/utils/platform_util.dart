import 'dart:io';
import 'package:flutter/services.dart';

/// Utility class for platform-specific detection and helpers
class PlatformUtil {
  PlatformUtil._();

  static const MethodChannel _channel = MethodChannel('com.debrify.app/downloader');

  static bool? _isAndroidTVCached;

  /// Last-resolved TV detection, read synchronously. Defaults to false until
  /// [isAndroidTV] has run once (it's called early in app startup, so this is
  /// reliably warm by the time playback starts). For UI that can't await.
  static bool get isAndroidTvCached => _isAndroidTVCached ?? false;

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
