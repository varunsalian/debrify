import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/stremio_iptv_service.dart';
import 'package:debrify/widgets/iptv/spotlight/iptv_spotlight_layout.dart';
import 'package:flutter/material.dart';

typedef IptvPreviewTuningDeps = ({
  IptvFocusState focusState,
  IptvPreviewState previewState,
  IptvSelectionState selectionState,
  IptvSettingsState settingsState,
  void Function() armAndroidRecStateRefresh,
  void Function() flushPreviewRearm,
  void Function() focusFirstChannel,
  FocusNode Function(IptvChannel channel) focusNodeFor,
  bool Function() isTelevision,
  bool Function() mounted,
  bool Function(IptvChannel channel) rowAttached,
});

class IptvPreviewTuning {
  final IptvPreviewTuningDeps _deps;
  final IptvFocusState _focusState;
  final IptvPreviewState _previewState;
  final IptvSelectionState _selectionState;
  final IptvSettingsState _settingsState;

  IptvPreviewTuning(this._deps)
    : _focusState = _deps.focusState,
      _previewState = _deps.previewState,
      _selectionState = _deps.selectionState,
      _settingsState = _deps.settingsState;

  /// Stage LEFT-exit: land on the exact row the stage was opened from — the
  /// row that owns the preview — so the return trip never retunes the stream.
  /// Geometric traversal would pick the nearest row instead, refocusing a
  /// DIFFERENT channel and reloading the preview twice on the way back.
  void returnFocusFromStage() {
    // Full-schedule pane open: the grid is ExcludeFocus'd, so a row focus
    // request would silently strand DPAD. The pane owns navigation (its own
    // LEFT/BACK close it); the stage's LEFT just stays put.
    if (_selectionState.scheduleChannel != null) return;
    final channel = _previewState.previewShown.value;
    if (channel != null &&
        _selectionState.spotlightLayoutMode !=
            IptvSpotlightLayoutMode.classic &&
        _focusState.spotlightTimelineController.restoreFocus()) {
      return;
    }
    if (channel != null && _deps.rowAttached(channel)) {
      _deps.focusNodeFor(channel).requestFocus();
      return;
    }
    _deps.focusFirstChannel();
  }

  /// Lets a preview stage claim the pointer, so nothing repoints it while the
  /// cursor is inside on its way to Watch or Record. A row the pointer RESTS on
  /// is exempt (see [_onChannelFocused]) — the cursor cannot be on a row and in
  /// the stage at once, so that exemption also means a flag left stuck true by
  /// a missed onExit can never strand the hover preview.
  Widget stageHoverGuard(Widget child) {
    if (_deps.isTelevision()) return child;
    return MouseRegion(
      onEnter: (_) => _previewState.pointerInStage = true,
      onExit: (_) => _previewState.pointerInStage = false,
      child: child,
    );
  }

  /// Called by a channel row gaining DPAD focus, or by a pointer resting on it
  /// ([fromPointer]) — retunes the preview stage.
  void onChannelFocused(IptvChannel channel, {bool fromPointer = false}) {
    // Focus-driven retargets (a reload refocusing the first channel, a restore
    // after a route pops) must not swap the panel out from under a cursor
    // already inside it. Only once something IS shown: the very first
    // population has to land even if the pointer happens to be parked there.
    if (!fromPointer &&
        _previewState.pointerInStage &&
        _previewState.previewShown.value != null) {
      return;
    }
    // The in-app player fallback never pauses the app, so a parked re-arm
    // wouldn't flush via the lifecycle observer — the focus restore after its
    // route pops (or the user's next move) lands here instead.
    _deps.flushPreviewRearm();
    final shown = _previewState.previewShown.value;
    if (identical(shown, channel)) return;
    _previewState.spotlightProgrammeShown.value = null;
    _previewState.previewShown.value = channel;
    if (_settingsState.channelPreviewEnabled) {
      retunePreview(channel);
    } else {
      stopPreviewPlayback();
    }
    // Keep the stage's Record↔Stop honest for whichever channel is focused
    // now (debounced — zapping through rows costs nothing).
    _deps.armAndroidRecStateRefresh();
  }

