import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_auto_refresh_dialog.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_destination.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_method_card.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_pane_parts.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_rail_entry.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_two_pane_row.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/settings/iptv_style_page.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/iptv_source_stats.dart';
import 'package:debrify/services/storage/iptv_appearance_storage.dart';
import 'package:debrify/services/storage/startup_iptv_storage.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

export 'package:debrify/features/iptv_settings_two_pane/presentation/iptv_auto_refresh_dialog.dart'
    show
        IptvAutoRefreshDialog,
        iptvAutoRefreshExplanation,
        iptvAutoRefreshLabel;

/// Two-pane IPTV settings for TV and desktop ("Concept A"): a rail of the
/// user's actual sources on the left, the selected source's detail on the
/// right, with Add / Lists / Startup / Channel preview as rail destinations
/// below them.
///
/// Why this shape — the single-column page it replaces put the *rarest*
/// action (adding a playlist) at the top in a fixed 410px block, buried
/// Startup at the bottom of a long scroll, and gave every playlist row FOUR
/// DPAD stops (star, refresh, edit, delete) in a horizontal strip. Three
/// playlists cost twelve stops to walk past. Here a source is one stop and
/// its actions live in the pane.
///
/// DPAD model, hand-wired to match [SettingsTvLayout] so the two pages feel
/// like one app:
///   • Rail: Up/Down move between entries AND update the pane live, so
///     focusing a source previews it. Right / OK enter the pane.
///   • Pane: Up/Down move between rows. Left returns to the *selected* rail
///     entry, never a different one.
///
/// Presentation and focus only — every action still lives in the parent
/// State, handed in as callbacks.
class IptvSettingsTwoPane extends StatefulWidget {
  const IptvSettingsTwoPane({
    super.key,
    required this.playlists,
    required this.defaultPlaylistId,
    required this.refreshingIds,
    this.autoRefreshHours = 24,
    this.onPickAutoRefresh,
    required this.customLists,
    required this.startupEnabled,
    required this.startupMode,
    required this.startupChannelLabel,
    required this.lastLiveChannelLabel,
    required this.hasStartupChannel,
    required this.hasLastLiveChannel,
    required this.addMethod,
    required this.onAddMethodChanged,
    required this.urlFormBuilder,
    required this.fileFormBuilder,
    required this.xtreamFormBuilder,
    required this.urlMethodFocusNode,
    required this.fileMethodFocusNode,
    required this.xtreamMethodFocusNode,
    required this.onSetDefault,
    required this.onRefresh,
    required this.onEdit,
    required this.onDelete,
    required this.onCreateList,
    required this.onManageChannelOrder,
    this.onManageCategoryOrder,
    this.onManageHidden,
    this.hiddenCounts = const {},
    required this.onFocusFirstFormField,
    required this.onListActions,
    required this.onToggleStartup,
    required this.onStartupModeChanged,
    required this.onPickStartupChannel,
    required this.channelPreviewEnabled,
    required this.onToggleChannelPreview,
    required this.trackContinueWatching,
    required this.onToggleTrackContinueWatching,
    this.showAppearanceSection = false,
    this.iptvStyle = IptvAppearanceStorage.kIptvStyleDefault,
    this.onIptvStyleChanged,
    this.playerGuideStyle = 'classic',
    this.onPlayerGuideStyleChanged,
    this.showRecordingSection = false,
    this.showEngineToggle = true,
    this.recordingEngineEnabled = true,
    this.scheduledCount = 0,
    this.onToggleRecordingEngine,
    this.onOpenScheduledRecordings,
    this.maxConcurrentRecordings = 2,
    this.onPickMaxConcurrent,
    this.batteryExempt,
    this.onRequestBatteryExemption,
    this.openAddSource = false,
  });

  /// The page was opened by an "Add playlist" affordance (the IPTV page's
  /// source dropdown, its empty state), not by a plain visit to settings — so
  /// open ON the Add pane instead of the source the page normally lands on.
  final bool openAddSource;

  final List<IptvPlaylist> playlists;
  final String? defaultPlaylistId;
  final Set<String> refreshingIds;
  final int autoRefreshHours;
  final VoidCallback? onPickAutoRefresh;
  final List<IptvListMeta> customLists;

  final bool startupEnabled;
  final String startupMode;
  final String startupChannelLabel;
  final String lastLiveChannelLabel;
  final bool hasStartupChannel;
  final bool hasLastLiveChannel;

  /// The Recording rail entry + pane exist where SOME recorder can run:
  /// Android 10+ (engine + toggle) or desktop (in-app scheduler only). On
  /// iOS/pre-Q the rail ends at Continue watching and nothing promises
  /// recording that cannot run.
  final bool showRecordingSection;

  /// Android only — the engine-vs-tee choice is meaningless on desktop, whose
  /// single recorder has no alternative to toggle to.
  final bool showEngineToggle;
  final bool recordingEngineEnabled;
  final int scheduledCount;
  final ValueChanged<bool>? onToggleRecordingEngine;
  final VoidCallback? onOpenScheduledRecordings;

  /// Simultaneous-recordings limit shown on (and picked from) the Recording
  /// pane; the host page owns persistence.
  final int maxConcurrentRecordings;
  final VoidCallback? onPickMaxConcurrent;

  /// Null hides the row (non-Android / TV); otherwise current exemption
  /// state, label-driving.
  final bool? batteryExempt;
  final VoidCallback? onRequestBatteryExemption;

  /// 0 = from URL, 1 = from file, 2 = Xtream login. Owned by the parent so the
  /// existing TabController (and the phone layout) stay in sync with it.
  final int addMethod;
  final ValueChanged<int> onAddMethodChanged;

  /// The three existing add forms, reused verbatim. They are already
  /// focus-wired against the method nodes below, so handing those in keeps
  /// every onUpArrow/onDownArrow target valid in this layout too.
  final WidgetBuilder urlFormBuilder;
  final WidgetBuilder fileFormBuilder;
  final WidgetBuilder xtreamFormBuilder;
  final FocusNode urlMethodFocusNode;
  final FocusNode fileMethodFocusNode;
  final FocusNode xtreamMethodFocusNode;

