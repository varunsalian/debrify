import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One live/terminal engine recording, as reported by the native store.
class LiveRecordingStatus {
  final String taskId;
  final String status; // recording | done | failed
  final String url;
  final String fileName;
  final String channelName;
  final int bytes;
  final int startedAtMs;
  final String? uri;
  final String? errorMessage;

  const LiveRecordingStatus({
    required this.taskId,
    required this.status,
    required this.url,
    required this.fileName,
    required this.channelName,
    required this.bytes,
    required this.startedAtMs,
    this.uri,
    this.errorMessage,
  });

  bool get isRecording => status == 'recording';

  factory LiveRecordingStatus.fromMap(Map<String, dynamic> map) {
    return LiveRecordingStatus(
      taskId: map['taskId']?.toString() ?? '',
      status: map['status']?.toString() ?? 'failed',
      url: map['url']?.toString() ?? '',
      fileName: map['fileName']?.toString() ?? '',
      channelName: map['channelName']?.toString() ?? '',
      bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      startedAtMs: (map['startedAtMs'] as num?)?.toInt() ?? 0,
      uri: map['uri']?.toString(),
      errorMessage: map['errorMessage']?.toString(),
    );
  }
}

/// One upcoming scheduled recording.
class ScheduledRecording {
  final String id;
  final String channelName;
  final String url;
  final String programmeTitle;
  final int startMs;
  final int endMs;

  const ScheduledRecording({
    required this.id,
    required this.channelName,
    required this.url,
    required this.programmeTitle,
    required this.startMs,
    required this.endMs,
  });

