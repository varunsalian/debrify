import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier;
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

/// One finished recording in the library — from the Android store/scan merge
/// or a desktop directory listing. [uri] is whatever plays it: `content://`
/// (Android Q+), `file://` (pre-Q), or a plain absolute path (desktop).
class RecordingLibraryEntry {
  /// Set when the Android recording store indexes this file (which is what
  /// carries [channelName] and [durationMs]); null for scan-only files.
  final String? taskId;
  final String uri;
  final String name;
  final String? channelName;
  final int bytes;
  final int recordedAtMs;
  final int? durationMs;

  /// True when the capture died (process kill, OS reap) and reconcile
  /// salvaged the partial file — the signal behind the hub's
  /// battery-optimization nudge. [interruptedAtMs] is WHEN it died
  /// (finalize time), so dismissing the nudge only silences interruptions
  /// that had already happened.
  final bool interrupted;
  final int? interruptedAtMs;

  const RecordingLibraryEntry({
    required this.taskId,
    required this.uri,
    required this.name,
    required this.channelName,
    required this.bytes,
    required this.recordedAtMs,
    required this.durationMs,
    this.interrupted = false,
    this.interruptedAtMs,
  });

  factory RecordingLibraryEntry.fromMap(Map<String, dynamic> map) {
    return RecordingLibraryEntry(
      taskId: map['taskId']?.toString(),
      uri: map['uri']?.toString() ?? '',
      name: map['name']?.toString() ?? 'recording.ts',
      channelName: map['channelName']?.toString(),
      bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      recordedAtMs: (map['recordedAtMs'] as num?)?.toInt() ?? 0,
      durationMs: (map['durationMs'] as num?)?.toInt(),
      interrupted: map['interrupted'] == true,
      interruptedAtMs: (map['interruptedAtMs'] as num?)?.toInt(),
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

  /// Bumped whenever THIS process mutates the schedule set (page, player
  /// sheet, manual timer, desktop scheduler firing) — UI badges listen
  /// instead of polling. Native-side mutations (an Android alarm firing
  /// while the app is backgrounded) can't bump it; listeners pair this with
  /// an on-resume refresh.
  static final ValueNotifier<int> schedulesRevision = ValueNotifier<int>(0);

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

  static const String _maxConcurrentPref = 'recording_max_concurrent';
  static const int maxConcurrentDefault = 2;

  /// Picker ceiling. Every recording is a full extra connection to the
  /// provider ON TOP of whatever is being watched, and most IPTV accounts
  /// allow 1–3 connections total — past 4 the realistic outcome is the
  /// provider kicking streams, not more recordings.
  static const int maxConcurrentCeiling = 4;

  /// Synchronous mirror of [maxConcurrent] for desktop's start path (which
  /// can't await a prefs read). Primed at desktop scheduler init, refreshed
  /// by every [maxConcurrent]/[setMaxConcurrent] call. Android never reads
  /// it — Kotlin reads the pref directly at each start.
  static int maxConcurrentCached = maxConcurrentDefault;

  /// User-set cap on simultaneous recordings (1..[maxConcurrentCeiling],
  /// default 2). Kotlin reads the same key from FlutterSharedPreferences
  /// (`flutter.recording_max_concurrent`).
  static Future<int> maxConcurrent() async {
    final prefs = await SharedPreferences.getInstance();
    final value = (prefs.getInt(_maxConcurrentPref) ?? maxConcurrentDefault)
        .clamp(1, maxConcurrentCeiling);
    maxConcurrentCached = value;
    return value;
  }

  static Future<void> setMaxConcurrent(int value) async {
    final clamped = value.clamp(1, maxConcurrentCeiling);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxConcurrentPref, clamped);
    maxConcurrentCached = clamped;
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
    if (path.endsWith('.ts') ||
        path.endsWith('.mts') ||
        path.endsWith('.m2ts')) {
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
          .map(
            (e) => LiveRecordingStatus.fromMap(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  static Future<bool> forget(String taskId) =>
      _invokeBool('forgetLiveRecording', {'taskId': taskId});

  // ── Library ───────────────────────────────────────────────────────────────

  /// Finished recordings on this device: the native store's `done` entries
  /// merged with an on-disk scan of the recordings folder (which also finds
  /// files the store no longer indexes). Android only — desktop lists its
  /// folder in [DesktopRecordingService].
  static Future<List<RecordingLibraryEntry>> queryLibrary() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'queryRecordingsLibrary',
      );
      if (raw == null) return const [];
      return raw
          .map(
            (e) => RecordingLibraryEntry.fromMap(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .where((e) => e.uri.isNotEmpty)
          .toList(growable: false);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Delete a finished recording's file AND its store entry. Refused natively
  /// (`recording_live`) while that file is still being captured.
  static Future<bool> deleteRecordingFile(String uri) =>
      _invokeBool('deleteRecordingFile', {'uri': uri});

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
      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('scheduleRecording', {
            'url': url,
            'channelName': channelName,
            'programmeTitle': programmeTitle,
            'startMs': startMs,
            'endMs': endMs,
            'headers': headers ?? <String, String>{},
            'force': force,
          });
      if (raw == null) return const RecordingCallResult(errorCode: 'no_result');
      final result = RecordingCallResult(
        id: raw['id']?.toString(),
        exact: raw['exact'] == true,
      );
      if (result.ok) schedulesRevision.value++;
      return result;
    } on PlatformException catch (e) {
      return RecordingCallResult(errorCode: e.code, errorMessage: e.message);
    } on MissingPluginException {
      return const RecordingCallResult(errorCode: 'missing_plugin');
    }
  }

  static Future<bool> cancelSchedule(String id) async {
    final ok = await _invokeBool('cancelScheduledRecording', {'id': id});
    if (ok) schedulesRevision.value++;
    return ok;
  }

  static Future<List<ScheduledRecording>> listSchedules() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'listScheduledRecordings',
      );
      if (raw == null) return const [];
      return raw
          .map(
            (e) =>
                ScheduledRecording.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList(growable: false);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Engine availability, three-state: 'supported' (Android 10+, or pre-Q
  /// with the legacy storage grant), 'needs_permission' (pre-Q, grantable),
  /// 'unsupported'. Pre-Q devices must SHOW recording affordances in the
  /// needs_permission state — the first press is how the grant happens.
  static Future<String> engineSupport() async {
    if (!Platform.isAndroid) return 'unsupported';
    try {
      return await _channel.invokeMethod<String>('engineRecordingSupport') ??
          'unsupported';
    } on PlatformException {
      return 'unsupported';
    } on MissingPluginException {
      return 'unsupported';
    }
  }

  /// Show the legacy storage permission dialog (pre-Q). Resolves true once
  /// granted (or when no grant was needed).
  static Future<bool> requestLegacyStoragePermission() =>
      _invokeBool('requestLegacyStoragePermission');

  /// Gate for every engine action: true when recording can proceed NOW —
  /// requesting the pre-Q grant on the spot if that's all that's missing.
  /// Also the app's one contextual moment to ask for the Android 13+
  /// notification grant (asked at most once, ever): recording works without
  /// it, but progress, "Saved" and "schedule skipped" go silent.
  static Future<bool> ensureEngineReady() async {
    switch (await engineSupport()) {
      case 'supported':
        // Fire-and-forget: the system dialog must never delay the capture —
        // an unanswered prompt would eat the start of the live stream.
        unawaited(ensureNotificationPermission());
        return true;
      case 'needs_permission':
        final granted = await requestLegacyStoragePermission();
        if (granted) unawaited(ensureNotificationPermission());
        return granted;
      default:
        return false;
    }
  }

  /// Ask for POST_NOTIFICATIONS if never asked before (Android 13+). True =
  /// notifications will show. Never blocks recording.
  static Future<bool> ensureNotificationPermission() =>
      _invokeBool('ensureNotificationPermission');

  /// Whether Debrify is excluded from battery optimization — the difference
  /// between hours-long recordings surviving OEM app killers or not.
  static Future<bool> isIgnoringBatteryOptimizations() =>
      _invokeBool('isIgnoringBatteryOptimizations');

  /// Show the system "let this app ignore battery optimizations?" dialog.
  static Future<bool> requestIgnoreBatteryOptimizations() =>
      _invokeBool('requestIgnoreBatteryOptimizationForApp');

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
