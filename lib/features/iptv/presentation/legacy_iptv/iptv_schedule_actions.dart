import 'dart:async';
import 'dart:io' show Platform;

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/desktop_schedule_service.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/iptv/iptv_epg_panel.dart';
import 'package:debrify/widgets/iptv/spotlight/iptv_spotlight_layout.dart';
import 'package:debrify/widgets/recording_limit_dialogs.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

typedef IptvScheduleActionsDeps = ({
  IptvFocusState focusState,
  IptvRecordingState recordingState,
  IptvSelectionState selectionState,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() mounted,
  Future<void> Function(IptvChannel channel, EpgProgramme programme)
  playCatchup,
  IptvPlaylist? Function(IptvChannel channel) recordingResourceFor,
  Future<void> Function() refreshScheduledCount,
  StateSetter setState,
});

class IptvScheduleActions {
  final IptvScheduleActionsDeps _deps;
  final IptvFocusState _focusState;
  final IptvRecordingState _recordingState;
  final IptvSelectionState _selectionState;

  IptvScheduleActions(this._deps)
    : _focusState = _deps.focusState,
      _recordingState = _deps.recordingState,
      _selectionState = _deps.selectionState;

  /// The schedule action for a row, or null when the channel can't have
  /// guide data (no RIGHT-key handling, no calendar icon).
  VoidCallback? scheduleActionFor(IptvChannel channel, {bool inPlace = false}) {
    if (!IptvEpgService.isEpgCapable(channel)) return null;
    if (inPlace) {
      return () => openSchedulePane(channel);
    }
    return () => showIptvScheduleSheet(
      _deps.context(),
      channel,
      isTelevision: _deps.isTelevision(),
      onPlayProgramme: (programme) => _deps.playCatchup(channel, programme),
      onRecordProgramme: recordProgrammeActionFor(channel),
    );
  }

  void openSchedulePane(IptvChannel channel) {
    _deps.setState(() => _selectionState.scheduleChannel = channel);
  }

  void closeSchedulePane() {
    final channel = _selectionState.scheduleChannel;
    if (channel == null) return;
    _deps.setState(() => _selectionState.scheduleChannel = null);
    if (!_deps.isTelevision() &&
        _selectionState.spotlightLayoutMode ==
            IptvSpotlightLayoutMode.classic) {
      return;
    }
    // Hand focus back to the row that opened the schedule. Post-frame: the
    // grid (and the cached node's row) only exists again after this build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted()) return;
      if (_selectionState.spotlightLayoutMode !=
              IptvSpotlightLayoutMode.classic &&
          _focusState.spotlightTimelineController.restoreFocus()) {
        return;
      }
      final node = _focusState.cardFocusNodes[channel];
      if (node != null && node.canRequestFocus) node.requestFocus();
    });
  }

  /// REC handler for the page's guide surfaces (row-opened sheet, full-day
  /// pane), or null when recording is unavailable or the channel isn't
  /// schedulable — a null hides the REC tags entirely.
  void Function(EpgProgramme programme)? recordProgrammeActionFor(
    IptvChannel channel,
  ) {
    if (!_recordingState.pageCanRecord ||
        !LiveRecordingService.isSchedulableUrl(channel.url)) {
      return null;
    }
    return (programme) {
      unawaited(() async {
        final message = await scheduleProgrammeFromStage(channel, programme);
        if (message != null && _deps.mounted()) {
          ScaffoldMessenger.of(
            _deps.context(),
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      }());
    };
  }

  /// Stage schedule row → REC. Same flow the channel sheet uses: confirm
  /// dialog, platform-branched backend, honest result copy. Returns the
  /// message the stage shows (null = dismissed).
  Future<String?> scheduleProgrammeFromStage(
    IptvChannel channel,
    EpgProgramme programme,
  ) async {
    if (!LiveRecordingService.isSchedulableUrl(channel.url)) {
      return "This channel can't be scheduled — recording needs a direct TS "
          'or Xtream stream';
    }
    final recordUrl = LiveRecordingService.engineRecordableUrl(channel.url);
    if (recordUrl == null || !_deps.mounted()) return null;
    if (!kIsWeb &&
        Platform.isAndroid &&
        !await LiveRecordingService.ensureEngineReady()) {
      return 'Storage access is needed to save recordings';
    }
    if (!_deps.mounted()) return null;
    if (!await ensureRecordingCapacity(
      _deps.context(),
      startMs: programme.start.millisecondsSinceEpoch,
      endMs: programme.stop.millisecondsSinceEpoch,
      candidateUrl: recordUrl,
    )) {
      return null;
    }
    if (!_deps.mounted()) return null;
    String clock(DateTime t) => MaterialLocalizations.of(
      _deps.context(),
    ).formatTimeOfDay(TimeOfDay.fromDateTime(t));
    final airsNow =
        !programme.start.isAfter(DateTime.now()) &&
        programme.stop.isAfter(DateTime.now());
    final app = AppThemeScope.of(_deps.context());
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (dialogContext) => AlertDialog(
        backgroundColor: app.iptv.modalBg,
        title: Text(
          'Record programme',
          style: TextStyle(color: app.core.tx, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '${programme.title}\n'
          '${channel.name} · ${clock(programme.start)} – '
          '${clock(programme.stop)}'
          '${airsNow ? '\n\nAlready airing — records the rest, '
                    'from now until it ends.' : ''}',
          style: TextStyle(color: app.core.tx.withAlpha(0xB3), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Record'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_deps.mounted()) return null;
    final resource = _deps.recordingResourceFor(channel);
    final result = (!kIsWeb && Platform.isAndroid)
        ? await LiveRecordingService.schedule(
            url: recordUrl,
            channelName: channel.name,
            programmeTitle: programme.title,
            startMs: programme.start.millisecondsSinceEpoch,
            endMs: programme.stop.millisecondsSinceEpoch,
            headers: channel.playbackHeaders,
            connectionResourceId: resource?.connectionResourceId,
            resourceAuthorizationRevision: resource?.connectionResourceRevision,
          )
        : await DesktopScheduleService.instance.add(
            url: recordUrl,
            channelName: channel.name,
            programmeTitle: programme.title,
            startMs: programme.start.millisecondsSinceEpoch,
            endMs: programme.stop.millisecondsSinceEpoch,
            headers: channel.playbackHeaders,
            connectionResourceId: resource?.connectionResourceId,
            resourceAuthorizationRevision: resource?.connectionResourceRevision,
          );
    unawaited(_deps.refreshScheduledCount());
    if (result.errorCode == 'exact_alarms_required') {
      return 'Allow "Alarms & reminders" for Debrify to schedule recordings';
    }
    return result.ok
        ? (airsNow
              ? 'Recording starts in a few seconds'
              : 'Recording scheduled')
        : switch (result.errorCode) {
            'duplicate' => 'Already scheduled',
            'overlap' => 'Overlaps another scheduled recording',
            'bad_time' => 'This programme is already over',
            _ => "Couldn't schedule recording",
          };
  }
}
