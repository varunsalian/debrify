import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/iptv_playlist.dart';
import '../../models/playlist_view_mode.dart';
import '../../services/iptv_global_search.dart';
import '../../services/storage_service.dart';
import '../../services/video_player_launcher.dart';
import '../../utils/tv_keys.dart';
import '../../widgets/browse/brand_accent.dart';
import '../../widgets/home/home_theme.dart';
import '../../widgets/see_all/see_all_theme.dart';
import '../../widgets/tv_text_field.dart';
import 'xtream_series_detail.dart';

/// Matches a trailing resolution in a channel name, e.g. "(1080p)" — same
/// split the channel rows do (pulled into a chip, name shown clean).
final RegExp _resExp = RegExp(r'\((\d{3,4}[pi])\)', caseSensitive: false);

/// Search every IPTV source at once — all playlists, Live + Movies + Series
/// in one query. Reads the catalogs this device already has (session caches,
/// the disk snapshots the SWR layer persists, local files), so results are
/// instant and available offline; no source is contacted.
///
/// DPAD-first: the field is the in-app TV keyboard shell, DOWN drops into the
/// results, UP from the first row returns to the field, BACK pops. Grouped
/// results carry their source's name; a live hit launches with its source's
/// full channel list as zapping context, a series hit opens the merged series
/// page against its owning provider.
class IptvGlobalSearchPage extends StatefulWidget {
  final bool isTelevision;
  const IptvGlobalSearchPage({super.key, required this.isTelevision});

  @override
  State<IptvGlobalSearchPage> createState() => _IptvGlobalSearchPageState();
}

/// Flat list model for the results ListView: a section header or a hit.
class _Row {
  final String? header;
  final int? headerTotal; // true match count (may exceed what's shown)
  final int? headerShown;
  final IptvGlobalSearchHit? hit;
  final int? hitIndex; // index into the flat hit/FocusNode arrays

  const _Row.header(this.header, this.headerShown, this.headerTotal)
      : hit = null,
        hitIndex = null;
  const _Row.hit(this.hit, this.hitIndex)
      : header = null,
        headerTotal = null,
        headerShown = null;
}

