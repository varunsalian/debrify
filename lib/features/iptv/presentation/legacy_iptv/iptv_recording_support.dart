import 'dart:async';
import 'dart:io' show Platform;

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/settings/recordings_page.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/desktop_schedule_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

typedef IptvRecordingSupportDeps = ({
  IptvRecordingState recordingState,
  BuildContext Function() context,
  bool Function() mounted,
  Future<void> Function() refreshAndroidRecordingState,
  StateSetter setState,
});

class IptvRecordingSupport {
  final IptvRecordingSupportDeps _deps;
  final IptvRecordingState _recordingState;

  IptvRecordingSupport(this._deps) : _recordingState = _deps.recordingState;

  void onSchedulesChanged() {
    if (_deps.mounted()) unawaited(refreshScheduledCount());
  }

  void onDesktopRecordingChanged() {
    if (_deps.mounted()) _deps.setState(() {});
  }

  /// Every route into IPTV settings from this page is an "Add playlist"
  /// affordance — the source dropdown's entry, the filter bar's picker, the
  /// empty state's button — so open settings ON the add form rather than
  /// dropping the user at its default landing to go hunting for it.
  // ── Command Center: recording plumbing ──────────────────────────────────

  /// Recording availability for the stage. Deny-by-default: affordances only
  /// ever appear after a positive answer.
  Future<void> initRecordingSupport() async {
    var can = false;
    if (!kIsWeb && Platform.isAndroid) {
      // needs_permission counts as available — the affordances are how the
      // pre-Q storage grant gets requested in the first place.
      can =
          await LiveRecordingService.engineEnabled() &&
          (await LiveRecordingService.engineSupport()) != 'unsupported';
    } else {
      can = DesktopRecordingService.instance.isSupported;
    }
    if (!_deps.mounted()) return;
    if (can != _recordingState.pageCanRecord) {
      _deps.setState(() => _recordingState.pageCanRecord = can);
    }
    unawaited(refreshScheduledCount());
    unawaited(_deps.refreshAndroidRecordingState());
  }

  Future<void> refreshScheduledCount() async {
    var count = 0;
    if (!kIsWeb && Platform.isAndroid) {
      count = (await LiveRecordingService.listSchedules()).length;
    } else if (DesktopScheduleService.instance.isSupported) {
      count = (await DesktopScheduleService.instance.list()).length;
    }
    if (_deps.mounted() && count != _recordingState.scheduledCount) {
      _deps.setState(() => _recordingState.scheduledCount = count);
    }
  }

  void openScheduledRecordings() {
    unawaited(
      Navigator.of(_deps.context())
          .push(MaterialPageRoute<void>(builder: (_) => const RecordingsPage()))
          .then((_) {
            unawaited(refreshScheduledCount());
            // A capture stopped inside the hub must flip the stage's
            // Record button back too.
            unawaited(_deps.refreshAndroidRecordingState());
          }),
    );
  }

  /// LIVE channels with a capturable URL only. The URL-shape check alone
  /// would also pass VOD movies (direct http, non-segmented) — and "Record"
  /// on a movie is a broken duplicate of Download, spinning the engine on a
  /// static file for up to 6 hours.
  /// Any capture running right now, either backend — drives the classic
  /// header's record-dot. Android state comes from the same url→task map the
  /// stage uses (refreshed at init, on resume, and on hub/player returns);
  /// desktop reads the service directly and repaints via its revision
  /// listener.
  bool get anyRecordingLive =>
      _recordingState.androidRecordingsByUrl.isNotEmpty ||
      (DesktopRecordingService.instance.isSupported &&
          DesktopRecordingService.instance.captures.isNotEmpty);

  bool channelEngineRecordable(IptvChannel channel) =>
      channel.isLive &&
      LiveRecordingService.engineRecordableUrl(channel.url) != null;

  String stageRecordingFileName(String channelName) {
    final safeName = channelName
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    var base = safeName.isEmpty ? 'recording' : safeName;
    if (base.length > 60) base = base.substring(0, 60);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${base}_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.ts';
  }
}
