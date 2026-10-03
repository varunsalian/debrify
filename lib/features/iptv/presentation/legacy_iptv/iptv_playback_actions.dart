import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/iptv/xtream_series_detail.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/widgets/home/cw_card_menu.dart';
import 'package:flutter/material.dart';

typedef IptvPlaybackActionsDeps = ({
  IptvSettingsState settingsState,
  // TEMP(iptv): _clearPreview -> IptvPreviewTuning.clearPreview (step 6).
  void Function() clearPreview,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() mounted,
  String? Function(IptvChannel channel) originPlaylistIdFor,
  Future<void> Function(IptvChannel channel, {bool Function()? shouldCancel})
  playChannel,
  Future<void> Function() refreshAfterPlayback,
});

class IptvPlaybackActions {
  final IptvPlaybackActionsDeps _deps;
  final IptvSettingsState _settingsState;

  IptvPlaybackActions(this._deps) : _settingsState = _deps.settingsState;

  /// Open the merged series page for an Xtream series entry. Playback happens
  /// inside that page (episode list / Resume), so none of [_playChannelInner]'s
  /// launch bookkeeping applies here.
  Future<void> openSeriesDetail(IptvChannel channel) async {
    var playlist = _settingsState.selectedPlaylist;
    if (playlist == null) return;
    // Reached from a virtual shelf (Continue watching): the selected playlist
    // is the shelf itself, not the provider — resolve the series' real Xtream
    // provider from the origin id stored per row.
    if (!playlist.isXtreamCodes) {
      final originId = _deps.originPlaylistIdFor(channel);
      IptvPlaylist? origin;
      for (final p in _settingsState.playlists) {
        if (p.id == originId && p.isXtreamCodes) {
          origin = p;
          break;
        }
      }
      if (origin == null) {
        if (_deps.mounted()) {
          ScaffoldMessenger.of(_deps.context()).showSnackBar(
            const SnackBar(
              content: Text("This series' provider is no longer available"),
            ),
          );
        }
        return;
      }
      playlist = origin;
    }
    // Empty the stage BEFORE the route covers it: the app-resume path after
    // in-page playback flushes the parked re-arm, and a remounted backdrop
    // must not open a stream underneath the detail route. With the shown
    // channel cleared, an epoch bump remounts nothing.
    _deps.clearPreview();
    await openXtreamSeries(
      _deps.context(),
      playlist: playlist,
      series: channel,
      isTelevision: _deps.isTelevision(),
    );
    if (!_deps.mounted()) return;
    // Episodes watched inside the page entered the continue-watching shelf —
    // reflect that (and any position changes) now. The preview re-arms itself
    // on the next row focus.
    await _deps.refreshAfterPlayback();
  }

  /// Offer resume/removal for movies, series and catch-up on the CW shelf.
  Future<void> showContinueWatchingActions(IptvChannel channel) async {
    // Capture the provider before opening a dialog: series IDs are only
    // unique within their provider, and the selected shelf can change.
    final playlistId = _deps.originPlaylistIdFor(channel) ?? '';
    final seriesId = channel.attributes['series_id'] ?? '';
    final isSeries = channel.contentType == 'series';
    final action = await showCwCardMenu(
      _deps.context(),
      title: channel.name,
      posterUrl: channel.logoUrl,
      isTelevision: _deps.isTelevision(),
      playLabel: isSeries ? 'Open series' : 'Resume',
      playDescription: isSeries ? 'Choose an episode' : 'Continue playback',
      removeDescription: isSeries
          ? 'Clear saved progress for all episodes of this series.'
          : 'Clear saved progress for this item.',
    );
    if (!_deps.mounted() || action == null) return;
    if (action == CwCardAction.play) {
      await _deps.playChannel(channel);
      return;
    }
    try {
      if (isSeries) {
        if (seriesId.isEmpty) return;
        await IptvHistoryStorage.removeIptvContinueWatchingSeries(
          playlistId: playlistId,
          seriesId: seriesId,
        );
      } else {
        await IptvHistoryStorage.removeIptvContinueWatchingItem(channel.url);
      }
      if (!_deps.mounted()) return;
      await _deps.refreshAfterPlayback();
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text('Removed from Continue Watching')),
      );
    } catch (_) {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(
          content: Text('Could not remove item. Please try again.'),
        ),
      );
    }
  }
}
