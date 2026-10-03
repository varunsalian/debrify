import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_android_recording.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_composition_bindings.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_favorites.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_navigation.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_playback.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_playback_actions.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_handoff.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_layout.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_tuning.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_row_projection.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_schedule_actions.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_tablet_selection.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:flutter/material.dart';

typedef IptvPreviewAndSelectionCompositionExternalSections = ({
  IptvAndroidRecording Function() androidRecording,
  IptvFavorites Function() favorites,
  IptvNavigation Function() navigation,
  IptvPlayback Function() playback,
  IptvPlaybackActions Function() playbackActions,
  IptvPreviewHandoff Function() previewHandoff,
  IptvScheduleActions Function() scheduleActions,
});

/// Constructs the preview and selection sections for one view lifetime.
/// State owners are borrowed; cross-group getters are resolved only by actions.
class IptvPreviewAndSelectionComposition {
  final IptvViewBindings _view;
  final IptvCompositionStates _states;
  final IptvPreviewAndSelectionCompositionExternalSections _external;

  IptvPreviewAndSelectionComposition(this._view, this._states, this._external);

  late final IptvRowProjection rowProjection = IptvRowProjection((
    catalogState: _states.catalogState,
    focusState: _states.focusState,
    settingsState: _states.settingsState,
    isTelevision: () => _view.isTelevision(),
  ));

  late final IptvPreviewTuning previewTuning = IptvPreviewTuning((
    focusState: _states.focusState,
    previewState: _states.previewState,
    selectionState: _states.selectionState,
    settingsState: _states.settingsState,
    armAndroidRecStateRefresh: () =>
        _external.androidRecording().armAndroidRecStateRefresh(),
    flushPreviewRearm: () => _external.previewHandoff().flushPreviewRearm(),
    focusFirstChannel: () => _external.navigation().focusFirstChannel(),
    focusNodeFor: (IptvChannel channel) => rowProjection.focusNodeFor(channel),
    isTelevision: () => _view.isTelevision(),
    mounted: () => _view.mounted(),
    rowAttached: (IptvChannel channel) => rowProjection.rowAttached(channel),
  ));

  late final IptvPreviewLayout previewLayout = IptvPreviewLayout((
    playerState: _states.playerState,
    previewState: _states.previewState,
    settingsState: _states.settingsState,
    context: () => _view.context(),
    customLists: () => _external.favorites().customLists,
    isTelevision: () => _view.isTelevision(),
    markPreviewWinner: (int ticket) => previewTuning.markPreviewWinner(ticket),
    onPreviewPlaybackFailed: (int ticket) =>
        previewTuning.onPreviewPlaybackFailed(ticket),
    playChannel: (IptvChannel channel, {bool Function()? shouldCancel}) =>
        _external.playback().playChannel(channel, shouldCancel: shouldCancel),
    stageHoverGuard: (Widget child) => previewTuning.stageHoverGuard(child),
  ));

  late final IptvTabletSelection tabletSelection = IptvTabletSelection((
    membershipState: _states.membershipState,
    previewState: _states.previewState,
    selectionState: _states.selectionState,
    settingsState: _states.settingsState,
    customLists: () => _external.favorites().customLists,
    mounted: () => _view.mounted(),
    onChannelFocused: (IptvChannel channel, {bool fromPointer = false}) =>
        previewTuning.onChannelFocused(channel, fromPointer: fromPointer),
    openListPicker: (IptvChannel channel) =>
        _external.favorites().openListPicker(channel),
    scheduleActionFor: (IptvChannel channel, {bool inPlace = false}) =>
        _external.scheduleActions().scheduleActionFor(
          channel,
          inPlace: inPlace,
        ),
    showContinueWatchingActions: (IptvChannel channel) =>
        _external.playbackActions().showContinueWatchingActions(channel),
    showsPosterRows: () => rowProjection.showsPosterRows,
    toggleFavorite: (IptvChannel channel, bool isFavorited) =>
        _external.favorites().toggleFavorite(channel, isFavorited),
  ));
}
