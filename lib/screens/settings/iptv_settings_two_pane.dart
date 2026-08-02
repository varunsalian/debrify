import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/iptv_playlist.dart';
import '../../services/iptv_media_store.dart';
import '../../services/iptv_source_stats.dart';
import '../../services/storage_service.dart';
import 'widgets/settings_widgets.dart';

/// Two-pane IPTV settings for TV and desktop ("Concept A"): a rail of the
/// user's actual sources on the left, the selected source's detail on the
/// right, with Add / Lists / Startup as rail destinations below them.
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
    this.onManageHidden,
    this.hiddenCounts = const {},
    required this.onFocusFirstFormField,
    required this.onListActions,
    required this.onToggleStartup,
    required this.onStartupModeChanged,
    required this.onPickStartupChannel,
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
  final List<IptvListMeta> customLists;

  final bool startupEnabled;
  final String startupMode;
  final String startupChannelLabel;
  final String lastLiveChannelLabel;
  final bool hasStartupChannel;
  final bool hasLastLiveChannel;

  /// The Recording rail entry + pane exist where SOME recorder can run:
  /// Android 10+ (engine + toggle) or desktop (in-app scheduler only). On
  /// iOS/pre-Q the rail ends at Startup and nothing promises recording that
  /// cannot run.
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

  @override
  State<IptvSettingsTwoPane> createState() => IptvSettingsTwoPaneState();
}

/// What the pane is showing. Sources are identified by playlist id so a
/// refresh that rebuilds the list can't shift the selection onto a neighbour.
sealed class _Dest {
  const _Dest();
}

class _SourceDest extends _Dest {
  const _SourceDest(this.playlistId);
  final String playlistId;
}

class _AddDest extends _Dest {
  const _AddDest();
}

class _ListsDest extends _Dest {
  const _ListsDest();
}

class _StartupDest extends _Dest {
  const _StartupDest();
}

class _RecordingDest extends _Dest {
  const _RecordingDest();
}

class IptvSettingsTwoPaneState extends State<IptvSettingsTwoPane> {
  /// Rows in the busiest pane (a source: refresh, default, edit, guide,
  /// delete) plus headroom for the lists pane, which grows with the user's
  /// lists and is capped by the pool below.
  static const int _panePoolSize = 24;

