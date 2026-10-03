import 'dart:async';
import 'dart:io' show Platform;

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/desktop_schedule_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/widgets/recording_limit_dialogs.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

typedef IptvRecordNowDeps = ({
  IptvRecordingState recordingState,
  IptvSettingsState settingsState,
  BuildContext Function() context,
  bool Function() mounted,
  String? Function(IptvChannel channel) originPlaylistIdFor,
  StateSetter setState,
  String Function(String channelName) stageRecordingFileName,
});

class IptvRecordNow {
  final IptvRecordNowDeps _deps;
  final IptvRecordingState _recordingState;
  final IptvSettingsState _settingsState;

  IptvRecordNow(this._deps)
    : _recordingState = _deps.recordingState,
      _settingsState = _deps.settingsState;

  IptvPlaylist? recordingResourceFor(IptvChannel channel) {
    final originId = _deps.originPlaylistIdFor(channel);
    if (originId == null) return null;
    for (final playlist in _settingsState.playlists) {
      if (playlist.id == originId && playlist.connectionResourceId != null) {
        return playlist;
      }
    }
    return null;
  }

  /// Stage "Record": start a background capture of [channel] WITHOUT playing
  /// it — the engine on Android, the desktop capture elsewhere.
  Future<void> stageRecordNow(IptvChannel channel) async {
    final recordUrl = LiveRecordingService.engineRecordableUrl(channel.url);
    if (recordUrl == null) return;
    final messenger = ScaffoldMessenger.of(_deps.context());
    // Both recorders behind this button are raw HTTP byte-copiers, and this
    // is the one Record surface with NO player to probe the format. A URL
    // that carries no extension can still answer with an HLS playlist — the
    // engine then kills the capture at its first bytes, long after this code
    // has told the user it started. Ask the server first; only an
    // affirmative playlist answer blocks (see [servesPlaylist]).
    if (!LiveRecordingService.isSchedulableUrl(recordUrl)) {
      // The probe is capped at 3s but still long enough that a silent button
      // reads as broken on a remote — say what's happening.
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Checking channel…'),
          duration: Duration(seconds: 3),
        ),
      );
      final playlist = await LiveRecordingService.servesPlaylist(
        recordUrl,
        headers: channel.playbackHeaders,
      );
      if (!_deps.mounted()) return;
      if (playlist) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              "${channel.name} can't be recorded — it's an adaptive (HLS) "
              'stream. Recording works on progressive/TS channels.',
            ),
          ),
        );
        return;
      }
      messenger.hideCurrentSnackBar();
    }
    if (!_deps.mounted()) return;
    if (!kIsWeb && Platform.isAndroid) {
      if (!await LiveRecordingService.ensureEngineReady()) {
        if (!_deps.mounted()) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Storage access is needed to save recordings'),
          ),
        );
        return;
      }
      if (!_deps.mounted()) return;
      if (!await ensureRecordingCapacity(_deps.context())) return;
      if (!_deps.mounted()) return;
      final result = await LiveRecordingService.start(
        url: recordUrl,
        fileName: _deps.stageRecordingFileName(channel.name),
        channelName: channel.name,
        headers: channel.playbackHeaders,
        connectionResourceId: recordingResourceFor(
          channel,
        )?.connectionResourceId,
        resourceAuthorizationRevision: recordingResourceFor(
          channel,
        )?.connectionResourceRevision,
      );
      if (!_deps.mounted()) return;
      if (result.ok) {
        // Optimistic: the stage flips to Stop immediately; the debounced
        // query keeps it honest afterwards.
        _deps.setState(
          () => _recordingState.androidRecordingsByUrl[recordUrl] = result.id!,
        );
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.ok
                ? 'Recording ${channel.name} — stop from here or the '
                      'notification'
                : switch (result.errorCode) {
                    'recording_limit_reached' =>
                      'Recording limit reached \u2014 free a slot or raise '
                          'the limit in IPTV settings',
                    _ => "Couldn't start recording",
                  },
          ),
        ),
      );
      return;
    }
    if (!DesktopRecordingService.instance.isSupported) return;
    if (!await ensureRecordingCapacity(_deps.context())) return;
    if (!_deps.mounted()) return;
    final path = await DesktopScheduleService.buildRecordingPath(channel.name);
    if (!_deps.mounted()) return;
    // No onFinished: the revision listener already flips Stop back to Record,
    // and endings are announced app-wide by the reporter in main() — which,
    // unlike this widget, is still around when the capture outlives the page.
    final capture = await DesktopRecordingService.instance.start(
      url: recordUrl,
      path: path,
      channelName: channel.name,
      headers: channel.playbackHeaders,
      connectionResourceId: recordingResourceFor(channel)?.connectionResourceId,
      resourceAuthorizationRevision: recordingResourceFor(
        channel,
      )?.connectionResourceRevision,
    );
    if (!_deps.mounted()) return;
    if (capture != null) _deps.setState(() {}); // show Stop immediately
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          capture == null
              ? "Couldn't start recording"
              : 'Recording ${channel.name} — stop from this Record button; '
                    'runs while Debrify is open',
        ),
      ),
    );
  }
}
