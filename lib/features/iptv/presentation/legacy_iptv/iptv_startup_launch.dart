import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/startup_iptv_storage.dart';
import 'package:debrify/widgets/iptv/db_channel_list.dart';
import 'package:flutter/material.dart';

typedef IptvStartupLaunchDeps = ({
  IptvCatalogState catalogState,
  IptvFocusState focusState,
  IptvPlayerState playerState,
  IptvPreviewState previewState,
  IptvSelectionState selectionState,
  IptvSettingsState settingsState,
  BuildContext Function() context,
  ValueChanged<int>? Function() debugOnSpotlightStartupFocus,
  bool Function() mounted,
  Future<void> Function(IptvChannel channel, {bool Function()? shouldCancel})
  playChannel,
  Future<IptvChannel?> Function(
    Map<String, dynamic> payload,
    bool Function() cancelled,
  )
  resolveStartupRow,

  void Function(int index, IptvChannel channel) selectTabletChannel,
  StateSetter setState,

  bool Function() spotlightRequestedForDevice,

  bool Function() spotlightUsesTimeline,
});

class IptvStartupLaunch {
  final IptvStartupLaunchDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvFocusState _focusState;
  final IptvPlayerState _playerState;
  final IptvPreviewState _previewState;
  final IptvSelectionState _selectionState;
  final IptvSettingsState _settingsState;

  IptvStartupLaunch(this._deps)
    : _catalogState = _deps.catalogState,
      _focusState = _deps.focusState,
      _playerState = _deps.playerState,
      _previewState = _deps.previewState,
      _selectionState = _deps.selectionState,
      _settingsState = _deps.settingsState;

  bool get _spotlightRequestedForDevice => _deps.spotlightRequestedForDevice();

  bool get _spotlightUsesTimeline => _deps.spotlightUsesTimeline();

  void cancelStartupLaunch() {
    _playerState.startupAttempt++;
    if (_playerState.startupLaunchActive) {
      _playerState.startupLaunchActive = false;
      if (_deps.mounted()) _deps.setState(() {});
    }
  }

  Future<void> maybeRunStartupLaunch() async {
    final payload = MainPageBridge.consumeIptvStartupChannel();
    if (payload == null) return;
    // The bootstrap sentinel carries no url/name by design — it means "start on
    // whatever you land on" — so it must skip the stored-identity validation
    // below, which would otherwise reject it and cancel the whole attempt.
    final firstAvailable =
        payload[StartupIptvStorage.startupIptvFirstAvailable] == true;
    final url = payload['url'];
    final name = payload['name'];
    if (!firstAvailable && (url is! String || url.isEmpty || name is! String)) {
      MainPageBridge.cancelIptvStartupChannel();
      return;
    }

    final attempt = ++_playerState.startupAttempt;
    // The epoch, not just the local attempt: cancellation can land in the gap
    // between consuming the payload and registering the callback below, and
    // would then find nothing to call. The epoch records it regardless.
    final epoch = MainPageBridge.iptvStartupEpoch;
    bool cancelled() =>
        attempt != _playerState.startupAttempt ||
        epoch != MainPageBridge.iptvStartupEpoch ||
        !_deps.mounted();
    if (cancelled()) return;
    _playerState.startupLaunchActive = true;
    MainPageBridge.cancelIptvStartup = cancelStartupLaunch;
    if (_deps.mounted()) _deps.setState(() {});

    try {
      final row = await _deps.resolveStartupRow(payload, cancelled);
      if (cancelled()) return;
      if (row == null) {
        failStartupLaunch(
          firstAvailable
              ? 'No live channels to start on yet'
              : 'That channel is no longer available',
        );
        return;
      }
      await scrollAndFocusStartupRow(row);
      if (cancelled()) return;
      await _deps.playChannel(row, shouldCancel: cancelled);
    } catch (e) {
      debugPrint('IPTV startup launch failed: $e');
      if (!cancelled()) failStartupLaunch('Could not start that channel');
    } finally {
      // Do NOT drop the preview suppression just because push() returned.
      //
      // Focusing the target row above re-tuned the stage, so `_previewStreamUrl`
      // is loaded and only this flag is holding the stage off. On TV push()
      // returns while the native player is merely STARTING — clearing here
      // would remount the stage and open a second live stream underneath it,
      // which is the exact failure `_previewRearmPending` exists to prevent.
      // On the parked-re-arm paths, `_flushPreviewRearm` clears this instead.
      // Keyed on the parked re-arm itself, not on "we think we launched":
      // `_playChannelInner` can also return early WITHOUT launching (a Stremio
      // channel with no playable candidate, say), and treating that as parked
      // would strand the suppression on forever, leaving the preview stage
      // permanently dead until some unrelated playback flushed it.
      final parked = _previewState.previewRearmPending;
      if (attempt == _playerState.startupAttempt && !parked) {
        _playerState.startupLaunchActive = false;
        if (_deps.mounted()) _deps.setState(() {});
      }
      MainPageBridge.cancelIptvStartup = null;
    }
  }

