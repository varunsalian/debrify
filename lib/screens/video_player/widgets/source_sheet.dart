import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../models/torrent.dart';
import '../../../services/series_source_fetcher.dart';
import '../../../services/stream_badges_service.dart';
import '../../../utils/platform_util.dart';
import '../../../utils/source_quality.dart';
import '../../../utils/tv_keys.dart';
import '../../../widgets/stream_badge_strip.dart';

/// Full-screen source browser.  It deliberately keeps the source list in its
/// supplied order: grouping is only a view over the list, never a re-rank.
class SourceSheet extends StatefulWidget {
  final List<Torrent> sources;
  final int currentSourceIndex;
  final Future<String?> Function(Torrent) resolveSource;
  final void Function(int index, String resolvedUrl) onSourceSelected;
  final VoidCallback onClose;
  final SeriesSourceFetcher? seriesFetcher;
  final int? currentSeason;
  final int? currentEpisode;
  final void Function(List<Torrent> merged)? onSourcesMerged;

  const SourceSheet({
    super.key,
    required this.sources,
    required this.currentSourceIndex,
    required this.resolveSource,
    required this.onSourceSelected,
    required this.onClose,
    this.seriesFetcher,
    this.currentSeason,
    this.currentEpisode,
    this.onSourcesMerged,
  });

  @override
  State<SourceSheet> createState() => _SourceSheetState();
}

enum _FocusZone { addons, sources, close }

class _SourceEntry {
  final int originalIndex;
  final Torrent torrent;
  const _SourceEntry(this.originalIndex, this.torrent);
}

class _AddonGroup {
  final String id;
  final String label;
  final List<_SourceEntry> entries;
  const _AddonGroup(this.id, this.label, this.entries);
}

