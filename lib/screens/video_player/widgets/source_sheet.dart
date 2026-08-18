import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/torrent.dart';
import '../../../services/series_source_fetcher.dart';
import '../../../utils/platform_util.dart';
import '../../../utils/tv_keys.dart';

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
  final GlobalKey _loadMoreKey = GlobalKey();

  List<_AddonGroup> _groups = const [];
  int _selectedGroup = 0;
  int _focusedSource = 0;
  _FocusZone _focusZone = _FocusZone.sources;
  int? _resolvingIndex;
  String? _errorMessage;
  String? _loadingMode;

  @override
  void initState() {
    super.initState();
    _rebuildGroups(landOnCurrent: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
        _ensureFocusedVisible();
      }
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
    _groups = <_AddonGroup>[
      _AddonGroup('all', 'All add-ons', all),
      for (final bucket in buckets.entries)
        _AddonGroup(bucket.key, labels[bucket.key]!, bucket.value),
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

  String? get _loadMoreMode {
    final fetcher = widget.seriesFetcher;
    if (fetcher == null) return null;
    if (fetcher.isMovie) {
      return fetcher.movieFetched ? null : SeriesSourceFetcher.modeMovie;
    }
    if (!fetcher.packsFetched) return SeriesSourceFetcher.modePacks;
    if (!fetcher.episodesFetched) return SeriesSourceFetcher.modeEpisodes;
    return null;
  }

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

  String get _loadMoreLabel => switch (_loadMoreMode) {
    SeriesSourceFetcher.modeEpisodes => 'Load episode sources',
    SeriesSourceFetcher.modePacks => 'Load season-pack sources',
    _ => 'Load more sources',
  };

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

  void _ensureFocusedVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final GlobalKey? key = _focusedSource < 0
          ? _loadMoreKey
          : _sourceKeys[_focusedEntry?.originalIndex];
      final context = key?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
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
        _sourceScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        );
      }
    });
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

  Future<void> _loadMore() async {
    final mode = _loadMoreMode;
    final fetcher = widget.seriesFetcher;
    if (mode == null || fetcher == null || _loadingMode != null) return;
    setState(() {
      _loadingMode = mode;
      _errorMessage = null;
    });
    List<Torrent>? fetched;
    try {
      fetched = await fetcher.fetch(
        mode,
        season: widget.currentSeason,
        episode: widget.currentEpisode,
      );
    } catch (_) {}
    if (fetched != null) {
      widget.onSourcesMerged?.call(
        SeriesSourceFetcher.mergeSources(widget.sources, fetched),
      );
      if (mounted) setState(() => _loadingMode = null);
      return;
    }
    if (!mounted) return;
    setState(() {
      _loadingMode = null;
      _errorMessage = "Couldn't fetch more sources — try again";
    });
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
      final minimum = _loadMoreMode == null ? 0 : -1;
      if (_focusedSource > minimum) {
        setState(() => _focusedSource--);
        _ensureFocusedVisible();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_focusedSource < _visibleEntries.length - 1) {
        setState(() => _focusedSource++);
        _ensureFocusedVisible();
      }
    } else if (isActivateKey(event.logicalKey)) {
      if (_focusedSource < 0) {
        _loadMore();
      } else {
        final entry = _focusedEntry;
        if (entry != null) _selectSource(entry);
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
                _groups.isEmpty ? 'All add-ons' : _groups[_selectedGroup].label,
              ),
            ),
            Text('${_visibleEntries.length} sources', style: _mutedStyle),
            const SizedBox(width: 14),
            _buildCloseButton(),
          ],
        ),
        const SizedBox(height: 20),
        Text(_seriesStateLabel, style: _noteStyle),
        if (_loadMoreMode != null) ...[
          const SizedBox(height: 12),
          _LoadMoreRow(
            key: _loadMoreKey,
            label: _loadingMode == null ? _loadMoreLabel : 'Loading sources…',
            focused: _focusZone == _FocusZone.sources && _focusedSource < 0,
            enabled: _loadingMode == null,
            onTap: _loadMore,
          ),
        ],
        const SizedBox(height: 14),
        if (_errorMessage != null) _ErrorBanner(message: _errorMessage!),
        Expanded(
          child: _visibleEntries.isEmpty
              ? Center(
                  child: Text(
                    'No sources from this add-on',
                    style: _mutedStyle,
                  ),
                )
              : ListView.builder(
                  controller: _sourceScrollController,
                  itemCount: _visibleEntries.length,
                  itemBuilder: (context, index) {
                    final entry = _visibleEntries[index];
                    return KeyedSubtree(
                      key: _sourceKeys.putIfAbsent(
                        entry.originalIndex,
                        GlobalKey.new,
                      ),
                      child: _SourceRow(
                        entry: entry,
                        current:
                            entry.originalIndex == widget.currentSourceIndex,
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
                    );
                  },
                ),
        ),
      ],
    ),
  );

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
  final bool selected;
  final bool focused;
  final VoidCallback onTap;
  const _AddonRailRow({
    required this.label,
    required this.count,
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
                label == 'All add-ons'
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
              '$count',
              style: TextStyle(
                color: inverse
                    ? Colors.black.withValues(alpha: .55)
                    : Colors.white.withValues(alpha: .42),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadMoreRow extends StatelessWidget {
  final String label;
  final bool focused;
  final bool enabled;
  final VoidCallback onTap;
  const _LoadMoreRow({
    super.key,
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
  Widget build(BuildContext context) {
    final torrent = entry.torrent;
    final inverse = focused;
    final tags = <String>[
      if (torrent.streamType == StreamType.directUrl) 'DIRECT',
      if (torrent.sizeBytes > 0) _formatSize(torrent.sizeBytes),
      if (!torrent.isDirectStream && torrent.seeders > 0)
        '${torrent.seeders} seeders',
    ];
    final quality = _quality(torrent.displayTitle);
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
        child: Row(
          children: [
            Expanded(
              child: Text(
                torrent.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: inverse
                      ? Colors.black
                      : Colors.white.withValues(alpha: .86),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 14),
            if (quality != null)
              _Pill(label: quality, inverse: inverse, emphasis: true),
            for (final tag in tags) ...[
              const SizedBox(width: 6),
              _Pill(label: tag, inverse: inverse),
            ],
            const SizedBox(width: 14),
            if (resolving)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: inverse ? Colors.black : Colors.white70,
                ),
              )
            else if (current)
              Text(
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
              ),
          ],
        ),
      ),
    );
  }

  static String? _quality(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('2160') ||
        lower.contains('4k') ||
        lower.contains('uhd')) {
      return '4K';
    }
    if (lower.contains('1080')) return '1080P';
    if (lower.contains('720')) return '720P';
    return null;
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
