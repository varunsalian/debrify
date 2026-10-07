import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_destination.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_dependencies.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_owners.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_widget.dart';
import 'package:debrify/services/iptv_source_stats.dart'
    show IptvSourceStatsLoader;
import 'package:flutter/material.dart';

class IptvSettingsTwoPaneNavigation {
  final IptvSettingsTwoPaneDependencies _deps;
  IptvSettingsTwoPaneNavigation(this._deps);
  IptvSettingsTwoPane get widget => _deps.widget();
  IptvSettingsTwoPaneOwners get _owners => _deps.owners;

  IptvTwoPaneDest initialDest() {
    if (widget.playlists.isEmpty) return const IptvTwoPaneAddDest();
    final id = widget.defaultPlaylistId;
    if (id != null && widget.playlists.any((p) => p.id == id)) {
      return IptvTwoPaneSourceDest(id);
    }
    return IptvTwoPaneSourceDest(widget.playlists.first.id);
  }

  /// Rail entries: every source, then Add, Lists, Startup, Channel preview,
  /// Continue watching, the optional Appearance (TV/desktop only), the
  /// always-present Player guide, and the optional Recording entry.
  int get _railCount =>
      widget.playlists.length +
      7 +
      (widget.showAppearanceSection ? 1 : 0) +
      (widget.showRecordingSection ? 1 : 0);

  int get channelPreviewIndex => widget.playlists.length + 3;

  int get continueWatchingIndex => widget.playlists.length + 4;

  /// Rail index of the Appearance entry — meaningful only while
  /// [IptvSettingsTwoPane.showAppearanceSection] is true.
  int get appearanceIndex => widget.playlists.length + 5;

  /// Rail index of the (always present) Player guide entry — shifts down one
  /// when Appearance is present.
  int get playerGuideIndex =>
      widget.playlists.length + 5 + (widget.showAppearanceSection ? 1 : 0);

  /// Rail index of the Recording entry — directly under Player guide.
  /// Meaningful only while showRecordingSection is true.
  int get recordingIndex => playerGuideIndex + 1;

  int get autoRefreshIndex => _railCount - 1;

  /// Grow-only, deliberately. Shrinking would dispose a node while the
  /// *previous* tree still holds a [Focus] referencing it — didUpdateWidget
  /// runs before the rebuild, so that widget's unmount would then detach a
  /// disposed node. Spare nodes cost nothing and are released in [dispose];
  /// [_focusRail] bounds itself by [_railCount], not by this length, so a
  /// spare can never be focused into.
  void syncRailNodes() {
    while (_owners.railNodes.length < _railCount) {
      _owners.railNodes.add(
        FocusNode(debugLabel: 'iptv-2p-rail-${_owners.railNodes.length}'),
      );
    }
  }

  /// Stats are read straight from the catalog DB (indexed lookups, no
  /// network). Recompute only when the source set or refresh state moves.
  void syncStats() {
    // Rebuilt from an explicit field list joined by unit/record separators,
    // so no field's contents can forge a boundary. Written as escapes on
    // purpose: raw control bytes in source make the file look binary to
    // grep, which silently skips it.
    //
    // The password is included because _editPlaylist treats ANY credential
    // change - password-only included - as cause to delete that login's
    // catalogs; omitting it left the pane quoting counts and a refresh time
    // for a catalog that no longer exists. Hashed rather than embedded: this
    // string outlives the build and needn't carry the secret.
    final signature = [
      for (final p in widget.playlists)
        [
          p.id,
          p.url,
          p.serverUrl ?? '',
          p.username ?? '',
          (p.password ?? '').hashCode,
          p.epgUrl ?? '',
        ].join('\u001f'),
      ...widget.refreshingIds,
    ].join('\u001e');
    if (signature == _owners.statsSignature) return;
    _owners.statsSignature = signature;
    _owners.sourceStats = {
      for (final p in widget.playlists) p.id: IptvSourceStatsLoader.read(p),
    };
  }

  FocusNode? paneNode(int i) =>
      i < _owners.paneNodes.length ? _owners.paneNodes[i] : null;

  void focusRailAt(int index) {
    // Bounded by the entries actually rendered, never by the (grow-only)
    // pool — a spare node is attached to nothing and would swallow focus.
    if (index < 0 || index >= _railCount || index >= _owners.railNodes.length)
      return;
    _owners.railNodes[index].requestFocus();
  }

  /// The rail index currently selected, so LEFT out of the pane returns to
  /// the entry the pane belongs to.
  int get selectedRailIndex {
    final dest = _owners.dest.value;
    return switch (dest) {
      IptvTwoPaneSourceDest(:final playlistId) => () {
        final i = widget.playlists.indexWhere((p) => p.id == playlistId);
        return i < 0 ? 0 : i;
      }(),
      IptvTwoPaneAddDest() => widget.playlists.length,
      IptvTwoPaneListsDest() => widget.playlists.length + 1,
      IptvTwoPaneStartupDest() => widget.playlists.length + 2,
      IptvTwoPaneChannelPreviewDest() => channelPreviewIndex,
      IptvTwoPaneContinueWatchingDest() => continueWatchingIndex,
      IptvTwoPaneAppearanceDest() => appearanceIndex,
      IptvTwoPanePlayerGuideDest() => playerGuideIndex,
      IptvTwoPaneRecordingDest() => recordingIndex,
      IptvTwoPaneAutoRefreshDest() => autoRefreshIndex,
    };
  }

  IptvTwoPaneDest destForRail(int index) {
    if (index == autoRefreshIndex) return const IptvTwoPaneAutoRefreshDest();
    if (index < widget.playlists.length) {
      return IptvTwoPaneSourceDest(widget.playlists[index].id);
    }
    return switch (index - widget.playlists.length) {
      0 => const IptvTwoPaneAddDest(),
      1 => const IptvTwoPaneListsDest(),
      2 => const IptvTwoPaneStartupDest(),
      3 => const IptvTwoPaneChannelPreviewDest(),
      4 => const IptvTwoPaneContinueWatchingDest(),
      5 =>
        widget.showAppearanceSection
            ? const IptvTwoPaneAppearanceDest()
            : const IptvTwoPanePlayerGuideDest(),
      6 =>
        widget.showAppearanceSection
            ? const IptvTwoPanePlayerGuideDest()
            : widget.showRecordingSection
            ? const IptvTwoPaneRecordingDest()
            : const IptvTwoPanePlayerGuideDest(),
      _ =>
        widget.showRecordingSection
            ? const IptvTwoPaneRecordingDest()
            : const IptvTwoPanePlayerGuideDest(),
    };
  }

  void enterPane() {
    // The add pane's first stop is the method chooser, which the parent owns.
    if (_owners.dest.value is IptvTwoPaneAddDest) {
      switch (widget.addMethod) {
        case 1:
          widget.fileMethodFocusNode.requestFocus();
        case 2:
          widget.xtreamMethodFocusNode.requestFocus();
        default:
          widget.urlMethodFocusNode.requestFocus();
      }
      return;
    }
    // A row with no action is not a focus stop — a dead stop is worse than no
    // stop on a remote — so the pane's FIRST node is not necessarily
    // focusable (Channel lists opens on the built-in Favorites row). Walk to
    // the first node that is actually attached and willing, or DPAD lands
    // nowhere and the pane is unreachable.
    for (final node in _owners.paneNodes) {
      if (node.context == null || !node.canRequestFocus) continue;
      node.requestFocus();
      return;
    }
  }

  void returnToRail() => focusRailAt(selectedRailIndex);
}