  final ValueChanged<IptvPlaylist> onSetDefault;
  final ValueChanged<IptvPlaylist> onRefresh;
  final ValueChanged<IptvPlaylist> onEdit;
  final ValueChanged<IptvPlaylist> onDelete;
  final VoidCallback onCreateList;
  final VoidCallback onManageChannelOrder;

  /// Opens a source's category-list reorder screen. Imported files use their
  /// stable saved-playlist id while remote sources use catalog identity.
  final ValueChanged<IptvPlaylist>? onManageCategoryOrder;

  /// Opens a source's hidden-categories manager. Null on sources that store
  /// no catalog (imported files), which is also what keeps the row off them.
  final ValueChanged<IptvPlaylist>? onManageHidden;

  /// Hidden-category count per playlist id — the row's subtitle. Owned by the
  /// host page, which re-reads it when the manager closes.
  final Map<String, int> hiddenCounts;

  /// DOWN off the method chooser lands on the current form's first field.
  /// Hand-wired rather than left to geometric traversal, which is exactly
  /// the kind of thing that misbehaves on real TV hardware.
  final VoidCallback onFocusFirstFormField;

  /// OK on a list opens rename/move/delete as a sheet — one stop per list
  /// instead of the four-icon strip.
  final ValueChanged<IptvListMeta> onListActions;

  final ValueChanged<bool> onToggleStartup;
  final ValueChanged<String> onStartupModeChanged;
  final VoidCallback onPickStartupChannel;

  final bool channelPreviewEnabled;
  final ValueChanged<bool> onToggleChannelPreview;

  final bool trackContinueWatching;
  final ValueChanged<bool> onToggleTrackContinueWatching;

  /// The Appearance rail entry + pane exist only where the IPTV cockpit does
  /// (television and desktop) — a phone or touch tablet would be picking a look
  /// it can never see.
  final bool showAppearanceSection;

  /// In-player guide look (`iptv_player_guide_style`). ALWAYS present in the
  /// rail — every platform has a player, unlike the cockpit Appearance.
  final String playerGuideStyle;
  final ValueChanged<String>? onPlayerGuideStyleChanged;

  /// Current `iptv_style` value ('command' / 'edition' / 'console' /
  /// 'spotlight'). Owned by the host page, which persists BEFORE reflecting the
  /// change back here.
  final String iptvStyle;
  final ValueChanged<String>? onIptvStyleChanged;

  @override
  State<IptvSettingsTwoPane> createState() => IptvSettingsTwoPaneState();
}

class IptvSettingsTwoPaneState extends State<IptvSettingsTwoPane> {
  /// Rows in the busiest pane (a source: refresh, default, edit, guide,
  /// delete) plus headroom for the lists pane, which grows with the user's
  /// lists and is capped by the pool below.
  static const int _panePoolSize = 24;

  /// The active theme, cached by [build] for every `_buildX` helper. Assigned
  /// before first use because `build` always runs before them.
  late AppTheme _app;

  final ValueNotifier<IptvTwoPaneDest> _dest = ValueNotifier(
    const IptvTwoPaneAddDest(),
  );

  /// One node per rail entry, rebuilt when the entry count changes.
  final List<FocusNode> _railNodes = [];
  final List<FocusNode> _paneNodes = List.generate(
    _panePoolSize,
    (i) => FocusNode(debugLabel: 'iptv-2p-pane-$i'),
  );

  final ScrollController _railScroll = ScrollController();

  /// Cached per-source stats, keyed by playlist id. Recomputed only when the
  /// playlist set or a refresh changes — a DPAD move must not re-query on a
  /// weak TV box.
  Map<String, IptvSourceStats> _stats = const {};
  String _statsSignature = '';

  @override
  void initState() {
    super.initState();
    _syncRailNodes();
    _syncStats();
    // Land on the default source (or the first one) rather than on "Add" —
    // the common visit is to manage what you already have. Unless the caller
    // came here to add: then "Add" is the whole point of the trip. Deliberately
    // only the OPENING landing — the later re-homing below (a deleted source
    // leaving the pane pointing at a ghost) still goes through _initialDest.
    _dest.value = widget.openAddSource
        ? const IptvTwoPaneAddDest()
        : _initialDest();
  }

  @override
  void didUpdateWidget(covariant IptvSettingsTwoPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRailNodes();
    _syncStats();
    // A deleted source must not leave the pane pointing at a ghost.
    final dest = _dest.value;
    if (dest is IptvTwoPaneSourceDest &&
        !widget.playlists.any((p) => p.id == dest.playlistId)) {
      _dest.value = _initialDest();
    }
  }

  @override
  void dispose() {
    for (final node in _railNodes) {
      node.dispose();
    }
    for (final node in _paneNodes) {
      node.dispose();
    }
    _railScroll.dispose();
    _dest.dispose();
    super.dispose();
  }