  void failStartupLaunch(String reason) {
    MainPageBridge.notifyAutoLaunchFailed(reason);
    if (_deps.mounted()) {
      ScaffoldMessenger.of(
        _deps.context(),
      ).showSnackBar(SnackBar(content: Text(reason)));
    }
  }

  /// The provider a stored startup channel belongs to.
  ///
  /// Falls back to an Xtream fingerprint (`serverUrl` + `username`) captured
  /// when the channel was saved: re-adding an account mints a brand-new
  /// playlist id, so an id-only lookup would lose the channel every time a user
  /// re-entered their subscription.
  IptvPlaylist? startupPlaylistFor(Map<String, dynamic> payload) {
    final playlistId = payload['playlistId'];
    if (playlistId is String && playlistId.isNotEmpty) {
      for (final playlist in _settingsState.playlists) {
        if (playlist.id == playlistId) return playlist;
      }
    }
    final serverUrl = payload['serverUrl'];
    final username = payload['username'];
    if (serverUrl is String && serverUrl.isNotEmpty && username is String) {
      for (final playlist in _settingsState.playlists) {
        if (playlist.isXtreamCodes &&
            playlist.serverUrl == serverUrl &&
            playlist.username == username) {
          return playlist;
        }
      }
    }
    return null;
  }

  /// Scroll the target into view and focus it, so BACK out of the player lands
  /// on the channel rather than at the top of the list.
  ///
  /// There is no existing scroll-to-index to reuse: the grid's only auto-scroll
  /// is each row's own `ensureVisible`, fired once a BUILT row takes focus — and
  /// a distant lazy row is never built and has no focus node.
  Future<void> scrollAndFocusStartupRow(IptvChannel row) async {
    final index = _catalogState.filteredChannels is DbChannelList
        ? (_catalogState.filteredChannels as DbChannelList).indexOfInstance(row)
        : _catalogState.filteredChannels.indexOf(row);
    if (index == null || index < 0) return;
    // Spotlight has one logical cursor instead of per-row FocusNodes. Hand it
    // the resolved index directly so a startup target outside the first
    // viewport becomes the hero selection and the BACK landing before the
    // player opens. Retry for a few frames if layout just mounted the timeline.
    if (_spotlightRequestedForDevice && _spotlightUsesTimeline) {
      for (var attempt = 0; attempt < 5; attempt++) {
        if (_focusState.spotlightTimelineController.focusChannelAt(index)) {
          _deps.debugOnSpotlightStartupFocus()?.call(index);
          return;
        }
        await WidgetsBinding.instance.endOfFrame;
        if (!_deps.mounted()) return;
      }
    }
    // The touch-tablet two-pane renders IptvCenteredSelector, which owns its
    // OWN controller — `_scrollController` drives the grid only, so scrolling it
    // here would be a no-op. Hand the selector the index through the selection
    // it already reconciles against instead.
    if (_selectionState.touchTabletTwoPaneActive) {
      _deps.setState(() => _deps.selectTabletChannel(index, row));
      return;
    }
    if (_focusState.scrollController.hasClients) {
      final target =
          (index ~/ _selectionState.gridColumns).toDouble() *
          (_selectionState.gridRowExtent + 4);
      final position = _focusState.scrollController.position;
      if (position.hasContentDimensions) {
        _focusState.scrollController.jumpTo(
          target.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
      }
    }
    // The row has to build before it has a focus node to give focus to, and on
    // a slow TV that can take more than the next frame.
    for (var attempt = 0; attempt < 5; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!_deps.mounted()) return;
      final node = _focusState.cardFocusNodes[row];
      if (node != null) {
        node.requestFocus();
        return;
      }
    }
  }
}
