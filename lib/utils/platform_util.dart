import 'dart:io';
import 'package:flutter/services.dart';

/// Utility class for platform-specific detection and helpers
class PlatformUtil {
  PlatformUtil._();

  static const MethodChannel _channel = MethodChannel('com.debrify.app/downloader');

  static bool? _isAndroidTVCached;

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
      return _isAndroidTVCached!;
    } catch (e) {
      // If the method call fails, assume not TV
      _isAndroidTVCached = false;
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
}
