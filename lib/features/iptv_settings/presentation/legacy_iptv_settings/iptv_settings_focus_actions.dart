import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;
import 'package:debrify/utils/tv_reveal.dart';
import 'package:flutter/material.dart';

import 'iptv_settings_focus_owner.dart';
import 'iptv_settings_sources_owner.dart';

typedef IptvSettingsFocusActionsDeps = ({
  bool Function() mounted,
  IptvSettingsSourcesOwner sourcesOwner,
  IptvSettingsFocusOwner focusOwner,
  List<IptvListMeta> Function() customLists,
  List<IptvPlaylist> Function() hideableSources,
});

class IptvSettingsFocusActions {
  IptvSettingsFocusActions(this._deps);
  final IptvSettingsFocusActionsDeps _deps;

  /// DOWN from a tab may select it first — the new tab's content is still
  /// under `ExcludeFocus(excluding: true)` until the rebuild, so a same-frame
  /// focus request is refused. Defer one frame — and MANUFACTURE that frame:
  /// when the tab was already selected, animateTo() early-returns (no
  /// setState, nothing schedules a frame on an idle screen) and an
  /// unscheduled post-frame callback just sits parked — the "DOWN does
  /// nothing, then the next keypress teleports focus into the form" glitch
  /// (the parked callback fired on the LATER press's frame and stole its
  /// focus move).
  void focusContentAfterTabSwitch(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_deps.mounted()) focusAndReveal(node);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// House DPAD idiom: focus a node, then scroll it into view next frame.
  /// Minimal + vertical-only via [tvRevealMinimal] — the alignment-pinning
  /// `Scrollable.ensureVisible` both over-scrolled (button focus dragged the
  /// playlists section into view) and dragged the TabBarView pager sideways
  /// (focusing the right-aligned Add button visibly switched tabs).
  void focusAndReveal(FocusNode node) {
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = node.context;
      if (ctx != null) tvRevealMinimal(ctx);
    });
    // If the node was already focused nothing above schedules a frame, and
    // the reveal would stall until some unrelated repaint — see
    // _focusContentAfterTabSwitch.
    WidgetsBinding.instance.scheduleFrame();
  }

  void ensureFocusNodes() {
    // 4 focus nodes per playlist (star + refresh + edit-EPG + delete)
    final needed = _deps.sourcesOwner.playlists.length * 4;

    while (_deps.focusOwner.playlistFocusNodes.length > needed) {
      _deps.focusOwner.playlistFocusNodes.removeLast().dispose();
    }

    while (_deps.focusOwner.playlistFocusNodes.length < needed) {
      final index = _deps.focusOwner.playlistFocusNodes.length;
      _deps.focusOwner.playlistFocusNodes.add(
        FocusNode(debugLabel: 'iptv-playlist-$index'),
      );
    }

    // 4 per custom list (rename + up + down + delete). Favorites is built in
    // and has no row of its own here.
    final listsNeeded = _deps.customLists().length * 4;
    while (_deps.focusOwner.listFocusNodes.length > listsNeeded) {
      _deps.focusOwner.listFocusNodes.removeLast().dispose();
    }
    while (_deps.focusOwner.listFocusNodes.length < listsNeeded) {
      final index = _deps.focusOwner.listFocusNodes.length;
      _deps.focusOwner.listFocusNodes.add(
        FocusNode(debugLabel: 'iptv-list-$index'),
      );
    }

    // One per source that can have hidden categories.
    final hiddenNeeded = _deps.hideableSources().length;
    while (_deps.focusOwner.hiddenFocusNodes.length > hiddenNeeded) {
      _deps.focusOwner.hiddenFocusNodes.removeLast().dispose();
    }
    while (_deps.focusOwner.hiddenFocusNodes.length < hiddenNeeded) {
      final index = _deps.focusOwner.hiddenFocusNodes.length;
      _deps.focusOwner.hiddenFocusNodes.add(
        FocusNode(debugLabel: 'iptv-hidden-$index'),
      );
    }
  }
}
