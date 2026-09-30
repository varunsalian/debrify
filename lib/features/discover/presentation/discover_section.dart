import 'dart:async';
import 'package:flutter/material.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/mdblist_list_choice.dart';
import '../../../widgets/see_all/discover_browsing_input.dart';
import '../../../ui/core/trailer_indicators.dart';
import '../application/discover_source_controller.dart';
import '../application/discover_layout_controller.dart';
import '../application/discover_card_settings_controller.dart';
import '../models/discover_card_settings.dart';
import '../models/discover_source_state.dart';
import 'discover_bindings.dart';
import 'discover_focus.dart';
import 'discover_preview.dart';
import 'discover_shell_bridge.dart';
import 'discover_content.dart';

typedef DiscoverSectionDeps = ({
  DiscoverBindings Function() bindings,
  bool Function() mounted,
  bool Function() discoverMode,
  bool Function() isTelevision,
  bool Function() discoveryEnabled,
  BuildContext Function() context,
  void Function(VoidCallback) setState,
  Widget Function() buildPanel,
});

/// Route-local source selection, focus and preview composition for Discover.
class DiscoverSection {
  DiscoverSection(this._deps);
  final DiscoverSectionDeps _deps;
  // Discover tab: the active source key (CW / tracker / `a:{addonId}`) + its
  // DPAD focus node (the "Source" dropdown is the leading filter of whichever
  // embedded See-All panel is shown). [discAddons] is the browsable addon list
  // appended to the Source dropdown.
  DiscoverBindings get _discoverBindings => _deps.bindings();
  DiscoverSourceController get discoverSourceController =>
      _discoverBindings.source;
  String get discSource => discoverSourceController.current.source;
  List<StremioAddon> get discAddons => discoverSourceController.current.addons;
  final discoverFocus = DiscoverFocus();
  FocusNode get discSourceNode => discoverFocus.source;

  /// An MDBList list handed off from the Search tab's Lists mode (consumed
  /// from MainPageBridge.pendingMdblistListOpen on mount). Passed into the
  /// MDBList panel, which opens focused on it with the ♥ like toggle.
  MdblistListChoice? discMdblistList;

  // The grid tile the DPAD is currently on, mirrored into the two-pane detail
  // rail (TV Discover). A ValueNotifier — not setState — so a focus move only
  // rebuilds the rail, never the grid subtree.
  ValueNotifier<StremioMeta?> get discFocused => discoverFocus.focused;
  void onDiscFocused(StremioMeta item) => discoverFocus.selectTitle(item);

  // Local preview signals are borrowed by the resolving rail and player stage.
  late final DiscoverPreview discPreview = DiscoverPreview(
    isCurrent: _deps.mounted,
  );

  DiscoverShellBridge? discoverShellBridge;

  // ── Discover layout (grid / stage) ───────────────────────────────────────

  DiscoverLayoutController get discoverLayoutController =>
      _discoverBindings.layout;
  String get discLayout => discoverLayoutController.current;

  DiscoverCardSettingsController get discoverCardSettingsController =>
      _discoverBindings.cards;
  DiscoverCardSettings get discCardSettings =>
      discoverCardSettingsController.current;

  /// Whether the STAGE layout is what this surface should render: the pref, on
  /// the Discover tab, on a TV. The canvas-size guard lives in the LayoutBuilder
  /// (a too-small canvas falls back to the flat panel, exactly like the grid's
  /// two-pane does).
  bool get discStage =>
      _deps.discoverMode() && _deps.isTelevision() && discLayout == 'stage';

  Future<void> loadDiscoverLayout() => discoverLayoutController.load(
    isCurrent: _deps.mounted,
    onChanged: () => _deps.setState(() {}),
  );

  /// Settings picker fired: tear the trailer down BEFORE the relayout, so the
  /// player is never re-parented mid-play into the other layout's tree (the
  /// Home board's rule for the same swap), then re-read the pref and rebuild.
  void onDiscoverLayoutChanged() {
    if (!_deps.mounted()) return;
    discPreview.resetPlayback();
    unawaited(loadDiscoverLayout());
  }

  void onDiscoverCardSettingsChanged() {
    if (!_deps.mounted()) return;
    if (discoverCardSettingsController.refresh(isCurrent: _deps.mounted)) {
      _deps.setState(() {});
    }
  }

  /// The Discover tab: a "Source" dropdown over a single browsable grid. Each
  /// source is rendered by the matching See-All panel in [embedded] mode (no
  /// Scaffold/back header), with the Source dropdown injected as its leading
  /// filter so DPAD walks Source → the panel's own filters → grid. All item
  /// open/play/bound wiring is this screen's existing board handlers.
  Widget buildDiscover() => DiscoverBrowsingInput(
    onActivity: discPreview.onActivity,
    child: _buildDiscoverContent(),
  );

  Widget _buildDiscoverContent() => buildDiscoverContent(
    _deps.context(),
    sourcePanel: _deps.buildPanel(),
    cardSettings: discCardSettings,
    showPreview:
        _deps.isTelevision() &&
        discSource != DiscoverSources.jellyfin &&
        discSource != DiscoverSources.emby,
    stage: discStage,
    focused: discFocused,
    preview: discPreview,
    isCurrent: _deps.mounted,
    loadingIndicator: (visible) => HomeHeroTrailerLoadingPill(visible: visible),
    ambientIndicator: (visible) => HomeHeroAmbientChip(visible: visible),
  );

  void selectDiscoverSource(String source) {
    final selected = discoverSourceController.select(
      source,
      discoveryEnabled: _deps.discoveryEnabled(),
      isCurrent: _deps.mounted,
      beforeChange: () {
        discFocused.value = null;
        discPreview.shown.value = null;
        if (source == DiscoverSources.jellyfin ||
            source == DiscoverSources.emby) {
          discPreview.resetPlayback();
        }
      },
      onChanged: () => _deps.setState(() {}),
    );
    // The embedded panel reattaches this shared node when the source changes.
    if (selected && _deps.isTelevision()) {
      discoverFocus.restoreSource(isCurrent: _deps.mounted);
    }
  }

  void startShell() {
    discoverShellBridge = DiscoverShellBridge(
      readPreview: () => discPreview,
      isTelevision: _deps.isTelevision(),
      onCardSettings: onDiscoverCardSettingsChanged,
      onLayout: onDiscoverLayoutChanged,
      loadLayout: loadDiscoverLayout,
    );
  }

  void dispose() {
    discoverFocus.dispose();
    discoverShellBridge?.dispose();
    discPreview.dispose();
  }
}
