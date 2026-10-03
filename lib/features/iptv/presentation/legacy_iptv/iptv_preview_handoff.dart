import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';

typedef IptvPreviewHandoffDeps = ({
  IptvPlayerState playerState,
  IptvPreviewState previewState,
  // TEMP(iptv): _clearPreview -> IptvPreviewTuning.clearPreview (step 6).
  void Function() clearPreview,
  bool Function() mounted,
  Future<void> Function() refreshAfterPlayback,
  // TEMP(iptv): _setSpotlightSourcesExpanded -> IptvSpotlightFocus.setSpotlightSourcesExpanded (step 6).
  void Function(bool expanded) setSpotlightSourcesExpanded,
});

class IptvPreviewHandoff {
  final IptvPreviewHandoffDeps _deps;
  final IptvPlayerState _playerState;
  final IptvPreviewState _previewState;

  IptvPreviewHandoff(this._deps)
    : _playerState = _deps.playerState,
      _previewState = _deps.previewState;

  /// Complete a parked preview re-arm (see [_playChannel]).
  void flushPreviewRearm() {
    if (!_previewState.previewRearmPending || !_deps.mounted()) return;
    _previewState.previewRearmPending = false;
    // The startup launch parks its preview suppression here too — this is the
    // designated "we're actually back" hook, and the stage must not remount
    // while the player it launched is still coming up.
    _playerState.startupLaunchActive = false;
    _previewState.previewEpoch.value++;
    // This fires only after real playback, on both TV return paths (app
    // resume for the native player, next row focus for the in-app fallback) —
    // so it is also exactly when the position the player just saved should be
    // pulled back into the bars and the shelf.
    _deps.refreshAfterPlayback();
  }

  /// Sidebar enter = lights out for the preview (Home's grammar: the menu
  /// never competes with a playing stage). Dropping the shown channel unmounts
  /// the backdrop, which releases its engine synchronously; refocusing a
  /// channel row re-arms the stage.
  void onTvSidebarFocusChanged(bool focused) {
    if (focused) {
      _deps.setSpotlightSourcesExpanded(false);
      _deps.clearPreview();
    }
  }
}