  IptvTwoPaneDest _initialDest() {
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

  int get _channelPreviewIndex => widget.playlists.length + 3;

  int get _continueWatchingIndex => widget.playlists.length + 4;

  /// Rail index of the Appearance entry — meaningful only while
  /// [IptvSettingsTwoPane.showAppearanceSection] is true.
  int get _appearanceIndex => widget.playlists.length + 5;

  /// Rail index of the (always present) Player guide entry — shifts down one
  /// when Appearance is present.
  int get _playerGuideIndex =>
      widget.playlists.length + 5 + (widget.showAppearanceSection ? 1 : 0);

  /// Rail index of the Recording entry — directly under Player guide.
  /// Meaningful only while showRecordingSection is true.
  int get _recordingIndex => _playerGuideIndex + 1;
  int get _autoRefreshIndex => _railCount - 1;

  /// Grow-only, deliberately. Shrinking would dispose a node while the
  /// *previous* tree still holds a [Focus] referencing it — didUpdateWidget
  /// runs before the rebuild, so that widget's unmount would then detach a
  /// disposed node. Spare nodes cost nothing and are released in [dispose];
  /// [_focusRail] bounds itself by [_railCount], not by this length, so a
  /// spare can never be focused into.
  void _syncRailNodes() {
    while (_railNodes.length < _railCount) {
      _railNodes.add(
        FocusNode(debugLabel: 'iptv-2p-rail-${_railNodes.length}'),
      );
    }
  }

  /// Stats are read straight from the catalog DB (indexed lookups, no
  /// network). Recompute only when the source set or refresh state moves.
  void _syncStats() {
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
    if (signature == _statsSignature) return;
    _statsSignature = signature;
    _stats = {
      for (final p in widget.playlists) p.id: IptvSourceStatsLoader.read(p),
    };
  }

  FocusNode? _paneNode(int i) => i < _paneNodes.length ? _paneNodes[i] : null;

  void _focusRail(int index) {
    // Bounded by the entries actually rendered, never by the (grow-only)
    // pool — a spare node is attached to nothing and would swallow focus.
    if (index < 0 || index >= _railCount || index >= _railNodes.length) return;
    _railNodes[index].requestFocus();
  }

  /// Entry point for the page's back button: hand DPAD to the rail entry the
  /// pane currently belongs to, never blindly to the first one.
  void focusRail() => _focusRail(_selectedRailIndex);

  /// TV entry point for an "Add playlist" deep-link: skip the rail entirely and
  /// put DPAD straight on the add method chooser, the way OK on the rail's
  /// "Add a source" entry would. LEFT out of the pane still returns to that
  /// entry, so the rail is one keypress away.
  void focusAddPane() {
    final alreadyThere = _dest.value is IptvTwoPaneAddDest;
    _dest.value = const IptvTwoPaneAddDest();
    if (alreadyThere) {
      _enterPane();
      return;
    }
    // The pane is still showing something else this frame, so the method
    // chooser's node is attached to nothing — and requesting focus on an
    // unattached node silently strands DPAD. Wait for the switch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _enterPane();
    });
  }

  /// The rail index currently selected, so LEFT out of the pane returns to
  /// the entry the pane belongs to.
  int get _selectedRailIndex {
    final dest = _dest.value;
    return switch (dest) {
      IptvTwoPaneSourceDest(:final playlistId) => () {
        final i = widget.playlists.indexWhere((p) => p.id == playlistId);
        return i < 0 ? 0 : i;
      }(),
      IptvTwoPaneAddDest() => widget.playlists.length,
      IptvTwoPaneListsDest() => widget.playlists.length + 1,
      IptvTwoPaneStartupDest() => widget.playlists.length + 2,
      IptvTwoPaneChannelPreviewDest() => _channelPreviewIndex,
      IptvTwoPaneContinueWatchingDest() => _continueWatchingIndex,
      IptvTwoPaneAppearanceDest() => _appearanceIndex,
      IptvTwoPanePlayerGuideDest() => _playerGuideIndex,
      IptvTwoPaneRecordingDest() => _recordingIndex,
      IptvTwoPaneAutoRefreshDest() => _autoRefreshIndex,
    };
  }

  IptvTwoPaneDest _destForRail(int index) {
    if (index == _autoRefreshIndex) return const IptvTwoPaneAutoRefreshDest();
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

  void _enterPane() {
    // The add pane's first stop is the method chooser, which the parent owns.
    if (_dest.value is IptvTwoPaneAddDest) {
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
    for (final node in _paneNodes) {
      if (node.context == null || !node.canRequestFocus) continue;
      node.requestFocus();
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ONE lookup per build, cached for every _buildX helper below: the pane is
    // rebuilt from a ValueListenableBuilder on each rail focus move, so a
    // per-helper lookup would walk the inherited tree on every DPAD step.
    _app = AppThemeScope.of(context);
    final t = _app.settings;
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildRail(),
          Container(width: 1, color: t.line),
          Expanded(
            child: ValueListenableBuilder<IptvTwoPaneDest>(
              valueListenable: _dest,
              builder: (context, dest, _) => _buildPane(dest),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- rail

  Widget _buildRail() {
    final t = _app.settings;
    final width = MediaQuery.sizeOf(context).width;
    return SizedBox(
      width: width >= 1400 ? 400 : 330,
      child: ValueListenableBuilder<IptvTwoPaneDest>(
        valueListenable: _dest,
        builder: (context, dest, _) {
          final selected = _selectedRailIndex;
          return ListView(
            controller: _railScroll,
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
            children: [
              const IptvTwoPaneRailHeading('Sources'),
              for (var i = 0; i < widget.playlists.length; i++)
                IptvTwoPaneRailEntry(
                  focusNode: _railNodes[i],
                  icon: _iconFor(widget.playlists[i]),
                  title: widget.playlists[i].name,
                  subtitle: _railSubtitle(widget.playlists[i]),
                  selected: selected == i,
                  trailing: widget.defaultPlaylistId == widget.playlists[i].id
                      ? Icon(Icons.star_rounded, size: 18, color: t.warning)
                      : null,
                  busy: widget.refreshingIds.contains(widget.playlists[i].id),
                  onFocused: () => _dest.value = _destForRail(i),
                  onSelect: _enterPane,
                  onUp: i == 0 ? null : () => _focusRail(i - 1),
                  onDown: () => _focusRail(i + 1),
                  onRight: _enterPane,
                ),
              if (widget.playlists.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                  child: Text(
                    'No sources yet.',
                    style: TextStyle(fontSize: 13, color: t.dim),
                  ),
                ),
              IptvTwoPaneRailEntry(
                focusNode: _railNodes[widget.playlists.length],
                icon: Icons.add_rounded,
                title: 'Add a source',
                subtitle: 'URL, file, or Xtream login',
                selected: selected == widget.playlists.length,
                onFocused: () => _dest.value = const IptvTwoPaneAddDest(),
                onSelect: _enterPane,
                onUp: widget.playlists.isEmpty
                    ? null
                    : () => _focusRail(widget.playlists.length - 1),
                onDown: () => _focusRail(widget.playlists.length + 1),
                onRight: _enterPane,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 10,
                ),
                child: Container(height: 1, color: t.line),
              ),
              IptvTwoPaneRailEntry(
                focusNode: _railNodes[widget.playlists.length + 1],
                icon: Icons.bookmark_rounded,
                title: 'Channel lists',
                subtitle: _listsSubtitle,
                selected: selected == widget.playlists.length + 1,
                chevron: true,
                onFocused: () => _dest.value = const IptvTwoPaneListsDest(),
                onSelect: _enterPane,
                onUp: () => _focusRail(widget.playlists.length),
                onDown: () => _focusRail(widget.playlists.length + 2),
                onRight: _enterPane,
              ),
              IptvTwoPaneRailEntry(
                focusNode: _railNodes[widget.playlists.length + 2],
                icon: Icons.play_circle_outline_rounded,
                title: 'Startup channel',
                subtitle: widget.startupEnabled
                    ? (widget.startupMode ==
                              StartupIptvStorage.startupIptvModePinned
                          ? 'On · a specific channel'
                          : 'On · last watched')
                    : 'Off',
                selected: selected == widget.playlists.length + 2,
                chevron: true,
                onFocused: () => _dest.value = const IptvTwoPaneStartupDest(),
                onSelect: _enterPane,
                onUp: () => _focusRail(widget.playlists.length + 1),
                onDown: () => _focusRail(widget.playlists.length + 3),
                onRight: _enterPane,
              ),
              IptvTwoPaneRailEntry(
                focusNode: _railNodes[_channelPreviewIndex],
                icon: Icons.ondemand_video_rounded,
                title: 'Channel preview',
                subtitle: widget.channelPreviewEnabled
                    ? 'On · uses a stream while browsing'
                    : 'Off · fullscreen playback only',
                selected: selected == _channelPreviewIndex,
                chevron: true,
                onFocused: () =>
                    _dest.value = const IptvTwoPaneChannelPreviewDest(),
                onSelect: _enterPane,
                onUp: () => _focusRail(widget.playlists.length + 2),
                onDown: () => _focusRail(_continueWatchingIndex),
                onRight: _enterPane,
              ),
              IptvTwoPaneRailEntry(
                focusNode: _railNodes[_continueWatchingIndex],
                icon: Icons.history_toggle_off_rounded,
                title: 'Continue watching',
                subtitle: widget.trackContinueWatching
                    ? 'Tracking movies and series'
                    : 'Off',
                selected: selected == _continueWatchingIndex,
                chevron: true,
                onFocused: () =>
                    _dest.value = const IptvTwoPaneContinueWatchingDest(),
                onSelect: _enterPane,
                onUp: () => _focusRail(_channelPreviewIndex),
                onDown: () => _focusRail(
                  widget.showAppearanceSection
                      ? _appearanceIndex
                      : _playerGuideIndex,
                ),
                onRight: _enterPane,
              ),
              if (widget.showAppearanceSection)
                IptvTwoPaneRailEntry(
                  focusNode: _railNodes[_appearanceIndex],
                  icon: Icons.style_rounded,
                  title: 'Appearance',
                  subtitle: iptvStyleLabel(widget.iptvStyle),
                  selected: selected == _appearanceIndex,
                  chevron: true,
                  onFocused: () =>
                      _dest.value = const IptvTwoPaneAppearanceDest(),
                  onSelect: _enterPane,
                  onUp: () => _focusRail(_continueWatchingIndex),
                  onDown: () => _focusRail(_playerGuideIndex),
                  onRight: _enterPane,
                ),
              IptvTwoPaneRailEntry(
                focusNode: _railNodes[_playerGuideIndex],
                icon: Icons.smart_display_rounded,
                title: 'Player guide',
                subtitle: switch (widget.playerGuideStyle) {
                  'glass' => 'Cinema Glass',
                  'edition' => 'Midnight Edition',
                  'console' => 'Master Control',
                  _ => 'Classic',
                },
                selected: selected == _playerGuideIndex,
                chevron: true,
                onFocused: () =>
                    _dest.value = const IptvTwoPanePlayerGuideDest(),
                onSelect: _enterPane,
                onUp: () => _focusRail(
                  widget.showAppearanceSection
                      ? _appearanceIndex
                      : _continueWatchingIndex,
                ),
                onDown: widget.showRecordingSection
                    ? () => _focusRail(_recordingIndex)
                    : () => _focusRail(_autoRefreshIndex),
                onRight: _enterPane,
              ),
              if (widget.showRecordingSection)
                IptvTwoPaneRailEntry(
                  focusNode: _railNodes[_recordingIndex],
                  icon: Icons.fiber_manual_record_rounded,
                  title: 'Recording',
                  subtitle: !widget.showEngineToggle
                      ? (widget.scheduledCount == 0
                            ? 'Recordings'
                            : '${widget.scheduledCount} scheduled')
                      : widget.recordingEngineEnabled
                      ? (widget.scheduledCount == 0
                            ? 'Engine on'
                            : 'Engine on · ${widget.scheduledCount} scheduled')
                      : 'Player-tied',
                  selected: selected == _recordingIndex,
                  chevron: true,
                  onFocused: () =>
                      _dest.value = const IptvTwoPaneRecordingDest(),
                  onSelect: _enterPane,
                  onUp: () => _focusRail(_playerGuideIndex),
                  onDown: () => _focusRail(_autoRefreshIndex),
                  onRight: _enterPane,
                ),
              IptvTwoPaneRailEntry(
                focusNode: _railNodes[_autoRefreshIndex],
                icon: Icons.update_rounded,
                title: 'Auto-refresh',
                subtitle: iptvAutoRefreshLabel(widget.autoRefreshHours),
                selected: selected == _autoRefreshIndex,
                chevron: true,
                onFocused: () =>
                    _dest.value = const IptvTwoPaneAutoRefreshDest(),
                onSelect: _enterPane,
                onUp: () => _focusRail(
                  widget.showRecordingSection
                      ? _recordingIndex
                      : _playerGuideIndex,
                ),
                onDown: null,
                onRight: _enterPane,
              ),
            ],
          );
        },
      ),
    );
  }

  String get _listsSubtitle {
    final n = widget.customLists.length;
    if (n == 0) return 'Favorites only';
    return 'Favorites + $n list${n == 1 ? '' : 's'}';
  }

  IconData _iconFor(IptvPlaylist p) {
    if (p.isXtreamCodes) return Icons.dns_rounded;
    if (p.isLocalFile) return Icons.folder_rounded;
    return Icons.playlist_play_rounded;
  }

  String _railSubtitle(IptvPlaylist p) {
    final stats = _stats[p.id];
    final kind = p.isXtreamCodes
        ? 'Xtream'
        : (p.isLocalFile ? 'Local file' : 'URL');
    if (stats == null || !stats.cached) return kind;
    final live = IptvSourceStatsLoader.count(stats.live);
    return '$kind · $live channel${stats.live == 1 ? '' : 's'}';
  }

  // ---------------------------------------------------------------- pane

  Widget _buildPane(IptvTwoPaneDest dest) {
    final child = switch (dest) {
      IptvTwoPaneSourceDest(:final playlistId) => _buildSourcePane(playlistId),
      IptvTwoPaneAddDest() => _buildAddPane(),
      IptvTwoPaneListsDest() => _buildListsPane(),
      IptvTwoPaneStartupDest() => _buildStartupPane(),
      IptvTwoPaneChannelPreviewDest() => _buildChannelPreviewPane(),
      IptvTwoPaneContinueWatchingDest() => _buildContinueWatchingPane(),
      IptvTwoPaneAppearanceDest() => _buildAppearancePane(),
      IptvTwoPanePlayerGuideDest() => _buildPlayerGuidePane(),
      IptvTwoPaneRecordingDest() => _buildRecordingPane(),
      IptvTwoPaneAutoRefreshDest() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IptvTwoPanePaneHeader(
            icon: Icons.update_rounded,
            title: 'Auto-refresh',
            meta: 'All sources in this profile',
            badges: [],
          ),
          const SizedBox(height: 24),
          IptvTwoPaneRow(
            focusNode: _paneNodes[0],
            icon: Icons.schedule_rounded,
            title: iptvAutoRefreshLabel(widget.autoRefreshHours),
            subtitle: iptvAutoRefreshExplanation,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: widget.onPickAutoRefresh,
            onLeft: () => _focusRail(_autoRefreshIndex),
          ),
        ],
      ),
    };
    // A key per destination gives each view its own scroll position, so
    // arriving from a scrolled-down Channel lists doesn't drop you into a
    // source with its header already off-screen.
    return ListView(
      key: ValueKey(switch (dest) {
        IptvTwoPaneSourceDest(:final playlistId) => 'source:$playlistId',
        IptvTwoPaneAddDest() => 'add',
        IptvTwoPaneListsDest() => 'lists',
        IptvTwoPaneStartupDest() => 'startup',
        IptvTwoPaneChannelPreviewDest() => 'channel-preview',
        IptvTwoPaneContinueWatchingDest() => 'continue-watching',
        IptvTwoPaneAppearanceDest() => 'appearance',
        IptvTwoPanePlayerGuideDest() => 'player_guide',
        IptvTwoPaneRecordingDest() => 'recording',
        IptvTwoPaneAutoRefreshDest() => 'auto-refresh',
      }),
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 32),
      children: [child],
    );
  }

  Widget _buildSourcePane(String playlistId) {
    final t = _app.settings;
    // Deleting the last source can leave one frame pointing here before
    // didUpdateWidget re-homes the pane; `.first` on an empty list would
    // throw rather than just render nothing.
    if (widget.playlists.isEmpty) return _buildAddPane();
    final playlist = widget.playlists.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => widget.playlists.first,
    );
    final stats = _stats[playlist.id] ?? const IptvSourceStats.none();
    final isDefault = widget.defaultPlaylistId == playlist.id;
    final busy = widget.refreshingIds.contains(playlist.id);
    // Local files have no remote to re-fetch.
    final canRefresh = !playlist.isLocalFile && !playlist.connectionReadOnly;

    var row = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IptvTwoPanePaneHeader(
          icon: _iconFor(playlist),
          title: playlist.name,
          meta: _sourceMeta(playlist),
          badges: [
            if (isDefault)
              IptvTwoPaneBadge('Default', t.warning, Icons.star_rounded),
            if (stats.guide == IptvGuideSource.custom)
              IptvTwoPaneBadge(
                'Custom guide',
                t.accent2,
                Icons.event_note_rounded,
              ),
            if (stats.guide == IptvGuideSource.provider)
              IptvTwoPaneBadge(
                'Provider guide',
                t.success,
                Icons.event_available_rounded,
              ),
            if (stats.cached && stats.refreshedAt != null)
              IptvTwoPaneBadge(
                'Refreshed ${IptvSourceStatsLoader.ago(stats.refreshedAt)}',
                t.accent2,
                Icons.schedule_rounded,
              ),
            if (playlist.connectionReadOnly)
              IptvTwoPaneBadge('Shared', t.accent2, Icons.lock_outline_rounded),
          ],
        ),
        const SizedBox(height: 20),
        if (stats.cached)
          IptvTwoPaneStatStrip(
            stats: [
              ('Live channels', IptvSourceStatsLoader.count(stats.live)),
              if (stats.hasVodSplit)
                ('Movies', IptvSourceStatsLoader.count(stats.movies)),
              if (stats.hasVodSplit)
                ('Series', IptvSourceStatsLoader.count(stats.series)),
              if (!stats.hasVodSplit)
                ('Categories', IptvSourceStatsLoader.count(stats.categories)),
            ],
          )
        else
          IptvTwoPaneQuietBanner(
            icon: playlist.isLocalFile
                ? Icons.sd_card_rounded
                : Icons.cloud_off_rounded,
            // "Not loaded yet" and "0 channels" are different facts; never
            // render the first as the second.
            text: playlist.isLocalFile
                ? 'Imported from a file — it plays from the copy stored in the app.'
                : 'Not loaded yet. Open this source in IPTV, or refresh it here.',
          ),
        const SizedBox(height: 20),
        IptvTwoPaneRowGroup(
          children: [
            if (canRefresh)
              IptvTwoPaneRow(
                focusNode: _paneNode(row++),
                icon: Icons.refresh_rounded,
                title: busy ? 'Refreshing…' : 'Refresh now',
                subtitle: 'Re-fetch channels and rebuild the catalog',
                trailing: Text(
                  stats.refreshedAt == null
                      ? 'never'
                      : IptvSourceStatsLoader.ago(stats.refreshedAt),
                  style: TextStyle(fontSize: 12.5, color: t.dim),
                ),
                // Stays focusable while busy, with the tap neutered — going
                // non-focusable mid-refresh would yank the focus out from
                // under the user who just pressed OK on it. Same idiom as
                // _TvFocusableButton's `_isAdding ? () {} : ...`.
                onTap: busy ? () {} : () => widget.onRefresh(playlist),
                onLeft: _returnToRail,
              ),
            IptvTwoPaneRow(
              focusNode: _paneNode(row++),
              icon: Icons.star_rounded,
              title: 'Default playlist',
              subtitle: 'Loads automatically when you open IPTV',
              trailing: Switch(
                value: isDefault,
                onChanged: (_) => widget.onSetDefault(playlist),
              ),
              onTap: () => widget.onSetDefault(playlist),
              onLeft: _returnToRail,
            ),
            if (!playlist.connectionReadOnly)
              IptvTwoPaneRow(
                focusNode: _paneNode(row++),
                icon: Icons.edit_rounded,
                title: 'Edit source',
                subtitle: playlist.isXtreamCodes
                    ? 'Name, server, username, password'
                    : 'Name, URL and guide URL',
                trailing: _chevron,
                onTap: () => widget.onEdit(playlist),
                onLeft: _returnToRail,
              ),
            // Imported files store no catalog, so there is nothing to hide
            // categories against — the row stays off them entirely.
            if (widget.onManageHidden != null && !playlist.isLocalFile)
              IptvTwoPaneRow(
                focusNode: _paneNode(row++),
                icon: Icons.visibility_off_rounded,
                title: 'Hidden categories',
                subtitle: switch (widget.hiddenCounts[playlist.id] ?? 0) {
                  0 => 'Nothing hidden from this source',
                  1 => '1 category hidden',
                  final n => '$n categories hidden',
                },
                trailing: _chevron,
                onTap: () => widget.onManageHidden!(playlist),
                onLeft: _returnToRail,
              ),
            if (widget.onManageCategoryOrder != null)
              IptvTwoPaneRow(
                focusNode: _paneNode(row++),
                icon: Icons.swap_vert_rounded,
                title: 'Category order',
                subtitle: 'Arrange categories in this source',
                trailing: _chevron,
                onTap: () => widget.onManageCategoryOrder!(playlist),
                onLeft: _returnToRail,
              ),
            if (!playlist.connectionReadOnly)
              IptvTwoPaneRow(
                focusNode: _paneNode(row++),
                icon: Icons.event_note_rounded,
                title: 'Guide (EPG) source',
                subtitle: switch (stats.guide) {
                  IptvGuideSource.custom =>
                    'Custom XMLTV URL set for this source',
                  IptvGuideSource.provider =>
                    "Using the provider's own guide data",
                  IptvGuideSource.none =>
                    'No guide source — rows show no programmes',
                },
                trailing: _chevron,
                onTap: () => widget.onEdit(playlist),
                onLeft: _returnToRail,
              ),
            if (!playlist.connectionReadOnly)
              IptvTwoPaneRow(
                focusNode: _paneNode(row++),
                icon: Icons.delete_outline_rounded,
                title: 'Remove source',
                subtitle: 'Keeps your lists and watch history',
                danger: true,
                trailing: _chevron,
                onTap: () => widget.onDelete(playlist),
                onLeft: _returnToRail,
                isLast: true,
              ),
          ],
        ),
      ],
    );
  }

  String _sourceMeta(IptvPlaylist p) {
    if (p.credentialsRedacted) {
      return 'Shared connection · credentials hidden';
    }
    if (p.isXtreamCodes) {
      final user = (p.username ?? '').isEmpty ? '' : ' · ${p.username}';
      return 'Xtream Codes · ${p.serverUrl ?? ''}$user';
    }
    if (p.isLocalFile) return 'Local file';
    return p.url;
  }

  Widget _buildAddPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IptvTwoPanePaneHeader(
          icon: Icons.add_rounded,
          title: 'Add a source',
          meta: 'Pick how you want to connect, then fill in the details.',
          badges: [],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: IptvTwoPaneMethodCard(
                focusNode: widget.urlMethodFocusNode,
                icon: Icons.link_rounded,
                label: 'From URL',
                hint: 'An M3U or M3U8 link',
                selected: widget.addMethod == 0,
                onTap: () => widget.onAddMethodChanged(0),
                // Leftmost card: LEFT leaves the pane entirely.
                onLeft: _returnToRail,
                onRight: widget.fileMethodFocusNode.requestFocus,
                onDown: widget.onFocusFirstFormField,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: IptvTwoPaneMethodCard(
                focusNode: widget.fileMethodFocusNode,
                icon: Icons.folder_open_rounded,
                label: 'From file',
                hint: 'A file on this device',
                selected: widget.addMethod == 1,
                onTap: () => widget.onAddMethodChanged(1),
                onLeft: widget.urlMethodFocusNode.requestFocus,
                onRight: widget.xtreamMethodFocusNode.requestFocus,
                onDown: widget.onFocusFirstFormField,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: IptvTwoPaneMethodCard(
                focusNode: widget.xtreamMethodFocusNode,
                icon: Icons.vpn_key_rounded,
                label: 'Xtream login',
                hint: 'Server, user, password',
                selected: widget.addMethod == 2,
                onTap: () => widget.onAddMethodChanged(2),
                onLeft: widget.fileMethodFocusNode.requestFocus,
                onRight: null,
                onDown: widget.onFocusFirstFormField,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        // Only the chosen method is built, so DPAD can never land on a
        // hidden field — the old fixed-height TabBarView kept all three
        // alive and had to ExcludeFocus the other two.
        switch (widget.addMethod) {
          1 => widget.fileFormBuilder(context),
          2 => widget.xtreamFormBuilder(context),
          _ => widget.urlFormBuilder(context),
        },
      ],
    );
  }

  Widget _buildListsPane() {
    var row = 0;
    final lists = widget.customLists;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IptvTwoPanePaneHeader(
          icon: Icons.bookmark_rounded,
          title: 'Channel lists',
          meta:
              'Hold OK on any channel to add it to a list. '
              'Deleting a list never deletes its channels.',
          badges: [],
        ),
        const SizedBox(height: 20),
        IptvTwoPaneRowGroup(
          children: [
            // Nothing to configure — built in, can't be renamed, reordered or
            // deleted. Deliberately not a focus stop, and deliberately not
            // holding a pool slot.
            IptvTwoPaneRow(
              focusNode: null,
              icon: Icons.star_rounded,
              title: 'Favorites',
              subtitle: 'Built in · always available',
              trailing: null,
              onTap: null,
              onLeft: _returnToRail,
            ),
            IptvTwoPaneRow(
              focusNode: _paneNode(row++),
              icon: Icons.reorder_rounded,
              title: 'Channel order',
              subtitle: 'Arrange Favorites and saved lists',
              trailing: _chevron,
              onTap: widget.onManageChannelOrder,
              onLeft: _returnToRail,
            ),
            for (var i = 0; i < lists.length; i++)
              IptvTwoPaneRow(
                focusNode: _paneNode(row++),
                icon: Icons.bookmark_border_rounded,
                title: lists[i].name,
                subtitle:
                    '${lists[i].channelCount} channel'
                    '${lists[i].channelCount == 1 ? '' : 's'}',
                trailing: _chevron,
                onTap: () => widget.onListActions(lists[i]),
                onLeft: _returnToRail,
              ),
            IptvTwoPaneRow(
              focusNode: _paneNode(row++),
              icon: Icons.add_rounded,
              title: 'Create list',
              subtitle: null,
              trailing: _chevron,
              onTap: widget.onCreateList,
              onLeft: _returnToRail,
              isLast: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStartupPane() {
    var row = 0;
    final pinned =
        widget.startupMode == StartupIptvStorage.startupIptvModePinned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IptvTwoPanePaneHeader(
          icon: Icons.play_circle_outline_rounded,
          title: 'Startup channel',
          meta: 'Open straight into a live channel when the app starts.',
          badges: [],
        ),
        const SizedBox(height: 20),
        IptvTwoPaneRowGroup(
          children: [
            IptvTwoPaneRow(
              focusNode: _paneNode(row++),
              icon: Icons.power_settings_new_rounded,
              title: 'Start on a channel',
              subtitle: 'Press BACK while it is tuning to stop',
              trailing: Switch(
                value: widget.startupEnabled,
                onChanged: widget.onToggleStartup,
              ),
              onTap: () => widget.onToggleStartup(!widget.startupEnabled),
              onLeft: _returnToRail,
              isLast: !widget.startupEnabled,
            ),
            if (widget.startupEnabled) ...[
              IptvTwoPaneRow(
                focusNode: _paneNode(row++),
                icon: Icons.history_rounded,
                title: 'Last watched channel',
                // Honest about the bootstrap: the first boot after enabling
                // this has nothing to resume, and silently doing nothing
                // reads as broken.
                subtitle: widget.hasLastLiveChannel
                    ? 'Currently: ${widget.lastLiveChannelLabel}'
                    : 'Nothing watched yet — starts on the first channel, '
                          'then remembers what you watch.',
                trailing: Radio<String>(
                  value: StartupIptvStorage.startupIptvModeLast,
                  groupValue: widget.startupMode,
                  onChanged: (v) =>
                      v == null ? null : widget.onStartupModeChanged(v),
                ),
                onTap: () => widget.onStartupModeChanged(
                  StartupIptvStorage.startupIptvModeLast,
                ),
                onLeft: _returnToRail,
              ),
              IptvTwoPaneRow(
                focusNode: _paneNode(row++),
                icon: Icons.push_pin_rounded,
                title: 'A specific channel',
                subtitle: widget.startupChannelLabel,
                trailing: Radio<String>(
                  value: StartupIptvStorage.startupIptvModePinned,
                  groupValue: widget.startupMode,
                  onChanged: (v) =>
                      v == null ? null : widget.onStartupModeChanged(v),
                ),
                onTap: () => widget.onStartupModeChanged(
                  StartupIptvStorage.startupIptvModePinned,
                ),
                onLeft: _returnToRail,
                isLast: !pinned,
              ),
              if (pinned)
                IptvTwoPaneRow(
                  focusNode: _paneNode(row++),
                  icon: Icons.live_tv_rounded,
                  title: widget.hasStartupChannel
                      ? 'Change channel'
                      : 'Choose channel',
                  subtitle: null,
                  trailing: _chevron,
                  onTap: widget.onPickStartupChannel,
                  onLeft: _returnToRail,
                  isLast: true,
                ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildContinueWatchingPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IptvTwoPanePaneHeader(
          icon: Icons.history_toggle_off_rounded,
          title: 'Continue watching',
          meta:
              'The shelf of on-demand movies and series you have started, '
              'on Home and in IPTV.',
          badges: [],
        ),
        const SizedBox(height: 20),
        IptvTwoPaneRowGroup(
          children: [
            IptvTwoPaneRow(
              focusNode: _paneNode(0),
              icon: Icons.playlist_add_check_rounded,
              title: 'Track movies and series',
              // Says what stays behind, because "off" reading as "my resume
              // positions are gone" is the obvious wrong guess here.
              subtitle:
                  'Off hides the shelf and stops adding to it. Nothing '
                  'is deleted, and playback still resumes where you left off',
              trailing: Switch(
                value: widget.trackContinueWatching,
                onChanged: widget.onToggleTrackContinueWatching,
              ),
              onTap: () => widget.onToggleTrackContinueWatching(
                !widget.trackContinueWatching,
              ),
              onLeft: _returnToRail,
              isLast: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChannelPreviewPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IptvTwoPanePaneHeader(
          icon: Icons.ondemand_video_rounded,
          title: 'Channel preview',
          meta:
              'Control whether the side panel tunes the focused channel '
              'while you browse.',
          badges: [],
        ),
        const SizedBox(height: 20),
        IptvTwoPaneRowGroup(
          children: [
            IptvTwoPaneRow(
              focusNode: _paneNode(0),
              icon: Icons.play_circle_outline_rounded,
              title: 'Play channel previews',
              subtitle:
                  'Uses a provider stream while browsing. Turn it off to '
                  'save a connection; fullscreen playback still works',
              trailing: Switch(
                value: widget.channelPreviewEnabled,
                onChanged: widget.onToggleChannelPreview,
              ),
              onTap: () =>
                  widget.onToggleChannelPreview(!widget.channelPreviewEnabled),
              onLeft: _returnToRail,
              isLast: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAppearancePane() {
    var row = 0;
    IconData styleIcon(String value) => switch (value) {
      'edition' => Icons.menu_book_rounded,
      'console' => Icons.tune_rounded,
      'spotlight' => Icons.calendar_view_week_rounded,
      _ => Icons.grid_view_rounded,
    };

    Widget styleRow({
      required IconData icon,
      required String value,
      required String title,
      required String subtitle,
      bool isLast = false,
    }) {
      return IptvTwoPaneRow(
        focusNode: _paneNode(row++),
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: Radio<String>(
          value: value,
          groupValue: widget.iptvStyle,
          onChanged: (v) =>
              v == null ? null : widget.onIptvStyleChanged?.call(v),
        ),
        onTap: () => widget.onIptvStyleChanged?.call(value),
        onLeft: _returnToRail,
        isLast: isLast,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IptvTwoPanePaneHeader(
          icon: Icons.style_rounded,
          title: 'Appearance',
          meta:
              'How the IPTV page looks on TV and desktop. Phones keep the '
              'classic list either way.',
          badges: [],
        ),
        const SizedBox(height: 20),
        IptvTwoPaneRowGroup(
          children: [
            for (var index = 0; index < kIptvStyleChoices.length; index++)
              styleRow(
                icon: styleIcon(kIptvStyleChoices[index].value),
                value: kIptvStyleChoices[index].value,
                title: kIptvStyleChoices[index].label,
                subtitle: kIptvStyleChoices[index].subtitle,
                isLast: index == kIptvStyleChoices.length - 1,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlayerGuidePane() {
    var row = 0;
    Widget styleRow({
      required IconData icon,
      required String value,
      required String title,
      required String subtitle,
      bool isLast = false,
    }) {
      return IptvTwoPaneRow(
        focusNode: _paneNode(row++),
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: Radio<String>(
          value: value,
          groupValue: widget.playerGuideStyle,
          onChanged: (v) =>
              v == null ? null : widget.onPlayerGuideStyleChanged?.call(v),
        ),
        onTap: () => widget.onPlayerGuideStyleChanged?.call(value),
        onLeft: _returnToRail,
        isLast: isLast,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IptvTwoPanePaneHeader(
          icon: Icons.smart_display_rounded,
          title: 'Player guide',
          meta:
              'How the channel banner and in-player guide look during live '
              'TV — the next playback session uses the new look.',
          badges: [],
        ),
        const SizedBox(height: 20),
        IptvTwoPaneRowGroup(
          children: [
            styleRow(
              icon: Icons.play_circle_outline_rounded,
              value: 'classic',
              title: 'Classic',
              subtitle: "Today's look",
            ),
            styleRow(
              icon: Icons.blur_on_rounded,
              value: 'glass',
              title: 'Cinema Glass',
              subtitle:
                  'Translucent panels, one violet accent — modern streaming',
            ),
            styleRow(
              icon: Icons.menu_book_rounded,
              value: 'edition',
              title: 'Midnight Edition',
              subtitle: 'Ink panels and serif headlines — editorial',
            ),
            styleRow(
              icon: Icons.tune_rounded,
              value: 'console',
              title: 'Master Control',
              subtitle: 'Black instrument — mono numerals, amber machinery',
              isLast: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecordingPane() {
    var row = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const IptvTwoPanePaneHeader(
          icon: Icons.fiber_manual_record_rounded,
          title: 'Recording',
          meta:
              'Background captures that survive zapping and leaving the '
              'app, plus programmes scheduled from the TV guide.',
          badges: [],
        ),
        const SizedBox(height: 20),
        IptvTwoPaneRowGroup(
          children: [
            if (widget.showEngineToggle)
              IptvTwoPaneRow(
                focusNode: _paneNode(row++),
                icon: Icons.settings_backup_restore_rounded,
                title: 'Background recording engine',
                subtitle:
                    'Off returns to player-tied recording. Uses an '
                    'extra connection to your provider.',
                trailing: Switch(
                  value: widget.recordingEngineEnabled,
                  onChanged: widget.onToggleRecordingEngine,
                ),
                onTap: () => widget.onToggleRecordingEngine?.call(
                  !widget.recordingEngineEnabled,
                ),
                onLeft: _returnToRail,
                isLast: !widget.recordingEngineEnabled,
              ),
            if (!widget.showEngineToggle || widget.recordingEngineEnabled)
              IptvTwoPaneRow(
                focusNode: _paneNode(row++),
                icon: Icons.filter_none_rounded,
                title: 'Simultaneous recordings',
                subtitle:
                    '${widget.maxConcurrentRecordings} at a time — each is an '
                    'extra provider connection',
                trailing: _chevron,
                onTap: () => widget.onPickMaxConcurrent?.call(),
                onLeft: _returnToRail,
                isLast: false,
              ),
            if ((!widget.showEngineToggle || widget.recordingEngineEnabled) &&
                widget.batteryExempt != null)
              IptvTwoPaneRow(
                focusNode: _paneNode(row++),
                icon: Icons.battery_alert_rounded,
                title: 'Battery optimization',
                subtitle: widget.batteryExempt == true
                    ? 'Excluded — long recordings can run to the end'
                    : 'Optimized — the phone may kill long recordings; '
                          'tap to exclude Debrify',
                trailing: _chevron,
                onTap: () => widget.onRequestBatteryExemption?.call(),
                onLeft: _returnToRail,
                isLast: false,
              ),
            if (!widget.showEngineToggle || widget.recordingEngineEnabled)
              IptvTwoPaneRow(
                focusNode: _paneNode(row++),
                icon: Icons.event_rounded,
                title: 'Recordings',
                subtitle: widget.scheduledCount == 0
                    ? 'Live captures, schedules and your recorded files'
                    : '${widget.scheduledCount} scheduled · live captures '
                          'and recorded files',
                trailing: _chevron,
                onTap: () => widget.onOpenScheduledRecordings?.call(),
                onLeft: _returnToRail,
                isLast: true,
              ),
          ],
        ),
      ],
    );
  }

  void _returnToRail() => _focusRail(_selectedRailIndex);

  Widget get _chevron =>
      Icon(Icons.chevron_right_rounded, size: 20, color: _app.settings.dim2);
}
