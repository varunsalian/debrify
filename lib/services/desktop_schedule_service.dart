import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_recording_service.dart';
import 'live_recording_service.dart';
import 'recording_capacity.dart' show peakOverlap;
import '../models/profiles/profile_policy.dart';
import 'profiles/device_job_store.dart';
import 'profiles/device_key_provider.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/profile_policy_guard.dart';
import 'profiles/profile_bootstrap.dart';

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
  final String ownerProfileId;
  final int profileAuthorizationRevision;
  final String? connectionResourceId;
  final int? resourceAuthorizationRevision;
  final String? sealedExecutionPayload;

  const DesktopSchedule({
    required this.id,
    required this.channelName,
    required this.url,
    required this.headers,
    required this.startMs,
    required this.endMs,
    required this.programmeTitle,
    this.ownerProfileId = 'legacy-admin-v1',
    this.profileAuthorizationRevision = 1,
    this.connectionResourceId,
    this.resourceAuthorizationRevision,
    this.sealedExecutionPayload,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'channelName': channelName,
    if (sealedExecutionPayload == null) 'url': url,
    if (sealedExecutionPayload == null) 'headers': headers,
    if (sealedExecutionPayload != null)
      'sealedExecutionPayload': sealedExecutionPayload,
    'startMs': startMs,
    'endMs': endMs,
    'programmeTitle': programmeTitle,
    'ownerProfileId': ownerProfileId,
    'profileAuthorizationRevision': profileAuthorizationRevision,
    if (connectionResourceId != null)
      'connectionResourceId': connectionResourceId,
    if (resourceAuthorizationRevision != null)
      'resourceAuthorizationRevision': resourceAuthorizationRevision,
  };

  static Future<DesktopSchedule?> fromJson(dynamic raw) async {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = map['id']?.toString();
    if (id == null || id.isEmpty) return null;
    final ownerProfileId =
        map['ownerProfileId']?.toString() ?? 'legacy-admin-v1';
    final profileAuthorizationRevision =
        (map['profileAuthorizationRevision'] as num?)?.toInt() ?? 1;
    var url = map['url']?.toString() ?? '';
    var headers = map['headers'] is Map
        ? Map<String, String>.from(
            (map['headers'] as Map).map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ),
          )
        : const <String, String>{};
    final sealed = map['sealedExecutionPayload'] as String?;
    if (sealed != null) {
      if (!DeviceKeyProvider.isUnlocked) return null;
      try {
        final clear = await DeviceKeyProvider.cipher.open(
          sealed,
          associatedData: utf8.encode(
            _executionAad(id, ownerProfileId, profileAuthorizationRevision),
          ),
        );
        final execution = jsonDecode(utf8.decode(clear));
        if (execution is! Map) return null;
        url = execution['url']?.toString() ?? '';
        headers = execution['headers'] is Map
            ? Map<String, String>.from(
                (execution['headers'] as Map).map(
                  (k, v) => MapEntry(k.toString(), v.toString()),
                ),
              )
            : const <String, String>{};
      } catch (_) {
        rethrow;
      }
    }
    if (url.isEmpty) return null;
    return DesktopSchedule(
      id: id,
      channelName: map['channelName']?.toString() ?? '',
      url: url,
      headers: headers,
      startMs: (map['startMs'] as num?)?.toInt() ?? 0,
      endMs: (map['endMs'] as num?)?.toInt() ?? 0,
      programmeTitle: map['programmeTitle']?.toString() ?? '',
      ownerProfileId: ownerProfileId,
      profileAuthorizationRevision: profileAuthorizationRevision,
      connectionResourceId: map['connectionResourceId']?.toString(),
      resourceAuthorizationRevision:
          (map['resourceAuthorizationRevision'] as num?)?.toInt(),
      sealedExecutionPayload: sealed,
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
    ownerProfileId: ownerProfileId,
    profileAuthorizationRevision: profileAuthorizationRevision,
    connectionResourceId: connectionResourceId,
    resourceAuthorizationRevision: resourceAuthorizationRevision,
  );

  static String _executionAad(
    String id,
    String ownerProfileId,
    int profileAuthorizationRevision,
  ) =>
      'debrify-desktop-schedule-v1|id=$id|owner=$ownerProfileId|revision=$profileAuthorizationRevision';
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
    await _migrateLegacySchedules();
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

  Future<List<DesktopSchedule>> list({bool allOwners = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final schedules = <DesktopSchedule>[];
      for (final item in decoded) {
        final schedule = await DesktopSchedule.fromJson(item);
        if (schedule != null) schedules.add(schedule);
      }
      if (allOwners ||
          !ProfileRuntime.isInitialized ||
          !ProfileRuntime.isProfileCommitted) {
        return schedules;
      }
      final owner = ProfileRuntime.capture().profileId;
      return schedules
          .where((schedule) => schedule.ownerProfileId == owner)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save(List<DesktopSchedule> schedules) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      _prefsKey,
      jsonEncode([for (final s in schedules) s.toJson()]),
    )) {
      throw StateError('Could not persist desktop schedules');
    }
  }

  Future<void> _migrateLegacySchedules() async {
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      return;
    }
    final scope = ProfileRuntime.capture();
    if (scope.profileId != 'legacy-admin-v1') return;
    final admin = await ProfileBootstrap.registry.getProfile(scope.profileId);
    if (admin == null || !admin.isEnabled) {
      throw StateError('Migrated Admin authority is unavailable');
    }
    final schedules = await list(allOwners: true);
    var changed = false;
    final migrated = <DesktopSchedule>[];
    for (final schedule in schedules) {
      if (schedule.sealedExecutionPayload != null) {
        migrated.add(schedule);
        continue;
      }
      final sealed = await DeviceKeyProvider.cipher.seal(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'url': schedule.url,
            'headers': schedule.headers,
          }),
        ),
        associatedData: utf8.encode(
          DesktopSchedule._executionAad(
            schedule.id,
            admin.id,
            admin.authorizationRevision,
          ),
        ),
      );
      migrated.add(
        DesktopSchedule(
          id: schedule.id,
          channelName: schedule.channelName,
          url: schedule.url,
          headers: schedule.headers,
          startMs: schedule.startMs,
          endMs: schedule.endMs,
          programmeTitle: schedule.programmeTitle,
          ownerProfileId: admin.id,
          profileAuthorizationRevision: admin.authorizationRevision,
          connectionResourceId: schedule.connectionResourceId,
          resourceAuthorizationRevision: schedule.resourceAuthorizationRevision,
          sealedExecutionPayload: sealed,
        ),
      );
      changed = true;
    }
    if (changed) await _save(migrated);
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
    String? connectionResourceId,
    int? resourceAuthorizationRevision,
  }) async {
    if (!isSupported) {
      return const RecordingCallResult(errorCode: 'not_desktop');
    }
    final authorization = await DeviceJobStore.authorize(
      ProfileFeature.recordings,
    );
    if (authorization != null &&
        !await DeviceJobStore.validateAuthorization(
          profileId: authorization.profileId,
          profileAuthorizationRevision:
              authorization.profileAuthorizationRevision,
          feature: ProfileFeature.recordings,
          resourceId: connectionResourceId,
          resourceAuthorizationRevision: resourceAuthorizationRevision,
        )) {
      return const RecordingCallResult(errorCode: 'resource_not_authorized');
    }
    final recordUrl = LiveRecordingService.engineRecordableUrl(url);
    if (recordUrl == null) {
      return const RecordingCallResult(errorCode: 'unsupported_channel');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (endMs <= now + _minRemaining.inMilliseconds || endMs <= startMs) {
      return const RecordingCallResult(errorCode: 'bad_time');
    }
    final schedules = (await list(allOwners: true)).toList();
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
    final intervals = [for (final s in schedules) (s.startMs, s.endMs)];
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
      ownerProfileId: authorization?.profileId ?? 'legacy-admin-v1',
      profileAuthorizationRevision:
          authorization?.profileAuthorizationRevision ?? 1,
      connectionResourceId: connectionResourceId,
      resourceAuthorizationRevision: resourceAuthorizationRevision,
      sealedExecutionPayload: authorization == null
          ? null
          : await DeviceKeyProvider.cipher.seal(
              utf8.encode(
                jsonEncode(<String, Object?>{
                  'url': recordUrl,
                  'headers': headers,
                }),
              ),
              associatedData: utf8.encode(
                DesktopSchedule._executionAad(
                  'dsched-$now',
                  authorization.profileId,
                  authorization.profileAuthorizationRevision,
                ),
              ),
            ),
    );
    schedules.add(schedule);
    await _save(schedules);
    await _armAll();
    LiveRecordingService.schedulesRevision.value++;
    if (authorization != null) {
      await DeviceJobStore.register(
        backend: 'desktopSchedule',
        externalJobId: schedule.id,
        kind: DeviceJobKind.schedule,
        authorization: authorization,
        resourceId: connectionResourceId,
        resourceAuthorizationRevision: resourceAuthorizationRevision,
      );
    }
    return RecordingCallResult(id: schedule.id);
  }

  Future<void> cancel(String id) async {
    final all = await list(allOwners: true);
    DesktopSchedule? target;
    for (final schedule in all) {
      if (schedule.id == id) {
        target = schedule;
        break;
      }
    }
    if (target != null &&
        ProfileRuntime.isProfileCommitted &&
        target.ownerProfileId != ProfileRuntime.capture().profileId &&
        !await ProfilePolicyGuard.allows(ProfileFeature.manageProfiles)) {
      throw StateError('Schedule belongs to another profile');
    }
    final schedules = all.where((s) => s.id != id).toList();
    await _save(schedules);
    _timers.remove(id)?.cancel();
    await DeviceJobStore.markTerminal(
      backend: 'desktopSchedule',
      externalJobId: id,
    );
    LiveRecordingService.schedulesRevision.value++;
  }

  Future<void> clearForDeviceReset() async {
    shutdown();
    final schedules = await list(allOwners: true);
    await _save(const <DesktopSchedule>[]);
    for (final schedule in schedules) {
      await DeviceJobStore.markTerminal(
        backend: 'desktopSchedule',
        externalJobId: schedule.id,
      );
    }
    LiveRecordingService.schedulesRevision.value++;
  }

  Future<void> _armAll() async {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    final now = DateTime.now().millisecondsSinceEpoch;
    final schedules = await list(allOwners: true);
    final keep = <DesktopSchedule>[];
    for (final schedule in schedules) {
      if (schedule.endMs - _minRemaining.inMilliseconds <= now) {
        await DeviceJobStore.markTerminal(
          backend: 'desktopSchedule',
          externalJobId: schedule.id,
        );
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
    for (final schedule in await list(allOwners: true)) {
      if (schedule.startMs <= now) {
        await _fire(schedule);
      }
    }
  }

  Future<void> _fire(DesktopSchedule schedule) async {
    final schedules = await list(allOwners: true);
    if (!schedules.any((s) => s.id == schedule.id)) return;
    if (!await DeviceJobStore.validateAuthorization(
      profileId: schedule.ownerProfileId,
      profileAuthorizationRevision: schedule.profileAuthorizationRevision,
      feature: ProfileFeature.recordings,
      resourceId: schedule.connectionResourceId,
      resourceAuthorizationRevision: schedule.resourceAuthorizationRevision,
      // The revision was stamped at schedule time, and saving ANY IPTV
      // source bumps every source's revision — without drift tolerance an
      // unrelated edit would silently delete every pending schedule below.
      // The live resource/grant/profile checks still refuse real revocation.
      allowRevisionDrift: true,
    )) {
      await _save(schedules.where((s) => s.id != schedule.id).toList());
      _timers.remove(schedule.id)?.cancel();
      await DeviceJobStore.markTerminal(
        backend: 'desktopSchedule',
        externalJobId: schedule.id,
      );
      return;
    }

    final now = DateTime.now();
    if (schedule.endMs - _minRemaining.inMilliseconds <=
        now.millisecondsSinceEpoch) {
      // Fully missed: nothing recordable remains.
      await _save(schedules.where((s) => s.id != schedule.id).toList());
      _timers.remove(schedule.id)?.cancel();
      await DeviceJobStore.markTerminal(
        backend: 'desktopSchedule',
        externalJobId: schedule.id,
      );
      debugPrint('DesktopSchedule: ${schedule.id} fully missed, dropping');
      return;
    }
    if (DesktopRecordingService.instance.captureForUrl(
          schedule.url,
          ownerProfileId: schedule.ownerProfileId,
        ) !=
        null) {
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
    final capture = await DesktopRecordingService.instance.start(
      url: schedule.url,
      path: path,
      channelName: schedule.channelName,
      headers: schedule.headers,
      ownerProfileId: schedule.ownerProfileId,
      profileAuthorizationRevision: schedule.profileAuthorizationRevision,
      connectionResourceId: schedule.connectionResourceId,
      resourceAuthorizationRevision: schedule.resourceAuthorizationRevision,
      onFinished: (end, bytes) {
        debugPrint('DesktopSchedule: ${schedule.id} ended ($end, $bytes B)');
      },
    );
    if (capture == null) {
      // Lost a same-instant race for the last slot (two fires straddling
      // each other's await gaps both pass the capacity check), or the
      // recorder refused. The entry was already consumed above — put it
      // back so the 30s tick retries while its window lasts, instead of
      // silently losing the recording.
      final restored = await list(allOwners: true);
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
    await DeviceJobStore.markTerminal(
      backend: 'desktopSchedule',
      externalJobId: schedule.id,
    );
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
