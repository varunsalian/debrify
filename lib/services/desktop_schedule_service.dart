import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_recording_service.dart';
import 'live_recording_service.dart';
import 'recording_capacity.dart' show peakOverlap;

/// One desktop schedule. Same shape as the Android native store's entries,
/// plus headers (which desktop must persist itself — there is no native side
/// to snapshot them).
class DesktopSchedule {
  final String id;
  final String channelName;
  final String url;
  final Map<String, String> headers;
  final int startMs;
  final int endMs;
  final String programmeTitle;

  const DesktopSchedule({
    required this.id,
    required this.channelName,
    required this.url,
    required this.headers,
    required this.startMs,
    required this.endMs,
    required this.programmeTitle,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'channelName': channelName,
        'url': url,
        'headers': headers,
        'startMs': startMs,
        'endMs': endMs,
        'programmeTitle': programmeTitle,
      };

  static DesktopSchedule? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = map['id']?.toString();
    final url = map['url']?.toString();
    if (id == null || id.isEmpty || url == null || url.isEmpty) return null;
    return DesktopSchedule(
      id: id,
      channelName: map['channelName']?.toString() ?? '',
      url: url,
      headers: map['headers'] is Map
          ? Map<String, String>.from(
              (map['headers'] as Map)
                  .map((k, v) => MapEntry(k.toString(), v.toString())),
            )
          : const {},
      startMs: (map['startMs'] as num?)?.toInt() ?? 0,
      endMs: (map['endMs'] as num?)?.toInt() ?? 0,
      programmeTitle: map['programmeTitle']?.toString() ?? '',
    );
  }

  /// The management page renders [ScheduledRecording]s; desktop entries wear
  /// the same face so the page needs no per-platform rows.
  ScheduledRecording toScheduledRecording() => ScheduledRecording(
        id: id,
        channelName: channelName,
        url: url,
        programmeTitle: programmeTitle,
        startMs: startMs,
        endMs: endMs,
      );
}

/// Tier-1 desktop scheduling: recordings fire WHILE DEBRIFY IS RUNNING (and
/// the machine is awake) — desktop has no AlarmManager, so a closed app
/// records nothing, and that is stated in the UI rather than papered over.
///
/// Mechanics mirror the Android alarm layer where they can:
///  - one exact [Timer] per schedule for on-time starts;
///  - a coarse safety tick (30s) that fires anything the timers missed —
///    Dart timers run on a monotonic clock, so a sleep/wake cycle can leave
///    them aiming at the wrong wall-clock moment; the tick compares wall
///    clock and late-joins exactly like Android's registerAll does;
///  - fired-is-fired: the entry is deleted before the capture starts;
///  - schedules whose window has fully passed are dropped at (re)arm time.
///
/// Captures go through [DesktopRecordingService] (the raw HTTP copier), so a
/// scheduled capture is stoppable from the player's Record button when that
/// channel is playing, and auto-ends at its scheduled end (no pad: desktop
/// schedules are all manual timers — when the user says 5 minutes they mean
/// 5 minutes; the +2min EPG-overrun pad is an Android/EPG concern).
class DesktopScheduleService {
  DesktopScheduleService._();
  static final DesktopScheduleService instance = DesktopScheduleService._();

  static const _prefsKey = 'desktop_recording_schedules_v1';

  /// Don't bother starting with less than this left (mirrors Android).
  static const _minRemaining = Duration(seconds: 60);

  final Map<String, Timer> _timers = {};
  Timer? _tick;
  bool _initialized = false;

  bool get isSupported => DesktopRecordingService.instance.isSupported;

