import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class AndroidNativeDownloader {
  static const MethodChannel _channel = MethodChannel(
    'com.debrify.app/downloader',
  );
  static const String updateTaskPrefix = 'update-';
  static const EventChannel _events = EventChannel(
    'com.debrify.app/downloader_events',
  );

  static Stream<Map<String, dynamic>>? _eventStream;

  static Stream<Map<String, dynamic>> get events {
    _eventStream ??= _events.receiveBroadcastStream().map(
      (e) => Map<String, dynamic>.from(e as Map),
    );
    return _eventStream!;
  }

  static Future<String?> start({
    required String url,
    String fileName = 'download',
    String subDir = 'Debrify',
    String mimeType = 'application/octet-stream',
    Map<String, String>? headers,
  }) async {
    if (!Platform.isAndroid) return null;
    // A PlatformException (e.g. foreground-service start not allowed from
    // the background on Android 12+) must surface as a failed start, not an
    // uncaught error in the download UI.
    try {
      return await _channel.invokeMethod<String>('startMediaStoreDownload', {
        'url': url,
        'fileName': fileName,
        'subDir': subDir,
        'mimeType': mimeType,
        'headers': headers ?? <String, String>{},
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<String?> startUpdate({
    required String url,
    String fileName = 'Debrify-update.apk',
    String subDir = 'Debrify/Updates',
    String mimeType = 'application/vnd.android.package-archive',
    Map<String, String>? headers,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('startMediaStoreDownload', {
        'url': url,
        'fileName': fileName,
        'subDir': subDir,
        'mimeType': mimeType,
        'headers': headers ?? <String, String>{},
        'markAsUpdate': true,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Invoke a bool-returning channel method, mapping channel-level failures
  /// (PlatformException such as fgs_not_allowed, MissingPluginException) to
  /// false instead of letting them escape into the calling UI flow.
  static Future<bool> _invokeBool(String method, [dynamic args]) async {
    try {
      return (await _channel.invokeMethod<bool>(method, args)) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> pause(String taskId) async {
    if (!Platform.isAndroid) return false;
    return _invokeBool('pause', {'taskId': taskId});
  }

  static Future<bool> resume(String taskId) async {
    if (!Platform.isAndroid) return false;
    return _invokeBool('resume', {'taskId': taskId});
  }

  static Future<bool> cancel(String taskId) async {
    if (!Platform.isAndroid) return false;
    return _invokeBool('cancel', {'taskId': taskId});
  }

  static Future<bool> openContentUri(String uri, String mimeType) async {
    if (!Platform.isAndroid) return false;
    return _invokeBool('openContentUri', {'uri': uri, 'mimeType': mimeType});
  }

  static Future<bool> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return false;
    return _invokeBool('openBatteryOptimizationSettings');
  }

  static Future<bool> requestIgnoreBatteryOptimizationsForApp() async {
    if (!Platform.isAndroid) return false;
    return _invokeBool('requestIgnoreBatteryOptimizationForApp');
  }

  static Future<bool> isTelevision() async {
    if (!Platform.isAndroid) return false;
    try {
      return (await _channel.invokeMethod<bool>('isTelevision')) ?? false;
    } catch (_) {
      return false;
    }
  }
}
