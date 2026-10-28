import 'dart:async';
import 'dart:io';

import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_dependencies.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_owners.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_sections.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/desktop_schedule_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/foundation.dart';

class RecordingsHubData {
  RecordingsHubData(this._deps);
  final RecordingsHubDependencies _deps;
  RecordingsHubOwners get _owners => _deps.owners;
  RecordingsHubSections get _sections => _deps.sections();

  static const String batteryNudgeDismissedPref =
      'recording_battery_nudge_dismissed_at';

  bool get isAndroid => !kIsWeb && Platform.isAndroid;

  bool get desktop => DesktopScheduleService.instance.isSupported;

  List<DesktopRecordingCapture> get desktopCaptures =>
      desktop ? DesktopRecordingService.instance.captures : const [];

  bool get _anythingLive =>
      _owners.live.isNotEmpty || desktopCaptures.isNotEmpty;

  bool get showBatteryNudge =>
      isAndroid &&
      !PlatformUtil.isAndroidTvCached &&
      !_owners.batteryExempt &&
      _owners.library.any(
        (e) =>
            e.interrupted &&
            (e.interruptedAtMs ?? e.recordedAtMs) >
                _owners.batteryNudgeDismissedAtMs,
      );

  void dismissBatteryNudge() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _deps.setState(() => _owners.batteryNudgeDismissedAtMs = now);
    unawaited(
      DevicePreferences.instance().then(
        (prefs) => prefs.setInt(batteryNudgeDismissedPref, now),
      ),
    );
  }

  Future<void> loadAll() async {
    final results = await Future.wait<Object>([
      isAndroid
          ? LiveRecordingService.query()
          : Future.value(const <LiveRecordingStatus>[]),
      desktop
          ? DesktopScheduleService.instance.list().then(
              (list) => list
                  .map((s) => s.toScheduledRecording())
                  .toList(growable: false),
            )
          : (isAndroid
                ? LiveRecordingService.listSchedules()
                : Future.value(const <ScheduledRecording>[])),
      isAndroid
          ? LiveRecordingService.queryLibrary()
          : DesktopRecordingService.listLibrary(),
      isAndroid
          ? LiveRecordingService.exactAlarmsGranted()
          : Future.value(true),
      isAndroid
          ? LiveRecordingService.isIgnoringBatteryOptimizations()
          : Future.value(true),
    ]);
    if (!_deps.mounted()) return;
    final live = (results[0] as List<LiveRecordingStatus>)
        .where((r) => r.isRecording)
        .toList(growable: false);
    final schedules = (results[1] as List<ScheduledRecording>).toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final library = (results[2] as List<RecordingLibraryEntry>).toList()
      ..sort(
        (a, b) => _sections.format
            .displayFor(b)
            .recordedAt
            .compareTo(_sections.format.displayFor(a).recordedAt),
      );
    _deps.setState(() {
      _owners.live = live;
      _owners.schedules = schedules;
      _owners.library = library;
      _owners.exactAlarms = results[3] as bool;
      _owners.batteryExempt = results[4] as bool;
      _owners.loading = false;
    });
    _syncTimers();
  }

  void _syncTimers() {
    if (!_owners.appVisible) return;
    final needTick = _anythingLive || _owners.schedules.isNotEmpty;
    if (needTick && _owners.ticker == null) {
      _owners.ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        _owners.now.value = DateTime.now();
      });
    } else if (!needTick && _owners.ticker != null) {
      _owners.ticker?.cancel();
      _owners.ticker = null;
    }
    // Android live poll: 3s while capturing (bytes + finalize detection),
    // 15s while merely scheduled (an alarm can fire any minute), off idle.
    // The poll is the LIGHT query — the library (whose native call walks the
    // store against the filesystem) only reloads when the live/scheduled
    // sets actually change.
    _owners.poll?.cancel();
    _owners.poll = null;
    if (isAndroid &&
        (_owners.live.isNotEmpty || _owners.schedules.isNotEmpty)) {
      _owners.poll = Timer.periodic(
        Duration(seconds: _owners.live.isNotEmpty ? 3 : 15),
        (_) => unawaited(_pollLive()),
      );
    }
  }

  /// The poll body: refresh live captures + schedules only. A membership
  /// change (a capture started or finished, a schedule fired) escalates to a
  /// full [_loadAll] so the library picks up the new file too.
  Future<void> _pollLive() async {
    if (!isAndroid) return;
    final results = await Future.wait<Object>([
      LiveRecordingService.query(),
      LiveRecordingService.listSchedules(),
    ]);
    if (!_deps.mounted()) return;
    final live = (results[0] as List<LiveRecordingStatus>)
        .where((r) => r.isRecording)
        .toList(growable: false);
    final schedules = (results[1] as List<ScheduledRecording>).toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final sameSets =
        live.map((r) => r.taskId).toSet().length == _owners.live.length &&
        _owners.live.every((old) => live.any((r) => r.taskId == old.taskId)) &&
        schedules.length == _owners.schedules.length &&
        _owners.schedules.every((old) => schedules.any((s) => s.id == old.id));
    if (!sameSets) {
      await loadAll();
      return;
    }
    // Same membership: bytes/elapsed only — no timer re-arm (the cadence is
    // a function of membership, which didn't change).
    _deps.setState(() {
      _owners.live = live;
      _owners.schedules = schedules;
    });
  }
}