  /// Arm everything at app start. Safe to call repeatedly.
  Future<void> init() async {
    if (!isSupported || _initialized) return;
    _initialized = true;
    // Primes LiveRecordingService.maxConcurrentCached for the recording
    // service's synchronous start path.
    await LiveRecordingService.maxConcurrent();
    await _armAll();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      // Wall-clock safety net for sleep/wake drift.
      unawaited(_fireDue());
    });
  }

  /// Stop the tick and every armed timer (tests / teardown). init() re-arms.
  void shutdown() {
    _tick?.cancel();
    _tick = null;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _initialized = false;
  }

  Future<List<DesktopSchedule>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(DesktopSchedule.fromJson)
          .whereType<DesktopSchedule>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save(List<DesktopSchedule> schedules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode([for (final s in schedules) s.toJson()]),
    );
  }

  /// Returns the new schedule id, or an error code mirroring the Android
  /// channel ('duplicate', 'bad_time', 'unsupported_channel').
  Future<RecordingCallResult> add({
    required String url,
    required String channelName,
    required String programmeTitle,
    required int startMs,
    required int endMs,
    required Map<String, String> headers,
  }) async {
    if (!isSupported) {
      return const RecordingCallResult(errorCode: 'not_desktop');
    }
    final recordUrl = LiveRecordingService.engineRecordableUrl(url);
    if (recordUrl == null) {
      return const RecordingCallResult(errorCode: 'unsupported_channel');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (endMs <= now + _minRemaining.inMilliseconds || endMs <= startMs) {
      return const RecordingCallResult(errorCode: 'bad_time');
    }
    final schedules = (await list()).toList();
    if (schedules.any((s) => s.url == recordUrl && s.startMs == startMs)) {
      return const RecordingCallResult(errorCode: 'duplicate');
    }
    // Capacity, not mere overlap: with the user-set limit L, a new schedule
    // is rejected only when some moment of its window would need more than L
    // simultaneous captures — a promise fire time couldn't keep. Reject at
    // creation, when the user can still resolve it, instead of silently
    // losing a recording later. (The UI pre-checks with the same math and a
    // richer dialog; this is the backstop.)
    final limit = await LiveRecordingService.maxConcurrent();
    final intervals = [
      for (final s in schedules) (s.startMs, s.endMs),
    ];
    if (peakOverlap(intervals, startMs, endMs) + 1 > limit) {
      return const RecordingCallResult(errorCode: 'overlap');
    }
    final schedule = DesktopSchedule(
      id: 'dsched-$now',
      channelName: channelName,
      url: recordUrl,
      headers: headers,
      startMs: startMs,
      endMs: endMs,
      programmeTitle: programmeTitle,
    );
    schedules.add(schedule);
    await _save(schedules);
    await _armAll();
    LiveRecordingService.schedulesRevision.value++;
    return RecordingCallResult(id: schedule.id);
  }

  Future<void> cancel(String id) async {
    final schedules = (await list()).where((s) => s.id != id).toList();
    await _save(schedules);
    _timers.remove(id)?.cancel();
    LiveRecordingService.schedulesRevision.value++;
  }

  Future<void> _armAll() async {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    final now = DateTime.now().millisecondsSinceEpoch;
    final schedules = await list();
    final keep = <DesktopSchedule>[];
    for (final schedule in schedules) {
      if (schedule.endMs - _minRemaining.inMilliseconds <= now) {
        continue; // fully missed — drop
      }
      keep.add(schedule);
      final delay = schedule.startMs - now;
      if (delay <= 0) {
        unawaited(_fire(schedule));
      } else {
        _timers[schedule.id] = Timer(
          Duration(milliseconds: delay),
          () => unawaited(_fire(schedule)),
        );
      }
    }
    if (keep.length != schedules.length) await _save(keep);
  }

  /// Fire anything whose wall-clock start has arrived (safety tick).
  Future<void> _fireDue() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final schedule in await list()) {
      if (schedule.startMs <= now) {
        await _fire(schedule);
      }
    }
  }

  Future<void> _fire(DesktopSchedule schedule) async {
    final schedules = await list();
    if (!schedules.any((s) => s.id == schedule.id)) return;

    final now = DateTime.now();
    if (schedule.endMs - _minRemaining.inMilliseconds <=
        now.millisecondsSinceEpoch) {
      // Fully missed: nothing recordable remains.
      await _save(schedules.where((s) => s.id != schedule.id).toList());
      _timers.remove(schedule.id)?.cancel();
      debugPrint('DesktopSchedule: ${schedule.id} fully missed, dropping');
      return;
    }
    if (DesktopRecordingService.instance.captureForUrl(schedule.url) != null) {
      // This channel is ALREADY being captured — a manual record-now, or the
      // previous back-to-back programme still flushing its file. Consuming
      // the entry now would glue it to that other capture: start() answers
      // with the existing capture (success-shaped), this schedule records
      // nothing, and its auto-stop timer would end a recording it doesn't
      // own. KEEP the entry — the 30s tick re-fires it the moment the
      // capture ends, recording the remainder of the window.
      debugPrint(
        'DesktopSchedule: ${schedule.id} deferred — channel already recording',
      );
      return;
    }
    if (DesktopRecordingService.instance.activeCount >=
        await LiveRecordingService.maxConcurrent()) {
      // At capacity — running captures win, but the schedule is KEPT, not
      // consumed: the 30s tick re-fires it, so when a slot frees up the
      // remainder of the programme still gets recorded. It only truly dies
      // if capacity stays full past the whole window, at which point the
      // missed-check above cleans it up.
      debugPrint(
        'DesktopSchedule: ${schedule.id} deferred — recording limit reached',
      );
      return;
    }
    // Fired-is-fired from here: remove before starting, so a timer + tick
    // double-fire finds nothing the second time.
    await _save(schedules.where((s) => s.id != schedule.id).toList());
    _timers.remove(schedule.id)?.cancel();
    LiveRecordingService.schedulesRevision.value++;
    final path = await _targetPath(
      schedule.programmeTitle.isNotEmpty
          ? schedule.programmeTitle
          : schedule.channelName,
    );
    final remaining = Duration(
      milliseconds: schedule.endMs - now.millisecondsSinceEpoch,
    );
    debugPrint(
      'DesktopSchedule: starting ${schedule.channelName} for '
      '${remaining.inMinutes} min → $path',
    );
    final capture = DesktopRecordingService.instance.start(
      url: schedule.url,
      path: path,
      channelName: schedule.channelName,
      headers: schedule.headers,
      onFinished: (end, bytes) =>
          debugPrint('DesktopSchedule: ${schedule.id} ended ($end, $bytes B)'),
    );
    if (capture == null) {
      // Lost a same-instant race for the last slot (two fires straddling
      // each other's await gaps both pass the capacity check), or the
      // recorder refused. The entry was already consumed above — put it
      // back so the 30s tick retries while its window lasts, instead of
      // silently losing the recording.
      final restored = await list();
      if (!restored.any((s) => s.id == schedule.id)) {
        await _save([...restored, schedule]);
        // The consume above already bumped the revision — bump again so the
        // UI's schedule rows come back instead of lying "gone" while the
        // tick quietly retries.
        LiveRecordingService.schedulesRevision.value++;
      }
      debugPrint('DesktopSchedule: ${schedule.id} could not start — re-queued');
      return;
    }
    // Auto-stop at the scheduled end. The capture's own 6h cap remains the
    // backstop; this timer is the scheduled end, taken literally (no pad).
    Timer(remaining, () {
      if (capture.isActive) unawaited(capture.stop());
    });
  }

  /// `Downloads/Debrify/Recordings/<name>_<stamp>.ts` with the same
  /// collision-avoidance as the player's recorder. Public: the IPTV page's
  /// stage Record button builds desktop capture paths through this too.
  static Future<String> buildRecordingPath(String name) =>
      instance._targetPath(name);

  Future<String> _targetPath(String name) async {
    final safeName = name
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    var base = safeName.isEmpty ? 'recording' : safeName;
    if (base.length > 60) base = base.substring(0, 60);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final dir = await DesktopRecordingService.recordingsDir();
    final sep = Platform.pathSeparator;
    final prefix = '${dir.path}$sep${base}_$stamp';
    var candidate = '$prefix.ts';
    for (var n = 2; n < 100 && await File(candidate).exists(); n++) {
      candidate = '${prefix}_$n.ts';
    }
    return candidate;
  }
}