  factory ScheduledRecording.fromMap(Map<String, dynamic> map) {
    return ScheduledRecording(
      id: map['id']?.toString() ?? '',
      channelName: map['channelName']?.toString() ?? '',
      url: map['url']?.toString() ?? '',
      programmeTitle: map['programmeTitle']?.toString() ?? '',
      startMs: (map['startMs'] as num?)?.toInt() ?? 0,
      endMs: (map['endMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Result of an engine start / schedule call: an id on success, otherwise the
/// native error code (`recording_limit_reached`, `duplicate`, `bad_time`,
/// `engine_unsupported`, `fgs_not_allowed`, ...).
class RecordingCallResult {
  final String? id;

  /// Schedule calls only: false when exact alarms aren't granted, so the
  /// start time may slip by up to ~10 minutes.
  final bool exact;
  final String? errorCode;
  final String? errorMessage;

  const RecordingCallResult({
    this.id,
    this.exact = true,
    this.errorCode,
    this.errorMessage,
  });

  bool get ok => id != null;
}

/// Dart face of the native recording ENGINE (LiveRecordingService): captures a
/// live stream over its own connection, independent of any player. See
/// RECORDING_ENGINE_PLAN.md. Everything here is Android-only; other platforms
/// keep the in-player libmpv tee.
class LiveRecordingService {
  static const MethodChannel _channel = MethodChannel(
    'com.debrify.app/downloader',
  );

  static const String _engineEnabledPref = 'recording_engine_enabled';

  /// Engine vs in-player tee, user-owned, default ON. Kotlin reads the same
  /// key from FlutterSharedPreferences (`flutter.recording_engine_enabled`);
  /// the native TV player snapshots it at activity launch.
  static Future<bool> engineEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_engineEnabledPref) ?? true;
  }

  static Future<void> setEngineEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_engineEnabledPref, enabled);
  }

  // ── URL classification (mirrors the Kotlin helpers; keep in sync) ─────────

  /// Segmented (adaptive) stream by URL shape — HLS/DASH/SmoothStreaming.
  /// Neither recorder can capture those byte-for-byte.
  static bool isSegmentedUrl(String url) {
    final path = url.split('?').first.split('#').first.toLowerCase();
    return path.endsWith('.m3u8') ||
        path.endsWith('.m3u') ||
        path.endsWith('.mpd') ||
        path.endsWith('.ism') ||
        path.endsWith('.isml') ||
        path.endsWith('/manifest');
  }

  static final RegExp _xtreamLiveM3u8 = RegExp(
    r'^(https?://[^/]+)/live/([^/]+)/([^/]+)/([^/.]+)\.m3u8$',
    caseSensitive: false,
  );

  /// Xtream panels serve every live channel in both containers: the `.ts`
  /// twin of `/live/user/pass/id.m3u8` is the same channel as progressive
  /// MPEG-TS — which IS engine-recordable. Strict path match only, and never
  /// for URLs carrying a query string — a twin stripped of its token would
  /// just 401.
  static String? xtreamTsTwin(String url) {
    if (url.contains('?')) return null;
    final clean = url.split('#').first;
    final m = _xtreamLiveM3u8.firstMatch(clean);
    if (m == null) return null;
    return '${m.group(1)}/live/${m.group(2)}/${m.group(3)}/${m.group(4)}.ts';
  }

  /// The URL the engine would capture for [url], or null when it can't. The
  /// engine is a plain HTTP client — rtmp/rtsp/udp/rtp/mms/srt channels (all
  /// of which M3U playlists carry) go to the tee, which records whatever mpv
  /// can play.
  static String? engineRecordableUrl(String url) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) return null;
    if (!isSegmentedUrl(url)) return url;
    return xtreamTsTwin(url);
  }

  static final RegExp _xtreamLiveAnyContainer = RegExp(
    r'^https?://[^/]+/(?:live/)?[^/]+/[^/]+/\d+(?:\.ts)?$',
    caseSensitive: false,
  );

  /// Stricter than [engineRecordableUrl]: true only for URLs AFFIRMATIVELY
  /// known to be progressive MPEG-TS. Scheduling has no player to probe — at
  /// alarm time nobody is watching — so an extensionless URL that merely
  /// *might* be progressive must not be schedulable: if it turned out to be
  /// HLS, the engine would loop-append playlist text into a .ts and report it
  /// saved. Explicit `.ts` and Xtream live URLs (whose extensionless default
  /// IS TS) qualify; everything else records via the button while watching,
  /// where the player's own format probe decides.
  static bool isSchedulableUrl(String url) {
    final recordable = engineRecordableUrl(url);
    if (recordable == null) return false;
    final path = recordable.split('?').first.split('#').first.toLowerCase();
    if (path.endsWith('.ts') || path.endsWith('.mts') || path.endsWith('.m2ts')) {
      return true;
    }
    return _xtreamLiveAnyContainer.hasMatch(path);
  }

  // ── Live captures ─────────────────────────────────────────────────────────

  static Future<RecordingCallResult> start({
    required String url,
    required String fileName,
    required String channelName,
    Map<String, String>? headers,
    int? maxDurationMs,
  }) async {
    if (!Platform.isAndroid) {
      return const RecordingCallResult(errorCode: 'not_android');
    }
    try {
      final id = await _channel.invokeMethod<String>('startLiveRecording', {
        'url': url,
        'fileName': fileName,
        'channelName': channelName,
        'headers': headers ?? <String, String>{},
        if (maxDurationMs != null) 'maxDurationMs': maxDurationMs,
      });
      if (id == null) return const RecordingCallResult(errorCode: 'no_task_id');
      return RecordingCallResult(id: id);
    } on PlatformException catch (e) {
      return RecordingCallResult(errorCode: e.code, errorMessage: e.message);
    } on MissingPluginException {
      return const RecordingCallResult(errorCode: 'missing_plugin');
    }
  }

  static Future<bool> stop(String taskId) =>
      _invokeBool('stopLiveRecording', {'taskId': taskId});

  static Future<bool> stopAll() => _invokeBool('stopAllLiveRecordings');

  /// Native truth (persisted store merged with live registry). Reconciles
  /// dead entries first, so a process death shows up as a finalized
  /// recording, never a phantom "recording".
  static Future<List<LiveRecordingStatus>> query() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'queryLiveRecordings',
      );
      if (raw == null) return const [];
      return raw
          .map((e) => LiveRecordingStatus.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  static Future<bool> forget(String taskId) =>
      _invokeBool('forgetLiveRecording', {'taskId': taskId});

  // ── Schedules ─────────────────────────────────────────────────────────────

  static Future<RecordingCallResult> schedule({
    required String url,
    required String channelName,
    required String programmeTitle,
    required int startMs,
    required int endMs,
    Map<String, String>? headers,
    bool force = false,
  }) async {
    if (!Platform.isAndroid) {
      return const RecordingCallResult(errorCode: 'not_android');
    }
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'scheduleRecording',
        {
          'url': url,
          'channelName': channelName,
          'programmeTitle': programmeTitle,
          'startMs': startMs,
          'endMs': endMs,
          'headers': headers ?? <String, String>{},
          'force': force,
        },
      );
      if (raw == null) return const RecordingCallResult(errorCode: 'no_result');
      return RecordingCallResult(
        id: raw['id']?.toString(),
        exact: raw['exact'] == true,
      );
    } on PlatformException catch (e) {
      return RecordingCallResult(errorCode: e.code, errorMessage: e.message);
    } on MissingPluginException {
      return const RecordingCallResult(errorCode: 'missing_plugin');
    }
  }

  static Future<bool> cancelSchedule(String id) =>
      _invokeBool('cancelScheduledRecording', {'id': id});

  static Future<List<ScheduledRecording>> listSchedules() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'listScheduledRecordings',
      );
      if (raw == null) return const [];
      return raw
          .map((e) => ScheduledRecording.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// True when exact alarms are available; false = scheduled starts may slip
  /// by up to ~10 minutes until the user grants the permission.
  static Future<bool> exactAlarmsGranted() => _invokeBool('exactAlarmState');

  static Future<bool> openExactAlarmSettings() =>
      _invokeBool('openExactAlarmSettings');

  static Future<bool> _invokeBool(String method, [dynamic args]) async {
    if (!Platform.isAndroid) return false;
    try {
      return (await _channel.invokeMethod<bool>(method, args)) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