class _SourceSheetState extends State<SourceSheet> {
  static const _glass = Color(0xFF101012);

  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'source-browser');
  final ScrollController _addonScrollController = ScrollController();
  final ScrollController _sourceScrollController = ScrollController();
  final Map<int, GlobalKey> _sourceKeys = <int, GlobalKey>{};

  List<_AddonGroup> _groups = const [];
  int _selectedGroup = 0;
  int _focusedSource = 0;
  _FocusZone _focusZone = _FocusZone.sources;
  bool _sourceScrollManuallyControlled = false;
  bool _sourceFocusAnimationActive = false;
  int _sourceFocusAnimationRun = 0;
  double _pendingSourceHeightDelta = 0;
  bool _sourceHeightCorrectionScheduled = false;
  int? _resolvingIndex;
  String? _errorMessage;

  /// Every applicable addon for this play — placeholder rail groups are built
  /// from these, so an addon with zero results still shows (with a "Fetch
  /// results" row) instead of being invisible.
  List<SourceAddonRef> _allAddons = const [];
  List<SourceEngineRef> _allEngines = const [];

  /// Group id → ALL addon ids sharing it. Group identity must stay the
  /// name-derived sourceKey (fetched rows carry `stremio:<name>` and nothing
  /// else), so two same-named addons share one group — the fetch then asks
  /// every addon in it rather than silently dropping all but the first.
  final Map<String, List<String>> _addonIdsByGroup = {};
  final Map<String, String> _engineIdByGroup = {};

  /// Per-group fetch state: episode fetch in flight / lazy pack probe in
  /// flight / last fetch failed (the group's Fetch row doubles as retry).
  final Set<String> _fetchingGroups = {};
  final Set<String> _packProbing = {};
  final Set<String> _failedGroups = {};
  final Set<String> _fetchedGroups = {};

  @override
  void initState() {
    super.initState();
    _rebuildGroups(landOnCurrent: true);
    _loadAddonListing();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
        _ensureFocusedVisible();
      }
    });
  }

  Future<void> _loadAddonListing() async {
    final addonListing = widget.seriesFetcher?.listAddons;
    final engineListing = widget.seriesFetcher?.listEngines;
    if (addonListing == null && engineListing == null) {
      return;
    }
    Future<List<SourceAddonRef>> loadAddons() async {
      try {
        return await addonListing?.call() ?? const [];
      } catch (_) {
        return const [];
      }
    }

    Future<List<SourceEngineRef>> loadEngines() async {
      try {
        return await engineListing?.call() ?? const [];
      } catch (_) {
        return const [];
      }
    }

    final addonsFuture = loadAddons();
    final enginesFuture = loadEngines();
    final addons = await addonsFuture;
    final engines = await enginesFuture;
    if (!mounted) return;
    setState(() {
      _allAddons = addons;
      _allEngines = engines;
      final selectedId = _groups.isEmpty ? 'all' : _groups[_selectedGroup].id;
      final focusedOriginal = _focusedEntry?.originalIndex;
      _rebuildGroups(selectedId: selectedId, focusedOriginal: focusedOriginal);
    });
  }

  @override
  void didUpdateWidget(SourceSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sources, widget.sources) ||
        oldWidget.currentSourceIndex != widget.currentSourceIndex) {
      final focusedOriginal = _focusedEntry?.originalIndex;
      final selectedId = _groups.isEmpty ? 'all' : _groups[_selectedGroup].id;
      _rebuildGroups(selectedId: selectedId, focusedOriginal: focusedOriginal);
    }
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    _addonScrollController.dispose();
    _sourceScrollController.dispose();
    super.dispose();
  }

  String _groupId(Torrent torrent) {
    final source = torrent.source.trim();
    return source.isEmpty ? '_other' : source.toLowerCase();
  }

  String _groupLabel(Torrent torrent) {
    var source = torrent.source.trim();
    if (source.isEmpty) return 'Other sources';
    // The title-level binding (torrent_playback_service._torrentFromSource).
    if (source.toLowerCase() == 'pinned') return 'Pinned source';
    if (source.toLowerCase().startsWith('stremio:')) {
      source = source.substring('stremio:'.length);
    }
    return source
        .split(RegExp(r'[_-]'))
        .map((word) {
          if (word.isEmpty) return word;
          return '${word[0].toUpperCase()}${word.substring(1)}';
        })
        .join(' ');
  }

  void _rebuildGroups({
    bool landOnCurrent = false,
    String? selectedId,
    int? focusedOriginal,
  }) {
    final all = <_SourceEntry>[];
    final buckets = <String, List<_SourceEntry>>{};
    final labels = <String, String>{};
    for (var index = 0; index < widget.sources.length; index++) {
      final entry = _SourceEntry(index, widget.sources[index]);
      all.add(entry);
      final id = _groupId(entry.torrent);
      (buckets[id] ??= <_SourceEntry>[]).add(entry);
      labels.putIfAbsent(id, () => _groupLabel(entry.torrent));
    }
    // Placeholder groups for applicable addons with no results yet — the
    // group id is the addon's sourceKey, so its fetched rows land in the
    // same bucket the placeholder occupied. Same-named addons share one
    // placeholder (the set guard), never two duplicate groups.
    _addonIdsByGroup.clear();
    _engineIdByGroup.clear();
    for (final addon in _allAddons) {
      (_addonIdsByGroup[addon.sourceKey] ??= <String>[]).add(addon.id);
    }
    for (final engine in _allEngines) {
      _engineIdByGroup[engine.sourceKey] = engine.id;
    }
    final placeholderKeys = <String>{};
    _groups = <_AddonGroup>[
      _AddonGroup('all', 'All sources', all),
      for (final bucket in buckets.entries)
        _AddonGroup(bucket.key, labels[bucket.key]!, bucket.value),
      for (final engine in _allEngines)
        if (!buckets.containsKey(engine.sourceKey) &&
            placeholderKeys.add(engine.sourceKey))
          _AddonGroup(engine.sourceKey, engine.name, const <_SourceEntry>[]),
      for (final addon in _allAddons)
        if (!buckets.containsKey(addon.sourceKey) &&
            placeholderKeys.add(addon.sourceKey))
          _AddonGroup(addon.sourceKey, addon.name, const <_SourceEntry>[]),
    ];
    final nextGroup = _groups.indexWhere((g) => g.id == selectedId);
    _selectedGroup = nextGroup < 0 ? 0 : nextGroup;
    final target =
        focusedOriginal ?? (landOnCurrent ? widget.currentSourceIndex : null);
    final idx = target == null
        ? -1
        : _visibleEntries.indexWhere((entry) => entry.originalIndex == target);
    _focusedSource = idx < 0 ? 0 : idx;
  }

  List<_SourceEntry> get _visibleEntries => _groups.isEmpty
      ? const <_SourceEntry>[]
      : _groups[_selectedGroup].entries;

  _SourceEntry? get _focusedEntry =>
      _focusedSource >= 0 && _focusedSource < _visibleEntries.length
      ? _visibleEntries[_focusedSource]
      : null;

  String get _seriesStateLabel {
    final fetcher = widget.seriesFetcher;
    if (fetcher == null || fetcher.isMovie) {
      return 'Sources returned for this title.';
    }
    final hasPacks = _visibleEntries.any((e) => _isPack(e.torrent));
    final hasEpisodes = _visibleEntries.any(
      (e) => e.torrent.streamType == StreamType.torrent && !_isPack(e.torrent),
    );
    if (hasPacks && hasEpisodes) {
      return 'Season packs and episode results loaded.';
    }
    if (hasPacks) {
      return 'Season packs loaded. Episode results are fetched separately.';
    }
    if (hasEpisodes) {
      return 'Episode results loaded. Season packs are fetched separately.';
    }
    return 'Sources returned for this series.';
  }

  static bool _isPack(Torrent torrent) =>
      torrent.coverageType == 'seasonPack' ||
      torrent.coverageType == 'multiSeasonPack' ||
      torrent.coverageType == 'completeSeries';

  void _selectGroup(int index) {
    setState(() {
      _selectedGroup = index;
      final current = _visibleEntries.indexWhere(
        (entry) => entry.originalIndex == widget.currentSourceIndex,
      );
      _focusedSource = current < 0 ? 0 : current;
    });
    _ensureAddonVisible();
    _ensureFocusedVisible();
  }

  // Rows above the selection can grow after asynchronous badge matching.
  // Compensate by their actual height deltas: an estimated index offset or
  // ensureVisible cannot find a selected lazy child already pushed off-screen.
  void _sourceHeightChanged(int index, double delta) {
    if (_sourceScrollManuallyControlled ||
        _focusZone != _FocusZone.sources ||
        index > _focusedSource ||
        (index == _focusedSource && !_sourceFocusAnimationActive)) {
      return;
    }
    if (index < _focusedSource) _pendingSourceHeightDelta += delta;
    if (_sourceHeightCorrectionScheduled) return;
    _sourceHeightCorrectionScheduled = true;
    final selection = _focusedEntry?.originalIndex;
    final group = _groups[_selectedGroup].id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sourceHeightCorrectionScheduled = false;
      final correction = _pendingSourceHeightDelta;
      _pendingSourceHeightDelta = 0;
      if (!mounted ||
          !_sourceScrollController.hasClients ||
          _sourceScrollManuallyControlled ||
          _focusZone != _FocusZone.sources ||
          selection != _focusedEntry?.originalIndex ||
          group != _groups[_selectedGroup].id) {
        return;
      }
      final position = _sourceScrollController.position;
      final resumeFocusAnimation = _sourceFocusAnimationActive;
      if (resumeFocusAnimation) ++_sourceFocusAnimationRun;
      _sourceScrollController.jumpTo(
        (position.pixels + correction).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      if (resumeFocusAnimation) {
        // The correction can remount a selected lazy row. Once laid out,
        // resume navigation toward its new position instead of stopping short.
        _ensureFocusedVisible();
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    });
  }

  void _ensureFocusedVisible() {
    _sourceScrollManuallyControlled = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _alignFocusedSource());
  }

  Future<void> _alignFocusedSource() async {
    if (!mounted || _sourceScrollManuallyControlled) {
      _sourceFocusAnimationActive = false;
      return;
    }
    final run = ++_sourceFocusAnimationRun;
    _sourceFocusAnimationActive = true;
    try {
      final context = _sourceKeys[_focusedEntry?.originalIndex]?.currentContext;
      if (context != null) {
        await Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          alignment: 0.45,
        );
      } else if (_sourceScrollController.hasClients && _focusedSource >= 0) {
        final target = (_focusedSource * 63.0).clamp(
          0.0,
          _sourceScrollController.position.maxScrollExtent,
        );
        await _sourceScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        );
      }
    } finally {
      if (run == _sourceFocusAnimationRun) _sourceFocusAnimationActive = false;
    }
  }

  void _ensureAddonVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_addonScrollController.hasClients) return;
      final horizontal =
          _addonScrollController.position.axisDirection ==
              AxisDirection.right ||
          _addonScrollController.position.axisDirection == AxisDirection.left;
      final extent = horizontal ? 150.0 : 47.0;
      _addonScrollController.animateTo(
        (_selectedGroup * extent).clamp(
          0.0,
          _addonScrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _selectSource(_SourceEntry entry) async {
    if (entry.originalIndex == widget.currentSourceIndex ||
        _resolvingIndex != null) {
      return;
    }
    setState(() {
      _resolvingIndex = entry.originalIndex;
      _errorMessage = null;
    });
    try {
      final url = await widget.resolveSource(entry.torrent);
      if (!mounted) return;
      if (url != null && url.isNotEmpty) {
        widget.onSourceSelected(entry.originalIndex, url);
      } else {
        await _showResolutionError(
          'Source unavailable — not cached or not a video',
        );
      }
    } catch (_) {
      if (mounted) await _showResolutionError('Failed to resolve source');
    }
  }

  Future<void> _showResolutionError(String message) async {
    if (!mounted) return;
    setState(() {
      _resolvingIndex = null;
      _errorMessage = message;
    });
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted && _resolvingIndex == null) {
      setState(() => _errorMessage = null);
    }
  }

  /// Whether the selected group is an empty addon group whose per-addon
  /// fetch is available — the state that renders the "Fetch results" row.
  bool get _groupFetchAvailable {
    if (_groups.isEmpty) return false;
    final group = _groups[_selectedGroup];
    return group.entries.isEmpty &&
        ((_addonIdsByGroup.containsKey(group.id) &&
                widget.seriesFetcher?.fetchAddonEpisodes != null) ||
            (_engineIdByGroup.containsKey(group.id) &&
                widget.seriesFetcher?.fetchEngine != null));
  }

  /// Per-addon fetch: episode results first — they render the instant the
  /// merge lands, direct links included — then, ONLY when they contained a
  /// torrent magnet, the lazy season-pack probe (a direct-link-only addon
  /// has no packs to find). A null fetch marks the group failed and keeps
  /// the Fetch row up as the retry.
  Future<void> _fetchAddonGroup() async {
    final fetcher = widget.seriesFetcher;
    if (fetcher == null || _groups.isEmpty) return;
    final group = _groups[_selectedGroup];
    final engineId = _engineIdByGroup[group.id];
    if (engineId != null) {
      if (_fetchingGroups.contains(group.id)) return;
      setState(() {
        _fetchingGroups.add(group.id);
        _failedGroups.remove(group.id);
      });
      final fetched = await fetcher.fetchEngine?.call(
        engineId,
        widget.currentSeason ?? fetcher.season,
        widget.currentEpisode ?? fetcher.episode,
      );
      if (!mounted) return;
      setState(() {
        _fetchingGroups.remove(group.id);
        if (fetched == null) {
          _failedGroups.add(group.id);
        } else {
          _fetchedGroups.add(group.id);
        }
      });
      if (fetched != null && fetched.isNotEmpty) {
        widget.onSourcesMerged?.call(
          SeriesSourceFetcher.mergeSources(widget.sources, fetched),
        );
      }
      return;
    }
    final search = fetcher.fetchAddonEpisodes;
    if (search == null) return;
    final addonIds = _addonIdsByGroup[group.id];
    if (addonIds == null ||
        addonIds.isEmpty ||
        _fetchingGroups.contains(group.id)) {
      return;
    }
    setState(() {
      _fetchingGroups.add(group.id);
      _failedGroups.remove(group.id);
      _errorMessage = null;
    });
    final s = widget.currentSeason ?? fetcher.season;
    final e = widget.currentEpisode ?? fetcher.episode;
    // Every addon sharing this group's name. Failed only when ALL failed —
    // a partial success is results the user asked for. Track which ids
    // returned magnets: only THOSE earn the pack probe (a direct-only or
    // empty sibling has no packs to find).
    List<Torrent>? episodes;
    final magnetIds = <String>[];
    for (final addonId in addonIds) {
      final fetched = await search(addonId, s, e);
      if (fetched != null) {
        (episodes ??= <Torrent>[]).addAll(fetched);
        if (fetched.any((t) => t.streamType == StreamType.torrent)) {
          magnetIds.add(addonId);
        }
      }
    }
    if (!mounted) return;
    if (episodes == null) {
      setState(() {
        _fetchingGroups.remove(group.id);
        _failedGroups.add(group.id);
      });
      return;
    }
    setState(() {
      _fetchingGroups.remove(group.id);
      _fetchedGroups.add(group.id);
    });
    var afterEpisodes = widget.sources;
    if (episodes.isNotEmpty) {
      afterEpisodes = SeriesSourceFetcher.mergeSources(
        widget.sources,
        episodes,
      );
      widget.onSourcesMerged?.call(afterEpisodes);
    }
    final packSearch = fetcher.fetchAddonPacks;
    if (fetcher.isMovie || packSearch == null || magnetIds.isEmpty) return;
    setState(() => _packProbing.add(group.id));
    List<Torrent>? packs;
    for (final addonId in magnetIds) {
      final fetched = await packSearch(addonId, s);
      if (fetched != null) (packs ??= <Torrent>[]).addAll(fetched);
    }
    if (!mounted) return;
    setState(() => _packProbing.remove(group.id));
    if (packs != null && packs.isNotEmpty) {
      // widget.sources only adopts the episode merge after the parent's
      // rebuild, and a fast pack probe can win that race (another merge —
      // a load-more, a second addon fetch — can also land in between).
      // Fold the episode result in again before appending packs: merge is
      // append-only and dedupes, so whichever list is fresher survives
      // intact and nothing is clobbered.
      widget.onSourcesMerged?.call(
        SeriesSourceFetcher.mergeSources(
          SeriesSourceFetcher.mergeSources(widget.sources, afterEpisodes),
          packs,
        ),
      );
    }
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      TvOverlayBack.mark();
      widget.onClose();
      return;
    }
    if (_focusZone == _FocusZone.close) {
      if (isActivateKey(event.logicalKey)) {
        TvOverlayBack.mark();
        widget.onClose();
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() => _focusZone = _FocusZone.sources);
        _ensureFocusedVisible();
      }
      return;
    }
    if (_focusZone == _FocusZone.addons) {
      final compact = MediaQuery.sizeOf(context).width < 700;
      final previousKey = compact
          ? LogicalKeyboardKey.arrowLeft
          : LogicalKeyboardKey.arrowUp;
      final nextKey = compact
          ? LogicalKeyboardKey.arrowRight
          : LogicalKeyboardKey.arrowDown;
      final exitKey = compact
          ? LogicalKeyboardKey.arrowDown
          : LogicalKeyboardKey.arrowRight;
      if (event.logicalKey == previousKey && _selectedGroup > 0) {
        _selectGroup(_selectedGroup - 1);
      } else if (event.logicalKey == nextKey &&
          _selectedGroup < _groups.length - 1) {
        _selectGroup(_selectedGroup + 1);
      } else if (event.logicalKey == exitKey ||
          isActivateKey(event.logicalKey)) {
        setState(() => _focusZone = _FocusZone.sources);
        _ensureFocusedVisible();
      }
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      setState(() => _focusZone = _FocusZone.addons);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      setState(() => _focusZone = _FocusZone.close);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_focusedSource > 0) {
        setState(() => _focusedSource--);
        _ensureFocusedVisible();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_focusedSource < _visibleEntries.length - 1) {
        setState(() => _focusedSource++);
        _ensureFocusedVisible();
      }
    } else if (isActivateKey(event.logicalKey)) {
      final entry = _focusedEntry;
      if (entry != null) {
        _selectSource(entry);
      } else if (_groupFetchAvailable) {
        // Empty addon group: the sole focusable row is "Fetch results".
        _fetchAddonGroup();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final useBlur = !PlatformUtil.isAndroidTvCached;
    final shell = LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        return Container(
          color: useBlur
              ? _glass.withValues(alpha: .88)
              : const Color(0xF5101012),
          child: SafeArea(
            child: compact
                ? Column(
                    children: [
                      SizedBox(
                        height: 104,
                        child: _buildAddonRail(compact: true),
                      ),
                      Container(
                        height: .75,
                        color: Colors.white.withValues(alpha: .12),
                      ),
                      Expanded(child: _buildResults(compact: true)),
                    ],
                  )
                : Row(
                    children: [
                      SizedBox(width: 300, child: _buildAddonRail()),
                      Container(
                        width: .75,
                        color: Colors.white.withValues(alpha: .12),
                      ),
                      Expanded(child: _buildResults()),
                    ],
                  ),
          ),
        );
      },
    );
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: widget.onClose,
            child: const ColoredBox(color: Color(0xA6000000)),
          ),
          Positioned.fill(
            child: useBlur
                ? BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                    child: shell,
                  )
                : shell,
          ),
        ],
      ),
    );
  }

  Widget _buildAddonRail({bool compact = false}) => Padding(
    padding: compact
        ? const EdgeInsets.fromLTRB(18, 14, 18, 10)
        : const EdgeInsets.fromLTRB(30, 46, 30, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Sources'),
        SizedBox(height: compact ? 8 : 18),
        Expanded(
          child: ListView.builder(
            controller: _addonScrollController,
            scrollDirection: compact ? Axis.horizontal : Axis.vertical,
            itemCount: _groups.length,
            itemBuilder: (context, index) {
              final group = _groups[index];
              final selected = index == _selectedGroup;
              final focused = selected && _focusZone == _FocusZone.addons;
              return SizedBox(
                width: compact ? 146 : null,
                child: _AddonRailRow(
                  label: group.label,
                  count: group.entries.length,
                  failed: _failedGroups.contains(group.id),
                  selected: selected,
                  focused: focused,
                  onTap: () {
                    _selectGroup(index);
                    setState(() => _focusZone = _FocusZone.addons);
                  },
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _buildResults({bool compact = false}) => Padding(
    padding: compact
        ? const EdgeInsets.fromLTRB(18, 18, 18, 18)
        : const EdgeInsets.fromLTRB(56, 46, 56, 34),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _sectionLabel(
                _groups.isEmpty ? 'All sources' : _groups[_selectedGroup].label,
              ),
            ),
            Text('${_visibleEntries.length} sources', style: _mutedStyle),
            const SizedBox(width: 14),
            _buildCloseButton(),
          ],
        ),
        const SizedBox(height: 20),
        Text(_seriesStateLabel, style: _noteStyle),
        if (_groups.isNotEmpty &&
            _packProbing.contains(_groups[_selectedGroup].id)) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
              const SizedBox(width: 8),
              Text(
                'Looking for season packs from this add-on…',
                style: _mutedStyle,
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        if (_errorMessage != null) _ErrorBanner(message: _errorMessage!),
        Expanded(
          child: _visibleEntries.isEmpty
              ? (_groupFetchAvailable
                    ? _buildGroupFetch()
                    : Center(
                        child: Text(
                          'No sources from this add-on',
                          style: _mutedStyle,
                        ),
                      ))
              : NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if ((notification is UserScrollNotification &&
                            notification.direction != ScrollDirection.idle) ||
                        (notification is ScrollStartNotification &&
                            notification.dragDetails != null)) {
                      // Keep touch/wheel users in charge until keyboard
                      // navigation explicitly returns to the selection.
                      _sourceScrollManuallyControlled = true;
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _sourceScrollController,
                    itemCount: _visibleEntries.length,
                    itemBuilder: (context, index) {
                      final entry = _visibleEntries[index];
                      return KeyedSubtree(
                        key: _sourceKeys.putIfAbsent(
                          entry.originalIndex,
                          GlobalKey.new,
                        ),
                        child: _SourceHeightObserver(
                          onChanged: (delta) =>
                              _sourceHeightChanged(index, delta),
                          child: _SourceRow(
                            entry: entry,
                            current:
                                entry.originalIndex ==
                                widget.currentSourceIndex,
                            focused:
                                _focusZone == _FocusZone.sources &&
                                _focusedSource == index,
                            resolving: _resolvingIndex == entry.originalIndex,
                            onTap: () {
                              setState(() {
                                _focusZone = _FocusZone.sources;
                                _focusedSource = index;
                              });
                              _selectSource(entry);
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    ),
  );

  /// The empty addon group's body: one "Fetch results" row (also the retry
  /// after a failure or an empty fetch) plus a one-line explanation.
  Widget _buildGroupFetch() {
    final group = _groups[_selectedGroup];
    final fetching = _fetchingGroups.contains(group.id);
    final failed = _failedGroups.contains(group.id);
    final fetched = _fetchedGroups.contains(group.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProviderFetchRow(
          label: fetching
              ? 'Fetching episode results…'
              : failed
              ? 'Fetch failed — try again'
              : 'Fetch results',
          focused: _focusZone == _FocusZone.sources && _focusedSource >= 0,
          enabled: !fetching,
          onTap: _fetchAddonGroup,
        ),
        const SizedBox(height: 10),
        Text(
          failed
              ? "This provider couldn't be reached."
              : fetched
              ? 'This provider returned nothing for this episode.'
              : "This provider hasn't been asked yet for this episode.",
          style: _mutedStyle,
        ),
      ],
    );
  }

  Widget _sectionLabel(String label) => Text(
    label.toUpperCase(),
    style: const TextStyle(
      color: Color(0x70FFFFFF),
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 2,
    ),
  );

  Widget _buildCloseButton() => GestureDetector(
    key: const ValueKey('source-sheet-close'),
    onTap: widget.onClose,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _focusZone == _FocusZone.close
            ? Colors.white
            : Colors.white.withValues(alpha: .08),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
      ),
      child: Icon(
        Icons.close_rounded,
        size: 22,
        color: _focusZone == _FocusZone.close
            ? Colors.black
            : Colors.white.withValues(alpha: .82),
      ),
    ),
  );

  static final _mutedStyle = TextStyle(
    color: Colors.white.withValues(alpha: .42),
    fontSize: 12,
  );
  static final _noteStyle = TextStyle(
    color: Colors.white.withValues(alpha: .55),
    fontSize: 13,
    height: 1.35,
  );
}

class _AddonRailRow extends StatelessWidget {
  final String label;
  final int count;
  final bool failed;
  final bool selected;
  final bool focused;
  final VoidCallback onTap;
  const _AddonRailRow({
    required this.label,
    required this.count,
    this.failed = false,
    required this.selected,
    required this.focused,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final inverse = focused;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: inverse
              ? Colors.white
              : selected
              ? Colors.white.withValues(alpha: .10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: inverse
                    ? Colors.black.withValues(alpha: .10)
                    : Colors.white.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label == 'All sources'
                    ? '✦'
                    : label.characters.first.toUpperCase(),
                style: TextStyle(
                  color: inverse
                      ? Colors.black
                      : Colors.white.withValues(alpha: .76),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: inverse
                      ? Colors.black
                      : Colors.white.withValues(alpha: .82),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              failed && count == 0 ? '!' : '$count',
              style: TextStyle(
                color: failed && count == 0
                    ? const Color(0xFFE57373)
                    : inverse
                    ? Colors.black.withValues(alpha: .55)
                    : Colors.white.withValues(alpha: .42),
                fontSize: 11,
                fontWeight: failed && count == 0 ? FontWeight.w800 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderFetchRow extends StatelessWidget {
  final String label;
  final bool focused;
  final bool enabled;
  final VoidCallback onTap;
  const _ProviderFetchRow({
    required this.label,
    required this.focused,
    required this.enabled,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: focused ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: focused
                    ? Colors.black
                    : Colors.white.withValues(alpha: enabled ? .82 : .42),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: focused ? Colors.black : Colors.white.withValues(alpha: .60),
          ),
        ],
      ),
    ),
  );
}

class _SourceRow extends StatelessWidget {
  final _SourceEntry entry;
  final bool current;
  final bool focused;
  final bool resolving;
  final VoidCallback onTap;
  const _SourceRow({
    required this.entry,
    required this.current,
    required this.focused,
    required this.resolving,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: StreamBadgesService.instance.matcher,
    builder: (_, matcher, __) => _buildRow(!matcher.isEmpty),
  );

  Widget _buildRow(bool customBadgesConfigured) {
    final torrent = entry.torrent;
    final inverse = focused;
    final tags = <String>[
      if (torrent.streamType == StreamType.directUrl) 'DIRECT',
      if (torrent.sizeBytes > 0) _formatSize(torrent.sizeBytes),
      if (!torrent.isDirectStream && torrent.seeders > 0)
        '${torrent.seeders} seeders',
    ];
    final quality = _quality(torrent.displayTitle);
    final title = Text(
      torrent.displayTitle,
      style: TextStyle(
        color: inverse ? Colors.black : Colors.white.withValues(alpha: .86),
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
    final badges = <Widget>[
      if (!customBadgesConfigured && quality != null)
        _Pill(label: quality, inverse: inverse, emphasis: true),
      for (final tag in tags) _Pill(label: tag, inverse: inverse),
      StreamBadgeStripFor(
        name: torrent.name,
        description: torrent.badgeDescription,
        height: 24,
        spacing: 6,
      ),
    ];
    final activity = resolving
        ? SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: inverse ? Colors.black : Colors.white70,
            ),
          )
        : current
        ? Text(
            '▮▮▮',
            semanticsLabel: 'Playing',
            style: TextStyle(
              color: inverse
                  ? const Color(0xFFAB2733)
                  : const Color(0xFFE23D4C),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          )
        : null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: inverse ? Colors.white : Colors.white.withValues(alpha: .025),
          borderRadius: BorderRadius.circular(10),
          boxShadow: inverse
              ? [
                  const BoxShadow(
                    color: Color(0x73000000),
                    blurRadius: 20,
                    offset: Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: title),
                if (activity != null) ...[const SizedBox(width: 14), activity],
              ],
            ),
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 9),
              Wrap(spacing: 6, runSpacing: 6, children: badges),
            ],
          ],
        ),
      ),
    );
  }

  static String? _quality(String value) {
    return sourceQualityBadgeForName(value)?.toUpperCase();
  }

  static String _formatSize(int bytes) {
    final gb = bytes / (1024 * 1024 * 1024);
    return gb >= 1
        ? '${gb.toStringAsFixed(1)} GB'
        : '${(bytes / (1024 * 1024)).round()} MB';
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool inverse;
  final bool emphasis;
  const _Pill({
    required this.label,
    required this.inverse,
    this.emphasis = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: inverse
          ? Colors.black.withValues(alpha: emphasis ? .12 : .07)
          : Colors.white.withValues(alpha: emphasis ? .12 : .07),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: inverse
            ? Colors.black.withValues(alpha: emphasis ? .80 : .58)
            : Colors.white.withValues(alpha: emphasis ? .82 : .58),
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.red.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      message,
      style: TextStyle(color: Colors.red.withValues(alpha: .9), fontSize: 12),
    ),
  );
}

/// Reports only changes after a row's first layout, including image/badge
/// completion. Calling the owner during layout only queues a post-frame scroll.
class _SourceHeightObserver extends SingleChildRenderObjectWidget {
  const _SourceHeightObserver({required this.onChanged, required super.child});
  final ValueChanged<double> onChanged;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _SourceHeightRender(onChanged);
  @override
  void updateRenderObject(
    BuildContext context,
    _SourceHeightRender renderObject,
  ) {
    renderObject.onChanged = onChanged;
  }
}

class _SourceHeightRender extends RenderProxyBox {
  _SourceHeightRender(this.onChanged);
  ValueChanged<double> onChanged;
  double? _lastHeight;
  @override
  void performLayout() {
    super.performLayout();
    final previous = _lastHeight;
    _lastHeight = size.height;
    if (previous != null && previous != size.height) {
      onChanged(size.height - previous);
    }
  }
}
