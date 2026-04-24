import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../services/trakt/trakt_episode_model.dart';
import '../services/trakt/trakt_service.dart';
import '../services/trakt/trakt_item_transformer.dart';
import '../services/series_source_service.dart';
import '../services/storage_service.dart';
import '../services/main_page_bridge.dart';
import '../screens/debrid_downloads_screen.dart';
import '../screens/torbox/torbox_downloads_screen.dart';
import 'add_source_picker_dialog.dart';
import 'home_focus_controller.dart';

/// Premium OTT-style Trakt Continue Watching section for the home screen.
class HomeTraktContinueWatchingSection extends StatefulWidget {
  final HomeFocusController? focusController;
  final VoidCallback? onRequestFocusAbove;
  final VoidCallback? onRequestFocusBelow;
  final bool isTelevision;
  final HomeSection homeSection;
  final String contentType; // 'movies' or 'episodes'
  final void Function(AdvancedSearchSelection selection)? onItemSelected;
  final void Function(AdvancedSearchSelection selection)? onQuickPlay;
  final void Function(StremioMeta show)? onBrowseShow;
  final void Function(StremioMeta show)? onSelectSource;
  final void Function(StremioMeta show)? onSearchPacks;
  final ValueChanged<bool>? onInitialLoadStateChanged;

  const HomeTraktContinueWatchingSection({
    super.key,
    this.focusController,
    this.onRequestFocusAbove,
    this.onRequestFocusBelow,
    this.isTelevision = false,
    required this.homeSection,
    required this.contentType,
    this.onItemSelected,
    this.onQuickPlay,
    this.onBrowseShow,
    this.onSelectSource,
    this.onSearchPacks,
    this.onInitialLoadStateChanged,
  });

  @override
  State<HomeTraktContinueWatchingSection> createState() =>
      _HomeTraktContinueWatchingSectionState();
}