  final ValueNotifier<_Dest> _dest = ValueNotifier(const _AddDest());

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
    _dest.value = widget.openAddSource ? const _AddDest() : _initialDest();
  }

  @override
  void didUpdateWidget(covariant IptvSettingsTwoPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRailNodes();
    _syncStats();
    // A deleted source must not leave the pane pointing at a ghost.
    final dest = _dest.value;
    if (dest is _SourceDest &&
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

  _Dest _initialDest() {
    if (widget.playlists.isEmpty) return const _AddDest();
    final id = widget.defaultPlaylistId;
    if (id != null && widget.playlists.any((p) => p.id == id)) {
      return _SourceDest(id);
    }
    return _SourceDest(widget.playlists.first.id);
  }

  /// Rail entries: every source, then Add, Lists, Startup.
  int get _railCount =>
      widget.playlists.length + 3 + (widget.showRecordingSection ? 1 : 0);

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
    final alreadyThere = _dest.value is _AddDest;
    _dest.value = const _AddDest();
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
      _SourceDest(:final playlistId) => () {
        final i = widget.playlists.indexWhere((p) => p.id == playlistId);
        return i < 0 ? 0 : i;
      }(),
      _AddDest() => widget.playlists.length,
      _ListsDest() => widget.playlists.length + 1,
      _StartupDest() => widget.playlists.length + 2,
      _RecordingDest() => widget.playlists.length + 3,
    };
  }

  _Dest _destForRail(int index) {
    if (index < widget.playlists.length) {
      return _SourceDest(widget.playlists[index].id);
    }
    return switch (index - widget.playlists.length) {
      0 => const _AddDest(),
      1 => const _ListsDest(),
      2 => const _StartupDest(),
      _ => widget.showRecordingSection
          ? const _RecordingDest()
          : const _StartupDest(),
    };
  }

  void _enterPane() {
    // The add pane's first stop is the method chooser, which the parent owns.
    if (_dest.value is _AddDest) {
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
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildRail(),
          Container(width: 1, color: kSettingsLine),
          Expanded(
            child: ValueListenableBuilder<_Dest>(
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
    final width = MediaQuery.sizeOf(context).width;
    return SizedBox(
      width: width >= 1400 ? 400 : 330,
      child: ValueListenableBuilder<_Dest>(
        valueListenable: _dest,
        builder: (context, dest, _) {
          final selected = _selectedRailIndex;
          return ListView(
            controller: _railScroll,
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
            children: [
              const _RailHeading('Sources'),
              for (var i = 0; i < widget.playlists.length; i++)
                _RailEntry(
                  focusNode: _railNodes[i],
                  icon: _iconFor(widget.playlists[i]),
                  title: widget.playlists[i].name,
                  subtitle: _railSubtitle(widget.playlists[i]),
                  selected: selected == i,
                  trailing: widget.defaultPlaylistId == widget.playlists[i].id
                      ? Icon(
                          Icons.star_rounded,
                          size: 18,
                          color: kSettingsAmber,
                        )
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
                    style: TextStyle(fontSize: 13, color: kSettingsDim),
                  ),
                ),
              _RailEntry(
                focusNode: _railNodes[widget.playlists.length],
                icon: Icons.add_rounded,
                title: 'Add a source',
                subtitle: 'URL, file, or Xtream login',
                selected: selected == widget.playlists.length,
                onFocused: () => _dest.value = const _AddDest(),
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
                child: Container(height: 1, color: kSettingsLine),
              ),
              _RailEntry(
                focusNode: _railNodes[widget.playlists.length + 1],
                icon: Icons.bookmark_rounded,
                title: 'Channel lists',
                subtitle: _listsSubtitle,
                selected: selected == widget.playlists.length + 1,
                chevron: true,
                onFocused: () => _dest.value = const _ListsDest(),
                onSelect: _enterPane,
                onUp: () => _focusRail(widget.playlists.length),
                onDown: () => _focusRail(widget.playlists.length + 2),
                onRight: _enterPane,
              ),
              _RailEntry(
                focusNode: _railNodes[widget.playlists.length + 2],
                icon: Icons.play_circle_outline_rounded,
                title: 'Startup channel',
                subtitle: widget.startupEnabled
                    ? (widget.startupMode ==
                              StorageService.startupIptvModePinned
                          ? 'On · a specific channel'
                          : 'On · last watched')
                    : 'Off',
                selected: selected == widget.playlists.length + 2,
                chevron: true,
                onFocused: () => _dest.value = const _StartupDest(),
                onSelect: _enterPane,
                onUp: () => _focusRail(widget.playlists.length + 1),
                onDown: widget.showRecordingSection
                    ? () => _focusRail(widget.playlists.length + 3)
                    : null,
                onRight: _enterPane,
              ),
              if (widget.showRecordingSection)
                _RailEntry(
                  focusNode: _railNodes[widget.playlists.length + 3],
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
                  selected: selected == widget.playlists.length + 3,
                  chevron: true,
                  onFocused: () => _dest.value = const _RecordingDest(),
                  onSelect: _enterPane,
                  onUp: () => _focusRail(widget.playlists.length + 2),
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

  Widget _buildPane(_Dest dest) {
    final child = switch (dest) {
      _SourceDest(:final playlistId) => _buildSourcePane(playlistId),
      _AddDest() => _buildAddPane(),
      _ListsDest() => _buildListsPane(),
      _StartupDest() => _buildStartupPane(),
      _RecordingDest() => _buildRecordingPane(),
    };
    // A key per destination gives each view its own scroll position, so
    // arriving from a scrolled-down Channel lists doesn't drop you into a
    // source with its header already off-screen.
    return ListView(
      key: ValueKey(switch (dest) {
        _SourceDest(:final playlistId) => 'source:$playlistId',
        _AddDest() => 'add',
        _ListsDest() => 'lists',
        _StartupDest() => 'startup',
        _RecordingDest() => 'recording',
      }),
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 32),
      children: [child],
    );
  }

  Widget _buildSourcePane(String playlistId) {
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
    final canRefresh = !playlist.isLocalFile;

    var row = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PaneHeader(
          icon: _iconFor(playlist),
          title: playlist.name,
          meta: _sourceMeta(playlist),
          badges: [
            if (isDefault)
              _Badge('Default', kSettingsAmber, Icons.star_rounded),
            if (stats.guide == IptvGuideSource.custom)
              _Badge(
                'Custom guide',
                kSettingsAccent2,
                Icons.event_note_rounded,
              ),
            if (stats.guide == IptvGuideSource.provider)
              _Badge(
                'Provider guide',
                kSettingsGreen,
                Icons.event_available_rounded,
              ),
            if (stats.cached && stats.refreshedAt != null)
              _Badge(
                'Refreshed ${IptvSourceStatsLoader.ago(stats.refreshedAt)}',
                kSettingsAccent2,
                Icons.schedule_rounded,
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (stats.cached)
          _StatStrip(
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
          _QuietBanner(
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
        _RowGroup(
          children: [
            if (canRefresh)
              _PaneRow(
                focusNode: _paneNode(row++),
                icon: Icons.refresh_rounded,
                title: busy ? 'Refreshing…' : 'Refresh now',
                subtitle: 'Re-fetch channels and rebuild the catalog',
                trailing: Text(
                  stats.refreshedAt == null
                      ? 'never'
                      : IptvSourceStatsLoader.ago(stats.refreshedAt),
                  style: TextStyle(fontSize: 12.5, color: kSettingsDim),
                ),
                // Stays focusable while busy, with the tap neutered — going
                // non-focusable mid-refresh would yank the focus out from
                // under the user who just pressed OK on it. Same idiom as
                // _TvFocusableButton's `_isAdding ? () {} : ...`.
                onTap: busy ? () {} : () => widget.onRefresh(playlist),
                onLeft: _returnToRail,
              ),
            _PaneRow(
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
            _PaneRow(
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
              _PaneRow(
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
            _PaneRow(
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
            _PaneRow(
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
        const _PaneHeader(
          icon: Icons.add_rounded,
          title: 'Add a source',
          meta: 'Pick how you want to connect, then fill in the details.',
          badges: [],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _MethodCard(
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
              child: _MethodCard(
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
              child: _MethodCard(
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
        const _PaneHeader(
          icon: Icons.bookmark_rounded,
          title: 'Channel lists',
          meta:
              'Hold OK on any channel to add it to a list. '
              'Deleting a list never deletes its channels.',
          badges: [],
        ),
        const SizedBox(height: 20),
        _RowGroup(
          children: [
            // Nothing to configure — built in, can't be renamed, reordered or
            // deleted. Deliberately not a focus stop, and deliberately not
            // holding a pool slot.
            _PaneRow(
              focusNode: null,
              icon: Icons.star_rounded,
              title: 'Favorites',
              subtitle: 'Built in · always available',
              trailing: null,
              onTap: null,
              onLeft: _returnToRail,
            ),
            for (var i = 0; i < lists.length; i++)
              _PaneRow(
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
            _PaneRow(
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
    final pinned = widget.startupMode == StorageService.startupIptvModePinned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PaneHeader(
          icon: Icons.play_circle_outline_rounded,
          title: 'Startup channel',
          meta: 'Open straight into a live channel when the app starts.',
          badges: [],
        ),
        const SizedBox(height: 20),
        _RowGroup(
          children: [
            _PaneRow(
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
              _PaneRow(
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
                  value: StorageService.startupIptvModeLast,
                  groupValue: widget.startupMode,
                  onChanged: (v) =>
                      v == null ? null : widget.onStartupModeChanged(v),
                ),
                onTap: () => widget.onStartupModeChanged(
                  StorageService.startupIptvModeLast,
                ),
                onLeft: _returnToRail,
              ),
              _PaneRow(
                focusNode: _paneNode(row++),
                icon: Icons.push_pin_rounded,
                title: 'A specific channel',
                subtitle: widget.startupChannelLabel,
                trailing: Radio<String>(
                  value: StorageService.startupIptvModePinned,
                  groupValue: widget.startupMode,
                  onChanged: (v) =>
                      v == null ? null : widget.onStartupModeChanged(v),
                ),
                onTap: () => widget.onStartupModeChanged(
                  StorageService.startupIptvModePinned,
                ),
                onLeft: _returnToRail,
                isLast: !pinned,
              ),
              if (pinned)
                _PaneRow(
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

  Widget _buildRecordingPane() {
    var row = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PaneHeader(
          icon: Icons.fiber_manual_record_rounded,
          title: 'Recording',
          meta: 'Background captures that survive zapping and leaving the '
              'app, plus programmes scheduled from the TV guide.',
          badges: [],
        ),
        const SizedBox(height: 20),
        _RowGroup(
          children: [
            if (widget.showEngineToggle)
              _PaneRow(
                focusNode: _paneNode(row++),
                icon: Icons.settings_backup_restore_rounded,
                title: 'Background recording engine',
                subtitle: 'Off returns to player-tied recording. Uses an '
                    'extra connection to your provider.',
                trailing: Switch(
                  value: widget.recordingEngineEnabled,
                  onChanged: widget.onToggleRecordingEngine,
                ),
                onTap: () => widget.onToggleRecordingEngine
                    ?.call(!widget.recordingEngineEnabled),
                onLeft: _returnToRail,
                isLast: !widget.recordingEngineEnabled,
              ),
            if (!widget.showEngineToggle || widget.recordingEngineEnabled)
              _PaneRow(
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
              _PaneRow(
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
              _PaneRow(
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
      Icon(Icons.chevron_right_rounded, size: 20, color: kSettingsDim2);
}

// ------------------------------------------------------------------ pieces

class _RailHeading extends StatelessWidget {
  const _RailHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: kSettingsDim2,
      ),
    ),
  );
}

/// One rail entry. Focus selects it (the pane updates live), OK/RIGHT enters
/// the pane. Snap styling, never a tween — the TV GPU rule.
class _RailEntry extends StatefulWidget {
  const _RailEntry({
    required this.focusNode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onFocused,
    required this.onSelect,
    required this.onUp,
    required this.onDown,
    required this.onRight,
    this.trailing,
    this.chevron = false,
    this.busy = false,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onFocused;
  final VoidCallback onSelect;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onRight;
  final Widget? trailing;
  final bool chevron;
  final bool busy;

  @override
  State<_RailEntry> createState() => _RailEntryState();
}

class _RailEntryState extends State<_RailEntry> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || widget.selected;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (has) {
        if (!mounted) return;
        setState(() => _focused = has);
        if (has) {
          widget.onFocused();
          // Keep the entry on screen when DPAD walks past the fold.
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: Duration.zero,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowUp:
            // Deliberately NOT consumed at the top of the rail: UP has to
            // escape upward to the page's back button, the way every other
            // settings page behaves.
            if (widget.onUp == null) return KeyEventResult.ignored;
            widget.onUp!();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowDown:
            // Consumed at the bottom, unlike UP: there is nothing below the
            // rail, and leaving it to geometric traversal would fling focus
            // sideways into the pane instead of simply stopping.
            if (widget.onDown == null) return KeyEventResult.handled;
            widget.onDown!();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowRight:
            widget.onRight();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.select:
          case LogicalKeyboardKey.space:
            widget.onSelect();
            return KeyEventResult.handled;
        }
        // LEFT is deliberately unhandled: the page's own back/sidebar
        // handling owns it, exactly as the main settings rail does.
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        // The whole row is the target, not just the glyphs it happens to
        // paint. Without this the padding is dead space — tolerable while
        // hover also selected, unacceptable now that clicking is the only
        // pointer affordance.
        behavior: HitTestBehavior.opaque,
        // Pointer: select only. Deliberately NOT onSelect() — that enters the
        // pane, which is the remote's OK behaviour; with a mouse it would
        // yank the focus ring into the pane on every click in the rail.
        onTap: widget.focusNode.requestFocus,
        child: MouseRegion(
          // Hover deliberately does nothing. Focus previews the pane, and on
          // TV focus IS the cursor — but with a mouse, merely crossing the
          // rail on the way somewhere else would swap the pane out from under
          // whatever the user was reading.
          cursor: SystemMouseCursors.click,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: _focused
                  ? kSettingsPanel2
                  : (widget.selected ? kSettingsPanel : null),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: _focused ? kSettingsAccent : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _focused ? kSettingsAccent : kSettingsPanel2,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: widget.busy
                      ? const Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          widget.icon,
                          size: 18,
                          color: _focused ? Colors.white : kSettingsAccent2,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: kSettingsDim),
                      ),
                    ],
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
                if (widget.chevron)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: kSettingsDim2,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({
    required this.icon,
    required this.title,
    required this.meta,
    required this.badges,
  });

  final IconData icon;
  final String title;
  final String meta;
  final List<Widget> badges;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: kSettingsPanel2,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 26, color: kSettingsAccent2),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                meta,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: kSettingsDim),
              ),
              if (badges.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 7, runSpacing: 7, children: badges),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class _StatStrip extends StatelessWidget {
  const _StatStrip({required this.stats});
  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < stats.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: kSettingsPanel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kSettingsLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stats[i].$2,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  stats[i].$1.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color: kSettingsDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );
}

class _QuietBanner extends StatelessWidget {
  const _QuietBanner({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: kSettingsPanel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: kSettingsLine),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: kSettingsDim),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: kSettingsDim),
          ),
        ),
      ],
    ),
  );
}

class _RowGroup extends StatelessWidget {
  const _RowGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: kSettingsPanel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kSettingsLine),
    ),
    child: Column(children: children),
  );
}

/// One action row in the pane. LEFT hands focus back to the rail; everything
/// else is ordinary vertical traversal.
class _PaneRow extends StatefulWidget {
  const _PaneRow({
    required this.focusNode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
    required this.onLeft,
    this.danger = false,
    this.isLast = false,
  });

  final FocusNode? focusNode;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback onLeft;
  final bool danger;
  final bool isLast;

  @override
  State<_PaneRow> createState() => _PaneRowState();
}

class _PaneRowState extends State<_PaneRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tint = widget.danger ? kSettingsRed : kSettingsAccent2;
    return Focus(
      focusNode: widget.focusNode,
      canRequestFocus: widget.onTap != null,
      descendantsAreFocusable: false,
      onFocusChange: (has) {
        if (!mounted) return;
        setState(() => _focused = has);
        if (has) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: Duration.zero,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowLeft:
            widget.onLeft();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.select:
          case LogicalKeyboardKey.space:
            widget.onTap?.call();
            return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        // Same reason as the rail: the row's padding must be clickable.
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null
            ? null
            : () {
                widget.focusNode?.requestFocus();
                widget.onTap!();
              },
        child: MouseRegion(
          cursor: widget.onTap == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: _focused ? kSettingsPanel2 : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focused ? kSettingsAccent : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 20, color: tint),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: widget.danger ? kSettingsRed : null,
                        ),
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle!,
                          style: TextStyle(fontSize: 12, color: kSettingsDim),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: 12),
                  // The row is the single target for both DPAD and pointer:
                  // a Switch/Radio here would otherwise take the tap itself
                  // and fire the action a second time.
                  IgnorePointer(child: widget.trailing!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodCard extends StatefulWidget {
  const _MethodCard({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
    required this.onLeft,
    required this.onRight,
    required this.onDown,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLeft;
  final VoidCallback? onRight;
  final VoidCallback onDown;

  @override
  State<_MethodCard> createState() => _MethodCardState();
}

class _MethodCardState extends State<_MethodCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (has) {
        if (mounted) setState(() => _focused = has);
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowLeft:
            widget.onLeft();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowRight:
            if (widget.onRight == null) return KeyEventResult.handled;
            widget.onRight!();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowDown:
            widget.onDown();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.select:
          case LogicalKeyboardKey.space:
            widget.onTap();
            return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        // Same reason as the rail: the whole card is the target.
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.focusNode.requestFocus();
          widget.onTap();
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: _focused
                  ? kSettingsPanel2
                  : (widget.selected ? kSettingsPanel : null),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: _focused
                    ? kSettingsAccent
                    : (widget.selected ? kSettingsAccent2 : kSettingsLine),
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Icon(widget.icon, size: 24, color: kSettingsAccent2),
                const SizedBox(height: 9),
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.hint,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(fontSize: 11.5, color: kSettingsDim),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