  /// Point the stage at the focused channel's stream. M3U/Xtream channels
  /// carry their URL; Stremio channels resolve theirs first (the 900ms dwell
  /// hides most of that latency) and start the candidate ladder.
  void retunePreview(IptvChannel channel) {
    _previewState.previewResolveTicket++;
    final ticket = _previewState.previewResolveTicket;
    _previewState.previewCandidates = null;
    // Series carry a sentinel URL, not a stream — the stage rests on its
    // floor (logo slab), like a channel with nothing playable.
    if (channel.contentType == 'series') {
      _previewState.previewStreamUrl.value = null;
      _previewState.previewShowing.value = false;
      return;
    }
    if (!StremioIptvService.isStremioChannelUrl(channel.url)) {
      _previewState.previewStreamUrl.value = channel.url;
      return;
    }
    // Unmounting the backdrop skips its teardown notification — reset the
    // "has frames" chip state ourselves or it would keep reading LIVE.
    _previewState.previewStreamUrl.value = null;
    _previewState.previewShowing.value = false;
    StremioIptvService.instance.resolveCandidates(channel.url).then((found) {
      if (!_deps.mounted() || ticket != _previewState.previewResolveTicket) {
        return;
      }
      // No playable streams — the stage stays on its floor, exactly like a
      // dead M3U channel.
      if (found.isEmpty) return;
      final urls = [for (final c in found) c.url];
      _previewState.previewCandidates = urls;
      _previewState.previewStreamUrl.value = urls.first;
    });
  }

  /// The stage's current stream genuinely failed (refused to open, errored, or
  /// stalled past the first-frame timeout). Stremio channels step down their
  /// candidate ladder; anything else keeps the old behavior (silent floor).
  /// [ticket] is the ladder generation the failing backdrop was built for —
  /// the notification is post-frame, so by the time it lands the focus may
  /// already be on another channel whose ladder must not be touched.
  void onPreviewPlaybackFailed(int ticket) {
    if (ticket != _previewState.previewResolveTicket) return;
    final candidates = _previewState.previewCandidates;
    final current = _previewState.previewStreamUrl.value;
    if (candidates == null || current == null) return;
    final next = candidates.indexOf(current) + 1;
    if (next <= 0) return; // stale failure for a URL we've already moved off
    if (next >= candidates.length) {
      // Every candidate is dead: drop back to the floor and forget the cached
      // list so a later attempt re-resolves fresh links.
      final shown = _previewState.previewShown.value;
      if (shown != null) StremioIptvService.instance.invalidate(shown.url);
      _previewState.previewStreamUrl.value = null;
      _previewState.previewShowing.value = false;
      return;
    }
    _previewState.previewStreamUrl.value = candidates[next];
  }

  /// First frames arrived — remember which candidate actually plays so the
  /// next preview/play of this channel starts there. Same staleness guard as
  /// the failure path: frames from a previous channel's engine must not
  /// crown the new channel's candidate.
  void markPreviewWinner(int ticket) {
    if (ticket != _previewState.previewResolveTicket) return;
    final shown = _previewState.previewShown.value;
    final current = _previewState.previewStreamUrl.value;
    if (shown == null ||
        current == null ||
        _previewState.previewCandidates == null) {
      return;
    }
    if (StremioIptvService.isStremioChannelUrl(shown.url)) {
      StremioIptvService.instance.markWinner(shown.url, current);
    }
  }

  /// Release the embedded stream and abandon any in-flight Stremio resolve,
  /// while leaving the selected channel's artwork, metadata and actions in
  /// the stage. This is the persistent-setting path.
  void stopPreviewPlayback() {
    _previewState.previewResolveTicket++;
    _previewState.previewCandidates = null;
    _previewState.previewStreamUrl.value = null;
    _previewState.previewShowing.value = false;
  }

  /// Empty the stage entirely (playlist switch, sidebar open) and abandon any
  /// in-flight resolve.
  void clearPreview() {
    stopPreviewPlayback();
    _previewState.spotlightProgrammeShown.value = null;
    _previewState.previewShown.value = null;
  }
}
