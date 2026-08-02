import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Result of a native start: either a [taskId] on success, or the reason the
/// start failed (e.g. `fgs_not_allowed` on Android 12+ background starts).
class AndroidStartResult {
  final String? taskId;
  final String? errorCode;
  final String? errorMessage;

  const AndroidStartResult({this.taskId, this.errorCode, this.errorMessage});

  bool get ok => taskId != null;
}

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

  static Future<AndroidStartResult> start({
    required String url,
    String? taskId,
    String fileName = 'download',
    String subDir = 'Debrify',
    String mimeType = 'application/octet-stream',
    Map<String, String>? headers,
    String? treeUri,
  }) async {
    if (!Platform.isAndroid) {
      return const AndroidStartResult(errorCode: 'not_android');
    }
    // A PlatformException (e.g. foreground-service start not allowed from
    // the background on Android 12+) must surface as a failed start WITH its
    // reason — swallowing it to null loses e.g. fgs_not_allowed, which the
    // orchestrator handles differently from a dead link.
    try {
      final id = await _channel.invokeMethod<String>('startMediaStoreDownload', {
        'url': url,
        if (taskId != null) 'taskId': taskId,
        'fileName': fileName,
        'subDir': subDir,
        'mimeType': mimeType,
        'headers': headers ?? <String, String>{},
        if (treeUri != null) 'treeUri': treeUri,
      });
      if (id == null) {
        return const AndroidStartResult(errorCode: 'no_task_id');
      }
      return AndroidStartResult(taskId: id);
    } on PlatformException catch (e) {
      return AndroidStartResult(errorCode: e.code, errorMessage: e.message);
    } on MissingPluginException {
      return const AndroidStartResult(errorCode: 'missing_plugin');
    }
  }

  /// Whether a finished recording can actually be published to Downloads on
  /// this device (MediaStore.Downloads is API 29+). False means recording
  /// should not be offered at all: the file could only ever land in
  /// app-private storage, where the user cannot get at it.
  static Future<bool> canPublishRecordings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canPublishRecordings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Register a recording temp file the moment libmpv starts writing it. The
  /// native side keeps the entry until the file is successfully published to
  /// Downloads, and re-attempts publication on the next app launch — so a
  /// process killed mid-recording or mid-copy still surfaces the footage.
  static Future<void> registerPendingRecording({
    required String path,
    required String fileName,
    String subDir = 'Debrify/Recordings',
    String mimeType = 'video/mp2t',
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('registerPendingRecording', {
        'path': path,
        'fileName': fileName,
        'subDir': subDir,
        'mimeType': mimeType,
      });
    } on PlatformException {
      // Best effort — recording proceeds without crash insurance.
    } on MissingPluginException {
      // Best effort.
    }
  }

  /// Copy an on-disk file into the MediaStore (Download/<subDir>) so it becomes
  /// user-visible, then delete the source. Used to publish an IPTV recording
  /// that libmpv wrote to app-private storage. Returns the content URI string
  /// on success, or null on failure.
  static Future<String?> saveLocalFile({
    required String path,
    required String fileName,
    String subDir = 'Debrify/Recordings',
    String mimeType = 'video/mp2t',
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('saveFileToMediaStore', {
        'path': path,
        'fileName': fileName,
        'subDir': subDir,
        'mimeType': mimeType,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Native truth for reconciliation: every persisted task merged with the
  /// live in-memory registry. Status is one of running/paused/failed.
  static Future<List<Map<String, dynamic>>> queryTasks() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('queryDownloadTasks');
      if (raw == null) return const [];
      return raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Purge a task from the native persistent store (after Dart has consumed
  /// its terminal state or cleaned a ghost). Does not touch the file.
  static Future<bool> forgetTask(String taskId) async {
    if (!Platform.isAndroid) return false;
    return _invokeBool('forgetDownloadTask', {'taskId': taskId});
  }

  /// Opens the system folder picker (ACTION_OPEN_DOCUMENT_TREE) and persists
  /// the grant. Returns {treeUri, displayName}, or null if the user backed out.
  static Future<Map<String, dynamic>?> pickDownloadDirectory() async {
    if (!Platform.isAndroid) return null;
    try {
      final res = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('pickDownloadDirectory');
      if (res == null) return null;
      return Map<String, dynamic>.from(res);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Releases a previously persisted folder grant (on change/reset).
  static Future<bool> releaseDownloadDirectory(String treeUri) async {
    if (!Platform.isAndroid) return false;
    return _invokeBool('releaseDownloadDirectory', {'treeUri': treeUri});
  }

  /// True when the grant for [treeUri] is still held and the folder is
  /// writable (SD card present, folder not deleted).
  static Future<bool> validateDownloadDirectory(String treeUri) async {
    if (!Platform.isAndroid) return false;
    return _invokeBool('validateDownloadDirectory', {'treeUri': treeUri});
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

  // TV-ness never changes at runtime, but this is called from a dozen screens
  // (including a MaterialApp.builder FutureBuilder) — cache so only the first
  // call pays the MethodChannel round-trip. Concurrent first calls share one
  // in-flight future instead of issuing duplicate channel calls.
  static bool? _isTelevisionCached;
  static Future<bool>? _isTelevisionInFlight;

  static Future<bool> isTelevision() {
    if (!Platform.isAndroid) return Future<bool>.value(false);
    final cached = _isTelevisionCached;
    if (cached != null) return Future<bool>.value(cached);
    return _isTelevisionInFlight ??= () async {
      try {
        final result =
            (await _channel.invokeMethod<bool>('isTelevision')) ?? false;
        _isTelevisionCached = result;
        return result;
      } catch (_) {
        _isTelevisionCached = false;
        return false;
      }
    }();
  }
}