class _IptvGlobalSearchPageState extends State<IptvGlobalSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchFocusNode =
      FocusNode(debugLabel: 'iptv-global-search-field');
  final ScrollController _scrollController = ScrollController();

  IptvGlobalSearchIndex? _index;
  bool _indexLoading = true;

  String _query = '';
  Timer? _debounce;
  IptvGlobalSearchResults? _results;

  /// Monotonic search id — a search may resolve on a worker isolate, so a
  /// slower earlier run must not overwrite a newer one's results.
  int _searchSeq = 0;

  /// Flat render list + one focus node per hit, in DPAD order.
  List<_Row> _rows = const [];
  final List<FocusNode> _hitNodes = [];

  /// Repeated OK on a row must not stack player launches (same latch the
  /// results view keeps).
  bool _launching = false;

  @override
  void initState() {
    super.initState();
    _loadIndex();
  }

  Future<void> _loadIndex() async {
    final index = await IptvGlobalSearchIndex.load();
    if (!mounted) return;
    setState(() {
      _index = index;
      _indexLoading = false;
    });
    // A query typed while the index was still loading should answer now.
    if (_query.isNotEmpty) _runSearch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    for (final node in _hitNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _query = value.trim();
    _debounce?.cancel();
    if (_query.isEmpty) {
      _applyResults(null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _runSearch();
    });
  }

  Future<void> _runSearch() async {
    final index = _index;
    if (index == null || _query.isEmpty) return;
    final query = _query;
    final seq = ++_searchSeq;
    final results = await index.searchAsync(query);
    // Drop stale results: a newer search started, the field moved on, or the
    // page went away while the worker ran.
    if (!mounted || seq != _searchSeq || query != _query) return;
    _applyResults(results);
  }

  void _applyResults(IptvGlobalSearchResults? results) {
    // Rebuild the flat model + focus nodes. A row CAN be focused when this
    // fires — the debounce can straddle a BACK-out of the keyboard followed
    // by DOWN onto a row, and on touch/desktop the clear (✕) button works
    // while a row holds keyboard focus. Disposing the focused node would
    // strand DPAD focus on the bare route scope, so note it and hand focus
    // back to the field afterwards.
    final hadRowFocus = _hitNodes.any((node) => node.hasFocus);
    final rows = <_Row>[];
    final hits = <IptvGlobalSearchHit>[];
    if (results != null) {
      void section(String label, List<IptvGlobalSearchHit> list, int total) {
        if (total == 0) return;
        rows.add(_Row.header(label, list.length, total));
        for (final hit in list) {
          rows.add(_Row.hit(hit, hits.length));
          hits.add(hit);
        }
      }

      section('Live channels', results.live, results.liveTotal);
      section('Movies', results.vod, results.vodTotal);
      section('Series', results.series, results.seriesTotal);
    }

    for (final node in _hitNodes) {
      node.dispose();
    }
    _hitNodes
      ..clear()
      ..addAll(List.generate(
        hits.length,
        (i) => FocusNode(debugLabel: 'iptv-global-hit-$i'),
      ));

    setState(() {
      _results = results;
      _rows = rows;
    });
    if (hadRowFocus) _searchFocusNode.requestFocus();
  }

  void _focusFirstHit() {
    if (_hitNodes.isNotEmpty) _hitNodes.first.requestFocus();
  }

  void _focusHit(int index) {
    if (index < 0) {
      _searchFocusNode.requestFocus();
    } else if (index < _hitNodes.length) {
      _hitNodes[index].requestFocus();
    }
  }

  /// Mirrors the results view's player-list cap: the whole zap list is
  /// serialized over the platform channel at launch.
  static const int _kMaxPlayerChannels = 1500;

  Future<void> _open(IptvGlobalSearchHit hit) async {
    if (_launching) return;
    _launching = true;
    try {
      final channel = hit.channel;
      if (hit.section == 'series') {
        await openXtreamSeries(
          context,
          playlist: hit.source.playlist,
          series: channel,
          isTelevision: widget.isTelevision,
        );
        return;
      }

      // On-demand plays feed the Continue-watching shelf; recorded before the
      // launch so a killed player still leaves a resumable row behind.
      if (!channel.isLive) {
        await StorageService.recordIptvWatch(
          channel.url,
          channelName: channel.name,
          logoUrl: channel.logoUrl,
          group: channel.group,
          playlistId: hit.source.playlist.id,
          httpHeaders: channel.httpHeaders,
        );
        if (!mounted) return;
      }

      // A live hit zaps within its source: hand the player the source's live
      // list (windowed like the results view) positioned on this channel.
      var channels = <IptvChannel>[channel];
      var startIndex = 0;
      if (channel.isLive) {
        final (window, idx) =
            hit.source.liveZapWindow(channel, _kMaxPlayerChannels);
        channels = window;
        startIndex = idx;
      }

      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: channel.url,
          title: channel.name,
          subtitle: channel.group ?? hit.source.playlist.name,
          viewMode: PlaylistViewMode.sorted,
          iptvChannels: channels,
          iptvStartIndex: startIndex,
          httpHeaders: channel.playbackHeaders,
        ),
      );
    } finally {
      _launching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeTheme.bg,
      body: Container(
        decoration: HomeTheme.pageBackground,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              _buildScopeLine(),
              const SizedBox(height: 4),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 20, 0),
      child: Row(
        children: [
          // BACK is the TV way out — the arrow is for touch/desktop and stays
          // off the DPAD chain so DOWN from the field can't strand on it.
          ExcludeFocus(
            excluding: widget.isTelevision,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: 'Back',
              icon: Icon(
                Icons.arrow_back_rounded,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TvTextField(
              controller: _controller,
              focusNode: _searchFocusNode,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              onChanged: _onQueryChanged,
              onSubmitted: (_) {
                _debounce?.cancel();
                _runSearch();
              },
              onDownArrow: _focusFirstHit,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search all sources…',
                hintStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                prefixIcon: Icon(
                  Icons.travel_explore_rounded,
                  color: kSeeAllAccent2.withValues(alpha: 0.8),
                ),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        onPressed: () {
                          _controller.clear();
                          _onQueryChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: kSeeAllAccent.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.07),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeLine() {
    final index = _index;
    final String text;
    if (_indexLoading) {
      text = 'Indexing saved catalogs…';
    } else if (index == null || index.sources.isEmpty) {
      text = 'Nothing indexed yet — open a source once in IPTV first';
    } else {
      final sourceNames = <String>{
        for (final s in index.sources) s.playlist.name,
      };
      final items = index.itemCount;
      text = '${sourceNames.length} source'
          '${sourceNames.length == 1 ? '' : 's'} · '
          '$items item${items == 1 ? '' : 's'} · works offline';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 8, 24, 0),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.38),
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_indexLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final results = _results;
    if (_query.isEmpty || results == null) {
      return _buildIdleState();
    }
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: Colors.white.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 14),
            Text(
              'No matches for "$_query"',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Searched every indexed source and content type',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: _rows.length,
      itemBuilder: (context, i) {
        final row = _rows[i];
        if (row.header != null) {
          final truncated = row.headerTotal! > row.headerShown!;
          return Padding(
            padding: EdgeInsets.fromLTRB(4, i == 0 ? 6 : 20, 4, 8),
            child: Row(
              children: [
                Text(
                  row.header!.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  truncated
                      ? '${row.headerShown} of ${row.headerTotal}'
                      : '${row.headerTotal}',
                  style: const TextStyle(
                    color: kSeeAllAccent2,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              ],
            ),
          );
        }
        final hit = row.hit!;
        final index = row.hitIndex!;
        return _SearchHitRow(
          hit: hit,
          focusNode: _hitNodes[index],
          isTelevision: widget.isTelevision,
          onOpen: () => _open(hit),
          onUp: () => _focusHit(index - 1),
          onDown: index + 1 < _hitNodes.length
              ? () => _focusHit(index + 1)
              : null,
        );
      },
    );
  }

  /// Empty-query state: what this search covers, source by source — and which
  /// sources it can't cover yet, with the way to fix that.
  Widget _buildIdleState() {
    final index = _index;
    if (index == null) return const SizedBox.shrink();
    final typeLabel = {
      'live': 'Live TV',
      'vod': 'Movies',
      'series': 'Series',
      'mixed': 'Playlist',
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(64, 18, 32, 24),
      children: [
        Text(
          'Search everything',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'One search across every source — live channels, movies and '
          'series together. Results come from your saved catalogs, so '
          'they appear instantly, even offline.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 12.5,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        for (final source in index.sources)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 14,
                  color: const Color(0xFF4ADE80).withValues(alpha: 0.8),
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    '${source.playlist.name} · '
                    '${typeLabel[source.contentType]}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${source.channelCount}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        for (final label in index.unindexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 14,
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.7),
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    '$label — open it once in IPTV to index it',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One search result: artwork chip, clean name, "source • category" line and
/// a resolution chip when the name declares one. Gold focus ring — the app's
/// row language.
class _SearchHitRow extends StatefulWidget {
  final IptvGlobalSearchHit hit;
  final FocusNode focusNode;
  final bool isTelevision;
  final VoidCallback onOpen;
  final VoidCallback onUp;
  final VoidCallback? onDown;

  const _SearchHitRow({
    required this.hit,
    required this.focusNode,
    required this.isTelevision,
    required this.onOpen,
    required this.onUp,
    this.onDown,
  });

  @override
  State<_SearchHitRow> createState() => _SearchHitRowState();
}

class _SearchHitRowState extends State<_SearchHitRow> {
  bool _focused = false;
  bool _hovered = false;
  bool get _active => _focused || _hovered;

  @override
  Widget build(BuildContext context) {
    final channel = widget.hit.channel;
    final poster = widget.hit.section != 'live';
    final brand = brandAccentFor(channel.name);

    final resMatch = _resExp.firstMatch(channel.name);
    final resolution = resMatch?.group(1)?.toLowerCase();
    final displayName = resMatch == null
        ? channel.name
        : channel.name
            .replaceRange(resMatch.start, resMatch.end, '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

    final group = channel.group?.trim();
    final sub = [
      widget.hit.source.playlist.name,
      if (group != null && group.isNotEmpty) group,
    ].join('  •  ');

    final hasArt = channel.logoUrl != null && channel.logoUrl!.isNotEmpty;

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: widget.isTelevision
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateOrSpaceKey(event.logicalKey)) {
          widget.onOpen();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          widget.onUp();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          // Swallowed on the last row — geometric traversal below the list
          // has nowhere sensible to go.
          widget.onDown?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onOpen,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const EdgeInsets.only(bottom: 3),
            decoration: BoxDecoration(
              color: _active ? const Color(0xFF141824) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _active ? HomeTheme.focusGold : Colors.transparent,
                width: 2,
              ),
              boxShadow: _active
                  ? [
                      BoxShadow(
                        color: HomeTheme.focusGold.withValues(alpha: 0.28),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: poster ? 34 : 44,
                  height: poster ? 48 : 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(poster ? 6 : 10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.alphaBlend(
                          brand.withValues(alpha: 0.16),
                          const Color(0xFF1E2030),
                        ),
                        const Color(0xFF14141D),
                      ],
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasArt
                      ? Padding(
                          padding: EdgeInsets.all(poster ? 0 : 6),
                          child: CachedNetworkImage(
                            imageUrl: channel.logoUrl!,
                            fit: poster ? BoxFit.cover : BoxFit.contain,
                            memCacheHeight: poster ? 144 : 88,
                            placeholder: (_, __) => _fallbackIcon(brand),
                            errorWidget: (_, __, ___) => _fallbackIcon(brand),
                          ),
                        )
                      : _fallbackIcon(brand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white
                              .withValues(alpha: _active ? 1.0 : 0.92),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.48),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (resolution != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Text(
                      resolution,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallbackIcon(Color brand) {
    return Center(
      child: Icon(
        widget.hit.section == 'live'
            ? Icons.live_tv_rounded
            : Icons.movie_rounded,
        size: 20,
        color: brand.withValues(alpha: 0.85),
      ),
    );
  }
}
