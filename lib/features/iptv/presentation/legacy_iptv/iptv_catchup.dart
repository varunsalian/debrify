import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:flutter/material.dart';

typedef IptvCatchupDeps = ({
  IptvCatalogState catalogState,
  IptvPlayerState playerState,
  IptvPreviewState previewState,
  IptvSelectionState selectionState,
  BuildContext Function() context,
  void Function() flushPreviewRearm,
  bool Function() isTelevision,
  bool Function() mounted,
  String? Function(IptvChannel channel) originPlaylistIdFor,
  Future<void> Function() refreshAfterPlayback,
});

class IptvCatchup {
  final IptvCatchupDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvPlayerState _playerState;
  final IptvPreviewState _previewState;
  final IptvSelectionState _selectionState;

  IptvCatchup(this._deps)
    : _catalogState = _deps.catalogState,
      _playerState = _deps.playerState,
      _previewState = _deps.previewState,
      _selectionState = _deps.selectionState;

  /// Replay an archived programme (Xtream catchup). The replay is launched
  /// as a single-item on-demand payload rather than through [_playChannel]:
  /// the timeshift URL is a finite VOD-style stream that isn't part of any
  /// channel list, and the in-player guide would otherwise point at an
  /// unrelated channel. Resume/continue-watching ride the normal VOD path —
  /// the timeshift URL is stable for a given programme, so a half-watched
  /// replay picks up where it left off.
  Future<void> playCatchup(IptvChannel channel, EpgProgramme programme) async {
    if (_playerState.launchingChannel) return;
    _playerState.launchingChannel = true;
    try {
      // Everything origin-dependent is captured BEFORE the first await: the
      // first-use dialect probe can run for tens of seconds, and the user
      // can switch playlists meanwhile — the widget stays mounted, so
      // `mounted` guards don't cover it. Recording with the switched-to
      // playlist's id would break the provider-deletion sweep (deleting B
      // would purge A's replay; deleting A would strand the entry).
      final originPlaylistId = _deps.originPlaylistIdFor(channel);
      final ticket = _catalogState.loadTicket;
      final replayFromInPlaceSchedule =
          _selectionState.scheduleChannel?.url == channel.url;
      final messenger = ScaffoldMessenger.of(_deps.context());
      messenger.showSnackBar(
        SnackBar(
          content: Text('Preparing replay of "${programme.title}"…'),
          // Covers the worst-case first-use probe (3 dialects × 10s timeout);
          // hidden explicitly the moment the probe answers.
          duration: const Duration(seconds: 30),
        ),
      );

      final url = await IptvEpgService.instance.catchupUrl(
        channel.url,
        programme,
      );
      if (!_deps.mounted()) return;
      messenger.hideCurrentSnackBar();
      // Stale: the playlist reloaded/switched, or the in-place schedule pane
      // this replay was picked from is gone — a player appearing over
      // whatever the user moved on to would read as the wrong programme
      // launching itself. Bottom-sheet replays capture false and skip this
      // guard because [_scheduleChannel] is never set in that flow.
      if (ticket != _catalogState.loadTicket) return;
      if (replayFromInPlaceSchedule &&
          _selectionState.scheduleChannel?.url != channel.url) {
        return;
      }
      if (url == null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Replay not available — the panel did not answer for '
              '"${programme.title}"',
            ),
          ),
        );
        return;
      }

      final replay = IptvChannel(
        name: programme.title,
        url: url,
        logoUrl: channel.logoUrl,
        group: channel.name, // reads as "on <channel>" in the player UI
        contentType: 'vod',
        httpHeaders: channel.httpHeaders,
      );
      await IptvHistoryStorage.recordIptvWatch(
        replay.url,
        channelName: replay.name,
        logoUrl: replay.logoUrl,
        group: replay.group,
        playlistId: originPlaylistId,
        httpHeaders: replay.httpHeaders,
      );
      if (!_deps.mounted()) return;

      await VideoPlayerLauncher.push(
        _deps.context(),
        VideoPlayerLaunchArgs(
          videoUrl: url,
          title: programme.title,
          subtitle: channel.name,
          viewMode: PlaylistViewMode.sorted,
          iptvChannels: [replay],
          iptvStartIndex: 0,
          httpHeaders: replay.playbackHeaders,
        ),
      );
      // Same parked preview re-arm discipline as _playChannelInner.
      if (_deps.mounted() &&
          (_deps.isTelevision() || _selectionState.tvTwoPaneActive)) {
        _previewState.previewRearmPending = true;
      }
      if (!_deps.isTelevision() && _deps.mounted()) {
        if (_selectionState.touchTabletTwoPaneActive) {
          _deps.flushPreviewRearm();
        } else {
          await _deps.refreshAfterPlayback();
        }
      }
    } finally {
      _playerState.launchingChannel = false;
    }
  }
}