class _HomeTraktContinueWatchingSectionState
    extends State<HomeTraktContinueWatchingSection> {
  final TraktService _traktService = TraktService.instance;
  List<StremioMeta> _items = [];
  Map<String, double> _progressMap = {};

  /// Episode info for shows: imdbId → {season, episode, runtime}
  Map<String, ({int season, int episode, int? runtime})> _episodeInfoMap = {};

  /// Playback entry IDs from Trakt API, keyed by IMDB ID.
  /// For shows, stores all playback IDs for that show.
  Map<String, List<int>> _playbackIds = {};
  bool _isLoading = true;
  bool _initialLoadSettled = false;
  int _loadGeneration = 0;

  final List<FocusNode> _cardFocusNodes = [];
  final ScrollController _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  static const _accentColor = Color(0xFFED1C24);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollIndicators);
    _loadItems();
  }

  @override
  void dispose() {
    widget.focusController?.unregisterSection(widget.homeSection);
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    _scrollController.removeListener(_updateScrollIndicators);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollIndicators() {
    if (!mounted || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final canLeft = pos.pixels > 0;
    final canRight = pos.pixels < pos.maxScrollExtent;
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _ensureFocusNodes() {
    while (_cardFocusNodes.length < _items.length) {
      _cardFocusNodes.add(
        FocusNode(
          debugLabel:
              'trakt_cw_${widget.contentType}_${_cardFocusNodes.length}',
        ),
      );
    }
    while (_cardFocusNodes.length > _items.length) {
      _cardFocusNodes.removeLast().dispose();
    }
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadItems() async {
    final gen = ++_loadGeneration;
    setState(() => _isLoading = true);

    try {
      await _loadItemsInner(gen).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      debugPrint('Trakt continue watching timed out (${widget.contentType})');
      if (gen == _loadGeneration) _finishEmpty();
    } catch (e) {
      debugPrint('Error loading Trakt continue watching: $e');
      if (gen == _loadGeneration) _finishEmpty();
    }
  }

  Future<void> _loadItemsInner(int gen) async {
    final isAuth = await _traktService.isAuthenticated();
    if (!isAuth) {
      if (gen == _loadGeneration) _finishEmpty();
      return;
    }

    var rawItems = await _traktService.fetchPlaybackItems(widget.contentType);
    if (!mounted || gen != _loadGeneration) return;

    // For shows: also find recently watched shows with next episode available
    if (widget.contentType == 'episodes') {
      final playbackImdbIds = <String>{};
      for (final raw in rawItems) {
        if (raw is! Map<String, dynamic>) continue;
        final show = raw['show'] as Map<String, dynamic>?;
        final ids = show?['ids'] as Map<String, dynamic>?;
        final imdbId = ids?['imdb'] as String?;
        if (imdbId != null) playbackImdbIds.add(imdbId);
      }

      final recentWithNext = await _traktService
          .fetchRecentShowsWithNextEpisode(excludeImdbIds: playbackImdbIds);
      if (!mounted || gen != _loadGeneration) return;

      if (recentWithNext.isNotEmpty) {
        rawItems = List<dynamic>.from(rawItems)..addAll(recentWithNext);
      }
    }

    if (rawItems.isEmpty) {
      if (gen == _loadGeneration) _finishEmpty();
      return;
    }

    List<StremioMeta> items;
    Map<String, double> progressMap = {};
    Map<String, List<int>> playbackIds = {};
    var episodeInfo = <String, ({int season, int episode, int? runtime})>{};

    if (widget.contentType == 'movies') {
      items = TraktItemTransformer.transformList(
        rawItems,
        inferredType: 'movie',
      );
      for (final raw in rawItems) {
        if (raw is! Map<String, dynamic>) continue;
        final progress = raw['progress'] as num?;
        final pbId = raw['id'] as int?;
        final movie = raw['movie'] as Map<String, dynamic>?;
        final ids = movie?['ids'] as Map<String, dynamic>?;
        final imdbId = ids?['imdb'] as String?;
        if (imdbId != null && progress != null) {
          progressMap[imdbId] = progress.toDouble();
        }
        if (imdbId != null && pbId != null) {
          playbackIds.putIfAbsent(imdbId, () => []).add(pbId);
        }
      }
    } else {
      items = TraktItemTransformer.transformPlaybackEpisodes(rawItems);
      for (final raw in rawItems) {
        if (raw is! Map<String, dynamic>) continue;
        final progress = raw['progress'] as num?;
        final pbId = raw['id'] as int?;
        final show = raw['show'] as Map<String, dynamic>?;
        final ids = show?['ids'] as Map<String, dynamic>?;
        final imdbId = ids?['imdb'] as String?;
        final ep = raw['episode'] as Map<String, dynamic>?;
        if (imdbId != null && progress != null) {
          progressMap.putIfAbsent(imdbId, () => progress.toDouble());
        }
        if (imdbId != null && pbId != null) {
          playbackIds.putIfAbsent(imdbId, () => []).add(pbId);
        }
        if (imdbId != null && ep != null && !episodeInfo.containsKey(imdbId)) {
          episodeInfo[imdbId] = (
            season: ep['season'] as int? ?? 0,
            episode: ep['number'] as int? ?? 0,
            runtime: ep['runtime'] as int?,
          );
        }
      }
    }

    if (!mounted || gen != _loadGeneration) return;
    setState(() {
      _items = items;
      _progressMap = progressMap;
      _playbackIds = playbackIds;
      _episodeInfoMap = episodeInfo;
      _isLoading = false;
    });
    _ensureFocusNodes();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updateScrollIndicators(),
    );
    widget.focusController?.registerSection(
      widget.homeSection,
      hasItems: _items.isNotEmpty,
      focusNodes: _cardFocusNodes,
    );
    _notifyInitialLoadFinished();
  }

  void _finishEmpty() {
    if (!mounted) return;
    setState(() {
      _items = [];
      _isLoading = false;
    });
    _ensureFocusNodes();
    widget.focusController?.registerSection(
      widget.homeSection,
      hasItems: false,
      focusNodes: [],
    );
    _notifyInitialLoadFinished();
  }

  void _notifyInitialLoadFinished() {
    if (_initialLoadSettled) return;
    _initialLoadSettled = true;
    widget.onInitialLoadStateChanged?.call(false);
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool autofocus = false,
  }) {
    return _MenuItem(
      icon: icon,
      label: label,
      subtitle: subtitle,
      color: color,
      onTap: onTap,
      autofocus: autofocus,
      isTelevision: widget.isTelevision,
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _showEditSourceDialog(StremioMeta show) async {
    final imdbId = show.effectiveImdbId ?? show.id;
    var sources = await SeriesSourceService.getSources(imdbId);
    if (sources.isEmpty || !mounted) return;
    final isMovie = show.type == 'movie';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFF141824),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 450,
                  maxHeight: 500,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.link_rounded,
                            color: Color(0xFF60A5FA),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isMovie
                                ? 'Movie Source'
                                : 'Series Sources (${sources.length})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (!isMovie) ...[
                        const SizedBox(height: 4),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'First match wins — reorder by priority',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: sources.length,
                          itemBuilder: (context, index) {
                            final source = sources[index];
                            return ListTile(
                              key: ValueKey(source.torrentHash),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF60A5FA,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Color(0xFF60A5FA),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                source.torrentName,
                                style: const TextStyle(fontSize: 13),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: Colors.red.withValues(alpha: 0.7),
                                ),
                                onPressed: () async {
                                  await SeriesSourceService.removeSourceByHash(
                                    imdbId,
                                    source.torrentHash,
                                  );
                                  final updated =
                                      await SeriesSourceService.getSources(
                                        imdbId,
                                      );
                                  setDialogState(() {
                                    sources = updated;
                                  });
                                  if (updated.isEmpty &&
                                      dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Add from Debrid button
                      FutureBuilder<List<bool>>(
                        future: Future.wait([
                          StorageService.getApiKey().then(
                            (k) => k != null && k.isNotEmpty,
                          ),
                          StorageService.getTorboxApiKey().then(
                            (k) => k != null && k.isNotEmpty,
                          ),
                        ]),
                        builder: (context, snapshot) {
                          final rdEnabled = snapshot.data?[0] ?? false;
                          final torboxEnabled = snapshot.data?[1] ?? false;
                          if (!rdEnabled && !torboxEnabled) {
                            return const SizedBox.shrink();
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  _pushDebridSelectSource(
                                    show: show,
                                    imdbId: imdbId,
                                    rdEnabled: rdEnabled,
                                    torboxEnabled: torboxEnabled,
                                  );
                                },
                                icon: const Icon(
                                  Icons.cloud_download_outlined,
                                  size: 18,
                                  color: Color(0xFF60A5FA),
                                ),
                                label: const Text(
                                  'Add from Debrid',
                                  style: TextStyle(color: Color(0xFF60A5FA)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFF60A5FA),
                                    width: 1,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Close'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            icon: Icon(
                              isMovie
                                  ? Icons.swap_horiz_rounded
                                  : Icons.add_rounded,
                              size: 18,
                            ),
                            label: Text(
                              isMovie ? 'Change Source' : 'Add Source',
                            ),
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              widget.onSelectSource?.call(show);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Show the add-source picker (Torrent Search / Real-Debrid / TorBox).
  /// Skips the picker if no cloud providers are enabled.
  Future<void> _showAddSourcePicker(StremioMeta item) async {
    final imdbId = item.effectiveImdbId ?? item.id;
    final rdKey = await StorageService.getApiKey();
    final torboxKey = await StorageService.getTorboxApiKey();
    final rdEnabled = rdKey != null && rdKey.isNotEmpty;
    final torboxEnabled = torboxKey != null && torboxKey.isNotEmpty;

    if (!mounted) return;

    if (!rdEnabled && !torboxEnabled) {
      widget.onSelectSource?.call(item);
      return;
    }

    await showAddSourcePickerDialog(
      context,
      onTorrentSearch: () => widget.onSelectSource?.call(item),
      onRealDebrid: rdEnabled
          ? () => _pushDebridSelectSource(
              show: item,
              imdbId: imdbId,
              rdEnabled: true,
              torboxEnabled: false,
            )
          : null,
      onTorbox: torboxEnabled
          ? () => _pushDebridSelectSource(
              show: item,
              imdbId: imdbId,
              rdEnabled: false,
              torboxEnabled: true,
            )
          : null,
    );
  }

  /// Push debrid downloads screen in select-source mode.
  /// If both providers enabled, shows a picker first.
  void _pushDebridSelectSource({
    required StremioMeta show,
    required String imdbId,
    required bool rdEnabled,
    required bool torboxEnabled,
  }) {
    final isMovie = show.type == 'movie';

    Future<void> saveSource(SeriesSource source) async {
      if (isMovie) {
        await SeriesSourceService.setSources(imdbId, [source]);
      } else {
        await SeriesSourceService.addSource(imdbId, source);
      }
    }

    void pushRd() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DebridDownloadsScreen(
            isPushedRoute: true,
            initialSearchQuery: show.name,
            selectSourceMode: true,
            onSourceSelected: saveSource,
          ),
        ),
      );
    }

    void pushTorbox() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TorboxDownloadsScreen(
            isPushedRoute: true,
            initialSearchQuery: show.name,
            selectSourceMode: true,
            onSourceSelected: saveSource,
          ),
        ),
      );
    }

    if (rdEnabled && !torboxEnabled) {
      pushRd();
      return;
    }
    if (torboxEnabled && !rdEnabled) {
      pushTorbox();
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141824),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Provider',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud, color: Color(0xFF22C55E)),
              title: const Text(
                'Real-Debrid',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                pushRd();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud, color: Color(0xFF7C3AED)),
              title: const Text(
                'TorBox',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                pushTorbox();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _onItemTap(StremioMeta item) async {
    // Check if item has bound source (works for both movies and series)
    bool hasBoundSource = false;
    if (widget.onSelectSource != null) {
      final imdbId = item.effectiveImdbId ?? item.id;
      final sources = await SeriesSourceService.getSources(imdbId);
      hasBoundSource = sources.isNotEmpty;
    }
    if (!mounted) return;

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            decoration: BoxDecoration(
              color: const Color(0xFF141824),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                _buildMenuItem(
                  icon: Icons.play_circle_filled_rounded,
                  label: 'Play',
                  subtitle: 'Quick play with default source',
                  color: const Color(0xFF10B981),
                  onTap: () => Navigator.pop(context, 'quick_play'),
                  autofocus: true,
                ),
                if (item.type != 'series' && widget.onSelectSource != null)
                  _buildMenuItem(
                    icon: hasBoundSource
                        ? Icons.edit_rounded
                        : Icons.add_link_rounded,
                    label: hasBoundSource ? 'Edit Source' : 'Add Source',
                    subtitle: hasBoundSource
                        ? 'Change the bound torrent source'
                        : 'Bind a torrent source for quick play',
                    color: const Color(0xFF60A5FA),
                    onTap: () => Navigator.pop(context, 'select_source'),
                  ),
                _buildMenuItem(
                  icon: item.type == 'series'
                      ? Icons.view_list_rounded
                      : Icons.search_rounded,
                  label: item.type == 'series'
                      ? 'Browse Episodes'
                      : 'Browse Sources',
                  subtitle: item.type == 'series'
                      ? 'View seasons and episodes'
                      : 'Find sources to play, download, or save',
                  color: const Color(0xFF818CF8),
                  onTap: () => Navigator.pop(context, 'browse'),
                ),
                if (item.type == 'series')
                  _buildMenuItem(
                    icon: Icons.shuffle_rounded,
                    label: 'Play Random Episode',
                    subtitle: 'Pick a random aired episode',
                    color: const Color(0xFFF59E0B),
                    onTap: () => Navigator.pop(context, 'random_episode'),
                  ),
                if (widget.onSelectSource != null)
                  if (item.type == 'series')
                    _buildMenuItem(
                      icon: hasBoundSource
                          ? Icons.edit_rounded
                          : Icons.add_link_rounded,
                      label: hasBoundSource ? 'Edit Source' : 'Add Source',
                      subtitle: hasBoundSource
                          ? 'Change the bound torrent source'
                          : 'Bind a torrent source for quick play',
                      color: const Color(0xFF60A5FA),
                      onTap: () => Navigator.pop(context, 'select_source'),
                    ),
                if (item.type == 'series' && widget.onSearchPacks != null)
                  _buildMenuItem(
                    icon: Icons.inventory_2_outlined,
                    label: 'Search Season Packs',
                    subtitle: 'Find full season packs to download or add',
                    color: const Color(0xFFFBBF24),
                    onTap: () => Navigator.pop(context, 'search_packs'),
                  ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                _buildMenuItem(
                  icon: Icons.remove_circle_outline_rounded,
                  label: 'Remove from Continue Watching',
                  subtitle: 'Remove playback progress from Trakt',
                  color: const Color(0xFFEF4444),
                  onTap: () => Navigator.pop(context, 'remove'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'browse') {
      _browseItem(item);
    } else if (choice == 'quick_play') {
      _quickPlayItem(item);
    } else if (choice == 'random_episode') {
      await _playRandomEpisode(item);
    } else if (choice == 'select_source') {
      if (hasBoundSource) {
        _showEditSourceDialog(item);
      } else {
        await _showAddSourcePicker(item);
      }
    } else if (choice == 'search_packs') {
      widget.onSearchPacks?.call(item);
    } else if (choice == 'remove') {
      _removePlayback(item);
    }
  }

  void _browseItem(StremioMeta item) {
    if (item.type == 'series') {
      widget.onBrowseShow?.call(item);
      return;
    }
    final progress = _traktProgressForItem(item);
    final selection = AdvancedSearchSelection(
      imdbId: item.imdbId ?? item.id,
      isSeries: false,
      title: item.name,
      year: item.year,
      contentType: item.type,
      posterUrl: item.poster,
      traktProgressPercent: progress,
      traktSource: true,
    );
    widget.onItemSelected?.call(selection);
  }

  void _quickPlayItem(StremioMeta item) async {
    int? season;
    int? episode;
    double? traktProgress = _traktProgressForItem(item);

    if (item.type == 'series') {
      final showId = item.imdbId ?? item.id;
      // Prefer the episode info already loaded for the Continue Watching tile
      // — it comes from /sync/playback/episodes (the actually-paused episode)
      // and matches what the user saw on screen. Falling back to
      // fetchNextEpisode (/shows/{id}/progress/watched) would return
      // "first unwatched" which can disagree when earlier episodes aren't
      // flagged as watched yet (e.g. before scrobble-stop fires).
      final cached = _episodeInfoMap[item.id];
      if (cached != null) {
        season = cached.season;
        episode = cached.episode;
      } else {
        final next = await _traktService.fetchNextEpisode(showId);
        if (!mounted) return;
        if (next == null) {
          _browseItem(item);
          return;
        }
        season = next.season;
        episode = next.episode;
      }

      final episodeProgress = await _traktService.fetchEpisodePlaybackProgress(
        showId,
      );
      if (!mounted) return;
      final key = '$season-$episode';
      final p = episodeProgress[key];
      if (p != null && p > 0 && p < 100) {
        traktProgress = p;
      }
    }

    final selection = AdvancedSearchSelection(
      imdbId: item.imdbId ?? item.id,
      isSeries: item.type == 'series',
      title: item.name,
      year: item.year,
      season: season,
      episode: episode,
      contentType: item.type,
      posterUrl: item.poster,
      traktProgressPercent: traktProgress,
      traktSource: true,
    );
    if (widget.onQuickPlay != null) {
      widget.onQuickPlay!(selection);
    } else {
      widget.onItemSelected?.call(selection);
    }
  }

  Future<void> _playRandomEpisode(StremioMeta item) async {
    if (item.type != 'series') {
      _quickPlayItem(item);
      return;
    }

    final navigator = Navigator.of(context, rootNavigator: true);
    var loadingDialogOpen = true;
    void dismissLoadingDialog() {
      if (!loadingDialogOpen) return;
      loadingDialogOpen = false;
      if (navigator.canPop()) {
        navigator.pop();
      }
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: const Color(0xFF141824),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Color(0xFFF59E0B),
                  ),
                ),
                SizedBox(width: 14),
                Flexible(
                  child: Text(
                    'Picking a random episode...',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final showId = item.imdbId ?? item.id;
      final rawSeasons = await _traktService.fetchShowSeasons(showId);
      if (!mounted) {
        dismissLoadingDialog();
        return;
      }

      final seasons = rawSeasons
          .map(TraktSeason.fromJson)
          .where((season) => season.episodes.isNotEmpty)
          .toList();
      final chosen = _pickRandomEpisodeFromSeasons(
        seasons,
        currentEpisode: _episodeInfoMap[item.id],
      );

      if (chosen == null) {
        dismissLoadingDialog();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No playable episodes found for this show on Trakt'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
        return;
      }

      double? traktProgress;
      final episodeProgress = await _traktService.fetchEpisodePlaybackProgress(
        showId,
      );
      if (!mounted) {
        dismissLoadingDialog();
        return;
      }
      final progress = episodeProgress['${chosen.season}-${chosen.number}'];
      if (progress != null && progress > 0 && progress < 100) {
        traktProgress = progress;
      }

      dismissLoadingDialog();

      final selection = AdvancedSearchSelection(
        imdbId: showId,
        isSeries: true,
        title: item.name,
        year: item.year,
        season: chosen.season,
        episode: chosen.number,
        contentType: item.type,
        posterUrl: item.poster,
        traktProgressPercent: traktProgress,
        traktSource: true,
      );

      if (widget.onQuickPlay != null) {
        widget.onQuickPlay!(selection);
      } else {
        widget.onItemSelected?.call(selection);
      }
    } catch (e) {
      debugPrint('Trakt: random episode pick failed for ${item.id}: $e');
      dismissLoadingDialog();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to pick a random episode'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
    }
  }

  TraktEpisode? _pickRandomEpisodeFromSeasons(
    List<TraktSeason> seasons, {
    ({int season, int episode, int? runtime})? currentEpisode,
  }) {
    if (seasons.isEmpty) return null;

    final nowUtc = DateTime.now().toUtc();

    List<TraktEpisode> collectCandidates(
      bool Function(TraktEpisode episode) test,
    ) {
      return seasons
          .expand((season) => season.episodes)
          .where(test)
          .where((episode) => episode.number > 0)
          .toList();
    }

    bool isRegularEpisode(TraktEpisode episode) => episode.season > 0;

    bool isAired(TraktEpisode episode) {
      final firstAired = episode.firstAired;
      if (firstAired == null || firstAired.isEmpty) {
        return true;
      }
      final parsed = DateTime.tryParse(firstAired);
      if (parsed == null) {
        return true;
      }
      return !parsed.toUtc().isAfter(nowUtc);
    }

    var candidates = collectCandidates(
      (episode) => isRegularEpisode(episode) && isAired(episode),
    );
    candidates = _excludeCurrentEpisodeIfPossible(candidates, currentEpisode);
    if (candidates.isNotEmpty) {
      return candidates[Random().nextInt(candidates.length)];
    }

    candidates = collectCandidates(isAired);
    candidates = _excludeCurrentEpisodeIfPossible(candidates, currentEpisode);
    if (candidates.isNotEmpty) {
      return candidates[Random().nextInt(candidates.length)];
    }

    return null;
  }

  List<TraktEpisode> _excludeCurrentEpisodeIfPossible(
    List<TraktEpisode> episodes,
    ({int season, int episode, int? runtime})? currentEpisode,
  ) {
    if (episodes.length <= 1 || currentEpisode == null) {
      return episodes;
    }

    final filtered = episodes
        .where(
          (episode) =>
              episode.season != currentEpisode.season ||
              episode.number != currentEpisode.episode,
        )
        .toList();
    return filtered.isNotEmpty ? filtered : episodes;
  }

  Future<void> _removePlayback(StremioMeta item) async {
    final imdbId = item.imdbId ?? item.id;
    final type = item.type;
    bool anySuccess = false;

    // Remove all playback entries for this item
    final ids = _playbackIds[imdbId];
    if (ids != null && ids.isNotEmpty) {
      for (final pbId in ids) {
        final ok = await _traktService.removePlaybackItem(pbId);
        if (ok) anySuccess = true;
      }
    }

    // Also remove from watch history so it doesn't reappear via "Up Next"
    final historyRemoved = await _traktService.removeFromHistory(imdbId, type);
    if (historyRemoved) anySuccess = true;

    if (anySuccess && mounted) {
      _loadItems();
    }
  }

  double? _traktProgressForItem(StremioMeta item) {
    final p = _progressMap[item.id];
    if (p == null || p <= 0 || p >= 100) return null;
    return p;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMovies = widget.contentType == 'movies';
    final title = isMovies
        ? 'Continue Watching · Movies (Trakt)'
        : 'Continue Watching · Shows (Trakt)';

    if (_isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(title),
          const SizedBox(height: 8),
          SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Loading...',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (_items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title),
        const SizedBox(height: 8),
        // ── Horizontal card row ──
        LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = MediaQuery.of(context).size.width;
            final isMobile = screenWidth < 600;
            final rowHeight = isMobile ? 200.0 : 220.0;
            return SizedBox(
              height: rowHeight,
              child: Stack(
                children: [
                  // Edge fade (skip ShaderMask on TV for GPU performance)
                  if (widget.isTelevision)
                    ListView.builder(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(
                        left: 16,
                        top: 8,
                        bottom: 8,
                      ),
                      clipBehavior: Clip.none,
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final progress = _progressMap[item.id];
                        final epInfo = _episodeInfoMap[item.id];

                        return Padding(
                          padding: EdgeInsets.only(
                            right: index < _items.length - 1 ? 16 : 0,
                          ),
                          child: _buildCard(
                            item: item,
                            progressPercent: progress != null
                                ? progress / 100
                                : null,
                            episodeInfo: epInfo,
                            index: index,
                            focusNode: index < _cardFocusNodes.length
                                ? _cardFocusNodes[index]
                                : null,
                          ),
                        );
                      },
                    )
                  else
                    ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: const [
                            Colors.transparent,
                            Colors.white,
                            Colors.white,
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.015, 0.985, 1.0],
                        ).createShader(bounds);
                      },
                      blendMode: BlendMode.dstIn,
                      child: ListView.builder(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(
                          left: 16,
                          top: 8,
                          bottom: 8,
                        ),
                        clipBehavior: Clip.none,
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final progress = _progressMap[item.id];
                          final epInfo = _episodeInfoMap[item.id];

                          return Padding(
                            padding: EdgeInsets.only(
                              right: index < _items.length - 1 ? 16 : 0,
                            ),
                            child: _buildCard(
                              item: item,
                              progressPercent: progress != null
                                  ? progress / 100
                                  : null,
                              episodeInfo: epInfo,
                              index: index,
                              focusNode: index < _cardFocusNodes.length
                                  ? _cardFocusNodes[index]
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Divider(height: 1, thickness: 0.5, color: Color(0x14FFFFFF)),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  // ── Section header ────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: _accentColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.75),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_items.length}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  // ── Landscape card ────────────────────────────────────────────────────────

  Widget _buildEpisodeLabel(
    ({int season, int episode, int? runtime}) info,
    double? progressPercent,
  ) {
    final epCode =
        'S${info.season.toString().padLeft(2, '0')}E${info.episode.toString().padLeft(2, '0')}';

    String detail;
    if (progressPercent != null &&
        progressPercent > 0 &&
        info.runtime != null &&
        info.runtime! > 0) {
      final remainingMin = ((1 - progressPercent) * info.runtime!).round();
      detail = remainingMin > 0 ? '${remainingMin}m left' : 'Almost done';
    } else if (progressPercent == null || progressPercent <= 0) {
      detail = 'Up Next';
    } else {
      detail = '${(progressPercent * 100).round()}%';
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: _accentColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            epCode,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _accentColor,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          detail,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildCard({
    required StremioMeta item,
    double? progressPercent,
    ({int season, int episode, int? runtime})? episodeInfo,
    int index = 0,
    FocusNode? focusNode,
  }) {
    return _TraktCardWithFocus(
      onTap: () => _onItemTap(item),
      focusNode: focusNode,
      index: index,
      totalCount: _items.length,
      scrollController: _scrollController,
      onUpPressed: widget.onRequestFocusAbove,
      onDownPressed: widget.onRequestFocusBelow,
      allFocusNodes: _cardFocusNodes,
      isTelevision: widget.isTelevision,
      onFocusChanged: (focused, idx) {
        if (focused) {
          widget.focusController?.saveLastFocusedIndex(widget.homeSection, idx);
        }
      },
      child: (isFocused, isHovered) {
        final isActive = isFocused || isHovered;
        final screenWidth = MediaQuery.of(context).size.width;
        final isMobile = screenWidth < 600;
        final isHero = index == 0;
        final cardWidth = isMobile
            ? (isHero ? screenWidth * 0.82 : screenWidth * 0.7)
            : (isHero ? 350.0 : 280.0);
        final cardHeight = isMobile
            ? (isHero ? 180.0 : 155.0)
            : (isHero ? 200.0 : 170.0);

        // Metadata
        final year = item.year ?? '';
        final rating = item.imdbRating;
        final genres = item.genres;
        final typeBadge = item.type == 'series' ? 'SERIES' : 'MOVIE';

        final cardContent = ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Backdrop image ──
              _buildBackdropImage(item),

              // ── Cinematic gradient overlay ──
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.1),
                        Colors.black.withValues(alpha: 0.75),
                        Colors.black.withValues(alpha: 0.95),
                      ],
                      stops: const [0.0, 0.3, 0.65, 1.0],
                    ),
                  ),
                ),
              ),
              // Left vignette (skip on TV for GPU perf)
              if (!widget.isTelevision)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          Colors.transparent,
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.3, 1.0],
                      ),
                    ),
                  ),
                ),

              // ── Rating badge (top right) ──
              if (rating != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 10,
                          color: Color(0xFFFFD700),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          rating.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Bottom info area ──
              Positioned(
                bottom: progressPercent != null ? 5 : 12,
                left: 12,
                right: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.2,
                        letterSpacing: -0.2,
                        shadows: widget.isTelevision
                            ? null
                            : const [
                                Shadow(color: Colors.black, blurRadius: 8),
                              ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Metadata row: year + genres
                    Row(
                      children: [
                        if (year.isNotEmpty) ...[
                          Text(
                            year,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                        if (year.isNotEmpty &&
                            genres != null &&
                            genres.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Container(
                              width: 3,
                              height: 3,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.3),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        if (genres != null && genres.isNotEmpty)
                          Flexible(
                            child: Text(
                              genres.take(2).join(' / '),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                    // Episode info label for series
                    if (episodeInfo != null) ...[
                      const SizedBox(height: 4),
                      _buildEpisodeLabel(episodeInfo, progressPercent),
                    ],
                  ],
                ),
              ),

              // ── Progress bar ──
              if (progressPercent != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SizedBox(
                    height: 3.5,
                    child: Stack(
                      children: [
                        // Track
                        Container(color: Colors.white.withValues(alpha: 0.1)),
                        // Fill
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progressPercent.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFED1C24), Color(0xFFFF4D4D)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _accentColor.withValues(alpha: 0.6),
                                  blurRadius: 6,
                                  offset: const Offset(0, -1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Play overlay on hover/focus ──
              if (widget.isTelevision && isActive)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.25),
                    child: Center(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.15),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                        child: ClipOval(
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.6),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else if (!widget.isTelevision)
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: isActive ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.25),
                      child: Center(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.85, end: isActive ? 1.0 : 0.85),
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutBack,
                          builder: (context, scale, child) =>
                              Transform.scale(scale: scale, child: child),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.15),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.4),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 10,
                                  sigmaY: 10,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );

        final cardDecoration = BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? Colors.white.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.08),
            width: isActive ? 1.5 : 0.5,
          ),
          boxShadow: widget.isTelevision
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isActive ? 0.9 : 0.6),
                    blurRadius: isActive ? 30 : 16,
                    offset: const Offset(0, 8),
                  ),
                ],
        );

        if (widget.isTelevision) {
          return Transform.scale(
            scale: isActive ? 1.05 : 1.0,
            child: Container(
              width: cardWidth,
              height: cardHeight,
              decoration: cardDecoration,
              child: cardContent,
            ),
          );
        }

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 1.0, end: isActive ? 1.05 : 1.0),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            width: cardWidth,
            height: cardHeight,
            decoration: cardDecoration,
            child: cardContent,
          ),
        );
      },
    );
  }

  Widget _buildBackdropImage(StremioMeta item) {
    // Prefer backdrop, fallback to poster
    final imageUrl = item.background ?? item.poster;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        memCacheWidth: 600,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: const Color(0xFF0D1117),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ),
          ),
        ),
        errorWidget: (context, url, error) => _buildPlaceholder(item.name),
      );
    }
    return _buildPlaceholder(item.name);
  }

  Widget _buildPlaceholder(String title) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A2E), Color(0xFF0D1117)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.movie_rounded,
              size: 28,
              color: Colors.white.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Glass pill badge ──────────────────────────────────────────────────────────

class _GlassPill extends StatelessWidget {
  final Widget child;

  const _GlassPill({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 0.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ── Focus-aware card wrapper (DPAD/TV) ────────────────────────────────────────

class _TraktCardWithFocus extends StatefulWidget {
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final int index;
  final int totalCount;
  final ScrollController? scrollController;
  final VoidCallback? onUpPressed;
  final VoidCallback? onDownPressed;
  final void Function(bool focused, int index)? onFocusChanged;
  final Widget Function(bool isFocused, bool isHovered) child;
  final List<FocusNode>? allFocusNodes;
  final bool isTelevision;

  const _TraktCardWithFocus({
    required this.onTap,
    required this.child,
    this.focusNode,
    this.index = 0,
    this.totalCount = 1,
    this.scrollController,
    this.onUpPressed,
    this.onDownPressed,
    this.onFocusChanged,
    this.allFocusNodes,
    this.isTelevision = false,
  });

  @override
  State<_TraktCardWithFocus> createState() => _TraktCardWithFocusState();
}

class _TraktCardWithFocusState extends State<_TraktCardWithFocus> {
  bool _isFocused = false;
  bool _isHovered = false;
  final GlobalKey _cardKey = GlobalKey();

  void _onFocusChange(bool focused) {
    setState(() => _isFocused = focused);
    widget.onFocusChanged?.call(focused, widget.index);

    if (focused && widget.scrollController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _cardKey.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: widget.isTelevision
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.gameButtonA) {
        widget.onTap?.call();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        widget.onUpPressed?.call();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        widget.onDownPressed?.call();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (widget.isTelevision && widget.allFocusNodes != null) {
          if (widget.index > 0) {
            widget.allFocusNodes![widget.index - 1].requestFocus();
          } else {
            MainPageBridge.focusTvSidebar?.call();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (widget.isTelevision && widget.allFocusNodes != null) {
          if (widget.index < widget.allFocusNodes!.length - 1) {
            widget.allFocusNodes![widget.index + 1].requestFocus();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: _onFocusChange,
        onKeyEvent: _handleKeyEvent,
        child: GestureDetector(
          onTap: widget.onTap,
          child: KeyedSubtree(
            key: _cardKey,
            child: widget.child(_isFocused, _isHovered),
          ),
        ),
      ),
    );
  }
}

// ── Scroll indicator ──────────────────────────────────────────────────────────

enum _ScrollDirection { left, right }

class _ScrollIndicator extends StatelessWidget {
  final _ScrollDirection direction;

  const _ScrollIndicator({required this.direction});

  @override
  Widget build(BuildContext context) {
    final isLeft = direction == _ScrollDirection.left;

    return IgnorePointer(
      child: Container(
        width: 36,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
            end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
            colors: [
              const Color(0xFF0F0F1A).withValues(alpha: 0.95),
              Colors.transparent,
            ],
          ),
        ),
        child: const SizedBox.shrink(),
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool autofocus;
  final bool isTelevision;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.autofocus = false,
    this.isTelevision = false,
  });

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      autofocus: widget.autofocus,
      canRequestFocus: true,
      onTap: widget.onTap,
      onFocusChange: (focused) => setState(() => _focused = focused),
      borderRadius: BorderRadius.circular(8),
      child: widget.isTelevision
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: _focused
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(
                        alpha: _focused ? 0.2 : 0.12,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.icon, size: 18, color: widget.color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: _focused
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(
                        alpha: _focused ? 0.2 : 0.12,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.icon, size: 18, color: widget.color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
