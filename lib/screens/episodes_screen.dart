import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../services/stremio_service.dart';
import '../services/trakt/trakt_episode_model.dart';
import '../services/storage_service.dart';
import 'debrify_tv/widgets/tv_focus_scroll_wrapper.dart';
import '../widgets/episode_tile.dart';
import '../widgets/home/home_theme.dart';

/// Route name for [EpisodesScreen]'s pushed route (a `MaterialPageRoute`,
/// or a zero-duration `PageRouteBuilder` on TV).
const String kEpisodesRouteName = 'episodes';

/// Route name the catalog host gives the pushed `CatalogItemDetailScreen`.
///
/// The detail screen no longer self-pops when "Browse" is tapped (so the
/// drill-down lands *on top of* it and back returns there). When a terminal
/// selection is made (Sources/Play/fallback) the drill-down + detail routes
/// must be torn back down to the host or the host's inline result (search
/// results / player) would be hidden behind them. These names let
/// [EpisodesScreen] and the host `popUntil` exactly those routes.
const String kCatalogDetailRouteName = 'catalog_item_detail';

/// A pushable route that presents the episode drill-down for a single series.
///
/// This was extracted out of `CatalogBrowser`'s inline "episode mode". Making
/// it a real route means system/back navigation returns to the previous
/// screen naturally instead of toggling host-screen state.
///
/// Source-binding (the Select Source button + bound-source count) is owned by
/// the host and surfaced through the [boundSourceCount] / [onSelectSource]
/// callbacks; this screen owns no bound-source state.
class EpisodesScreen extends StatefulWidget {
  /// The series to browse.
  final StremioMeta show;

  /// Optional explicit season to land on (deep links / calendar).
  final int? initialSeason;

  /// Optional explicit episode to land on (deep links / calendar).
  final int? initialEpisode;

  /// The addon used to fetch series meta (replaces the host's selected addon).
  final StremioAddon addon;

  /// Whether running on Android TV (disables animations, changes focus flow).
  final bool isTelevision;

  /// Whether to show the Quick Play button on episode tiles.
  final bool showQuickPlay;

  /// Callback when user selects an episode (Sources) or the series falls back
  /// to a direct search.
  final void Function(AdvancedSearchSelection selection)? onItemSelected;

  /// Callback when user quick-plays an episode.
  final void Function(AdvancedSearchSelection selection)? onQuickPlay;

  /// Fired exactly once when this route is dismissed *without* a terminal
  /// selection (back button / system back / gesture). Not called when the
  /// user picks an episode or falls back to direct search — those dispatch
  /// [onItemSelected]/[onQuickPlay] and pop straight to the host.
  final VoidCallback? onExitedWithoutSelection;

  /// Returns the number of bound sources for [show] (host-owned state).
  final int Function(StremioMeta show)? boundSourceCount;

  /// Callback when user taps the Select Source button. When null, the button
  /// is hidden.
  final void Function(StremioMeta show)? onSelectSource;

  const EpisodesScreen({
    super.key,
    required this.show,
    required this.addon,
    this.initialSeason,
    this.initialEpisode,
    this.isTelevision = false,
    this.showQuickPlay = true,
    this.onItemSelected,
    this.onQuickPlay,
    this.onExitedWithoutSelection,
    this.boundSourceCount,
    this.onSelectSource,
  });

  @override
  State<EpisodesScreen> createState() => _EpisodesScreenState();
}

class _EpisodesScreenState extends State<EpisodesScreen> {
  final StremioService _stremioService = StremioService.instance;

  // Episode drill-down state
  int _episodeModeGeneration = 0;
  StremioMeta? _selectedShow;
  List<TraktSeason> _episodeSeasons = [];
  int _selectedSeasonNumber = 1;
  bool _isLoadingEpisodes = false;
  Map<String, double> _episodeWatchProgress = {};

  /// Set before any terminal pop (episode chosen / quick-play / fallback) so
  /// [dispose] can tell a real selection apart from a plain back-out and only
  /// fire [EpisodesScreen.onExitedWithoutSelection] for the latter.
  bool _selectionDispatched = false;
  final List<FocusNode> _episodeFocusNodes = [];
  final ScrollController _episodeScrollController = ScrollController();
  final FocusNode _episodeBackButtonFocusNode = FocusNode(
    debugLabel: 'catalog-ep-back',
  );
  final FocusNode _episodeSeasonDropdownFocusNode = FocusNode(
    debugLabel: 'catalog-ep-season',
  );

  @override
  void initState() {
    super.initState();
    _episodeSeasonDropdownFocusNode.onKeyEvent =
        _handleEpisodeSeasonDropdownKeyEvent;
    _enterEpisodeMode(
      widget.show,
      initialSeason: widget.initialSeason,
      initialEpisode: widget.initialEpisode,
    );
  }

  @override
  void dispose() {
    // Plain back-out (no episode picked): tell the host to undo the source
    // switch it made on entry. Deferred a frame so the host's setState runs
    // after this route is fully torn down, never during it.
    if (!_selectionDispatched) {
      final cb = widget.onExitedWithoutSelection;
      if (cb != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => cb());
      }
    }
    _episodeScrollController.dispose();
    _episodeBackButtonFocusNode.dispose();
    _episodeSeasonDropdownFocusNode.dispose();
    for (final node in _episodeFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Load episode watch progress for the selected show.
  Future<void> _loadEpisodeWatchProgress(StremioMeta show) async {
    final imdbId = show.effectiveImdbId;
    if (imdbId == null) return;
    final progress = await StorageService.getEpisodeWatchProgressByImdbId(
      imdbId,
    );
    if (mounted) {
      setState(() => _episodeWatchProgress = progress);
    }
  }

  // ── Episode drill-down ──────────────────────────────────────────────────

  /// Tear the drill-down stack (this route + the detail route, if the host
  /// pushed one) back down to the host before a terminal dispatch, so the
  /// host's inline result isn't hidden behind these routes.
  void _popToHost() {
    Navigator.of(context).popUntil(
      (r) =>
          r.settings.name != kEpisodesRouteName &&
          r.settings.name != kCatalogDetailRouteName,
    );
  }

  /// Fallback: dispatch series directly to torrent search (bypasses episode mode).
  void _fallbackToDirectSearch(StremioMeta show) {
    if (!mounted) return;
    _selectionDispatched = true;
    _popToHost();
    final selection = AdvancedSearchSelection(
      imdbId: show.effectiveImdbId ?? show.id,
      isSeries: true,
      title: show.name,
      year: show.year,
      contentType: show.type,
      posterUrl: show.poster,
    );
    widget.onItemSelected?.call(selection);
  }

  void _enterEpisodeMode(
    StremioMeta show, {
    int? initialSeason,
    int? initialEpisode,
  }) async {
    final generation = ++_episodeModeGeneration;

    setState(() {
      _selectedShow = show;
      _isLoadingEpisodes = true;
      _episodeSeasons = [];
      _selectedSeasonNumber = initialSeason ?? 1;
    });

    // Load watch progress for this show
    _loadEpisodeWatchProgress(show);

    for (final node in _episodeFocusNodes) {
      node.dispose();
    }
    _episodeFocusNodes.clear();

    try {
      // Fetch episodes from addon meta endpoint
      final addon = widget.addon;

      final videos = await _stremioService.fetchSeriesMeta(addon, show.id);
      if (!mounted || generation != _episodeModeGeneration) return;

      if (videos == null || videos.isEmpty) {
        _fallbackToDirectSearch(show);
        return;
      }

      // Group videos into seasons
      final seasonMap = <int, List<TraktEpisode>>{};
      for (final v in videos) {
        final seasonRaw = v['season'];
        final seasonNum = seasonRaw is int
            ? seasonRaw
            : (seasonRaw is num ? seasonRaw.toInt() : null);
        if (seasonNum == null || seasonNum <= 0) continue;

        final epRaw = v['number'] ?? v['episode'];
        final epNum = epRaw is int
            ? epRaw
            : (epRaw is num ? epRaw.toInt() : null);
        if (epNum == null) continue;

        final title = (v['title'] as String?) ?? (v['name'] as String?) ?? '';
        final overview = v['overview'] as String?;
        final released = v['released'] as String?;
        final thumbnail = v['thumbnail'] as String?;
        final ratingRaw = v['imdbRating'] ?? v['rating'];
        final rating = ratingRaw is num
            ? ratingRaw.toDouble()
            : (ratingRaw is String ? double.tryParse(ratingRaw) : null);

        final episode = TraktEpisode(
          season: seasonNum,
          number: epNum,
          title: title,
          overview: overview,
          firstAired: released,
          thumbnailUrl: thumbnail,
          rating: rating,
        );

        seasonMap.putIfAbsent(seasonNum, () => []);
        seasonMap[seasonNum]!.add(episode);
      }

      if (seasonMap.isEmpty) {
        if (!mounted || generation != _episodeModeGeneration) return;
        _fallbackToDirectSearch(show);
        return;
      }

      // Sort seasons and episodes
      final seasons = seasonMap.entries.map((e) {
        final episodes = e.value..sort((a, b) => a.number.compareTo(b.number));
        return TraktSeason(
          number: e.key,
          episodeCount: episodes.length,
          episodes: episodes,
        );
      }).toList()..sort((a, b) => a.number.compareTo(b.number));

      // Resolve where to land. Explicit initialSeason/initialEpisode (deep
      // links, calendar) win; otherwise fall back to this show's last-played
      // episode. Catalog has no Trakt-style next-episode service, so without
      // this it always opens at S01E01. Mirrors _onQuickPlay's lookup.
      int? effectiveSeason = initialSeason;
      int? effectiveEpisode = initialEpisode;
      if (effectiveSeason == null || effectiveEpisode == null) {
        final imdbId = show.effectiveImdbId;
        if (imdbId != null) {
          final lastPlayed = await StorageService.getLastPlayedEpisodeByImdbId(
            imdbId,
          );
          if (!mounted || generation != _episodeModeGeneration) return;
          if (lastPlayed != null) {
            effectiveSeason ??= lastPlayed['season'] as int?;
            effectiveEpisode ??= lastPlayed['episode'] as int?;
          }
        }
        if (effectiveSeason == null || effectiveEpisode == null) {
          final byTitle = await StorageService.getLastPlayedEpisode(
            seriesTitle: show.name,
          );
          if (!mounted || generation != _episodeModeGeneration) return;
          if (byTitle != null) {
            effectiveSeason ??= byTitle['season'] as int?;
            effectiveEpisode ??= byTitle['episode'] as int?;
          }
        }
      }

      // Pick the target season: prefer the resolved season if it exists
      final targetSeason =
          (effectiveSeason != null &&
              seasons.any((s) => s.number == effectiveSeason))
          ? seasons.firstWhere((s) => s.number == effectiveSeason)
          : seasons.first;

      // Build focus nodes for target season
      for (int i = 0; i < targetSeason.episodes.length; i++) {
        _episodeFocusNodes.add(FocusNode(debugLabel: 'catalog-ep-$i'));
      }

      setState(() {
        _episodeSeasons = seasons;
        _selectedSeasonNumber = targetSeason.number;
        _isLoadingEpisodes = false;
      });

      // Scroll to (and focus) the target episode once its tile is built.
      // Robust against variable EpisodeTile height + lazy ListView building
      // (the old fixed focusIndex*128 estimate is wrong for the new tile).
      final targetEpIndex = effectiveEpisode != null
          ? targetSeason.episodes.indexWhere((e) => e.number == effectiveEpisode)
          : -1;
      _scrollFocusEpisode(
        targetEpIndex < 0 ? 0 : targetEpIndex,
        targetSeason.episodes.length,
        generation,
      );
    } catch (e) {
      if (!mounted || generation != _episodeModeGeneration) return;
      debugPrint('EpisodesScreen: Episode fetch failed: $e');
      _fallbackToDirectSearch(show);
    }
  }

  /// Robustly brings episode [epIndex] into view.
  ///
  /// The episode list is a lazy ListView with variable-height tiles, so a
  /// single fixed/proportional jump is unreliable — an off-screen target
  /// tile isn't built, leaving its FocusNode contextless. This re-reads
  /// scroll metrics each frame and converges (the builder's maxScrollExtent
  /// grows as more rows lay out). Once the tile exists: on TV focus it (the
  /// tile self-centers via EpisodeTile.onFocusChange and shows the focus
  /// border for the remote); on mobile/desktop just scroll it into view
  /// without focusing — an auto-applied golden focus border there looks out
  /// of place. Bounded so it can never spin.
  void _scrollFocusEpisode(int epIndex, int episodeCount, int generation) {
    const int maxAttempts = 16;
    void attempt(int n) {
      if (!mounted || generation != _episodeModeGeneration) return;
      if (epIndex < 0 || epIndex >= _episodeFocusNodes.length) return;
      final node = _episodeFocusNodes[epIndex];
      if (node.context != null) {
        if (widget.isTelevision) {
          node.requestFocus();
        } else {
          Scrollable.ensureVisible(
            node.context!,
            alignment: 0.5,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          );
        }
        return;
      }
      if (n >= maxAttempts || !_episodeScrollController.hasClients) {
        if (widget.isTelevision) node.requestFocus(); // best effort, then stop
        return;
      }
      final pos = _episodeScrollController.position;
      final ratio = episodeCount > 1 ? epIndex / (episodeCount - 1) : 0.0;
      final target = (pos.maxScrollExtent * ratio).clamp(
        0.0,
        pos.maxScrollExtent,
      );
      if ((target - pos.pixels).abs() > 1.0) {
        _episodeScrollController.jumpTo(target);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => attempt(n + 1));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => attempt(0));
  }

  void _onSeasonChanged(int? seasonNumber) {
    if (seasonNumber == null || seasonNumber == _selectedSeasonNumber) return;

    for (final node in _episodeFocusNodes) {
      node.dispose();
    }
    _episodeFocusNodes.clear();

    final season = _episodeSeasons.firstWhere(
      (s) => s.number == seasonNumber,
      orElse: () => _episodeSeasons.first,
    );
    for (int i = 0; i < season.episodes.length; i++) {
      _episodeFocusNodes.add(FocusNode(debugLabel: 'catalog-ep-$i'));
    }

    if (_episodeScrollController.hasClients) {
      _episodeScrollController.jumpTo(0);
    }

    setState(() => _selectedSeasonNumber = seasonNumber);
  }

  void _onEpisodeTap(TraktEpisode episode) {
    final show = _selectedShow;
    if (show == null || widget.onItemSelected == null) return;

    final selection = AdvancedSearchSelection(
      imdbId: show.effectiveImdbId ?? show.id,
      isSeries: true,
      title: show.name,
      year: show.year,
      season: episode.season,
      episode: episode.number,
      contentType: show.type,
      posterUrl: show.poster,
    );
    _selectionDispatched = true;
    _popToHost();
    widget.onItemSelected!(selection);
  }

  void _onEpisodeQuickPlay(TraktEpisode episode) {
    final show = _selectedShow;
    if (show == null) return;

    final selection = AdvancedSearchSelection(
      imdbId: show.effectiveImdbId ?? show.id,
      isSeries: true,
      title: show.name,
      year: show.year,
      season: episode.season,
      episode: episode.number,
      contentType: show.type,
      posterUrl: show.poster,
    );

    _selectionDispatched = true;
    _popToHost();
    if (widget.onQuickPlay != null) {
      widget.onQuickPlay!(selection);
    } else if (widget.onItemSelected != null) {
      widget.onItemSelected!(selection);
    }
  }

  Widget _buildEpisodeFiltersBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            // Back button — Focus-wrapped with blue accent border like Trakt
            Focus(
              focusNode: _episodeBackButtonFocusNode,
              onFocusChange: (focused) => setState(() {}),
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  // Top of a standalone route — nothing above to focus
                  // (the host is covered). Swallow so focus stays put.
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  _episodeSeasonDropdownFocusNode.requestFocus();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  if (_episodeFocusNodes.isNotEmpty) {
                    _episodeFocusNodes.first.requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.goBack) {
                  Navigator.of(context).pop();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _episodeBackButtonFocusNode.hasFocus
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                    color: _episodeBackButtonFocusNode.hasFocus
                        ? HomeTheme.focusGold
                        : Colors.white.withValues(alpha: 0.14),
                    width: _episodeBackButtonFocusNode.hasFocus ? 2 : 1,
                  ),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Back to shows',
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Show title
            Expanded(
              child: Text(
                _selectedShow?.name ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Season dropdown — Trakt-style with blue accent border
            if (_episodeSeasons.isNotEmpty) ...[
              const SizedBox(width: 8),
              _buildEpisodeSeasonDropdown(),
            ],

            // Select Source button
            if (_selectedShow != null && widget.onSelectSource != null) ...[
              const SizedBox(width: 8),
              Builder(
                builder: (context) {
                  final sourceCount =
                      widget.boundSourceCount?.call(_selectedShow!) ?? 0;
                  return _CatalogSelectSourceButton(
                    hasBoundSource: sourceCount > 0,
                    sourceCount: sourceCount,
                    onTap: () => widget.onSelectSource!(_selectedShow!),
                    onLeftFocus: _episodeSeasons.isNotEmpty
                        ? _episodeSeasonDropdownFocusNode
                        : _episodeBackButtonFocusNode,
                    onDownArrow: _episodeFocusNodes.isNotEmpty
                        ? () => _episodeFocusNodes.first.requestFocus()
                        : null,
                    // Top row of a standalone route — swallow Up (a non-null
                    // no-op makes the button report the key handled).
                    onUpArrow: () {},
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  KeyEventResult _handleEpisodeSeasonDropdownKeyEvent(
    FocusNode node,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      // Top row of a standalone route — swallow (nothing above).
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_episodeFocusNodes.isNotEmpty) {
        _episodeFocusNodes.first.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _episodeBackButtonFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (widget.onSelectSource != null) {
        node.nextFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildEpisodeSeasonDropdown() {
    return ListenableBuilder(
      listenable: _episodeSeasonDropdownFocusNode,
      builder: (context, _) {
        final hasFocus = _episodeSeasonDropdownFocusNode.hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: hasFocus ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasFocus
                  ? HomeTheme.focusGold
                  : Colors.white.withValues(alpha: 0.10),
              width: hasFocus ? 2.0 : 1.0,
            ),
            boxShadow: hasFocus
                ? [
                    BoxShadow(
                      color: HomeTheme.focusGold.withValues(alpha: 0.32),
                      blurRadius: 14,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              focusNode: _episodeSeasonDropdownFocusNode,
              focusColor: Colors.transparent,
              value: _selectedSeasonNumber,
              isDense: true,
              borderRadius: BorderRadius.circular(12),
              dropdownColor: const Color(0xFF14141C),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: hasFocus
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.7),
              ),
              items: _episodeSeasons.map((s) {
                return DropdownMenuItem(
                  value: s.number,
                  child: Text(
                    s.displayLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                );
              }).toList(),
              onChanged: _onSeasonChanged,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEpisodeContent() {
    if (_isLoadingEpisodes) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_episodeSeasons.isEmpty) {
      return Center(
        child: Text(
          'No episodes found',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        ),
      );
    }

    final currentSeason = _episodeSeasons.firstWhere(
      (s) => s.number == _selectedSeasonNumber,
      orElse: () => _episodeSeasons.first,
    );

    final w = MediaQuery.of(context).size.width;
    final hPad = w >= 900 ? 40.0 : 16.0;

    return TvFocusScrollWrapper(
      child: ListView.builder(
        controller: _episodeScrollController,
        padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 28),
        itemCount: currentSeason.episodes.length,
        itemBuilder: (context, index) {
          final episode = currentSeason.episodes[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: EpisodeTile(
              episode: episode,
              showImageUrl: _selectedShow?.poster,
              isTelevision: widget.isTelevision,
              showQuickPlay: widget.showQuickPlay,
              focusNode: index < _episodeFocusNodes.length
                  ? _episodeFocusNodes[index]
                  : null,
              watchProgress: _episodeWatchProgress[
                  '${episode.season}-${episode.number}'],
              onPlay: () => _onEpisodeQuickPlay(episode),
              onSources: () => _onEpisodeTap(episode),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E14),
      body: SafeArea(
        child: Column(
          children: [
            _buildEpisodeFiltersBar(),
            Expanded(child: _buildEpisodeContent()),
          ],
        ),
      ),
    );
  }
}

// ─── Select Source Button for catalog episode browser ────────────────────────

class _CatalogSelectSourceButton extends StatefulWidget {
  final bool hasBoundSource;
  final int sourceCount;
  final VoidCallback onTap;
  final FocusNode? onLeftFocus;
  final VoidCallback? onDownArrow;
  final VoidCallback? onUpArrow;

  const _CatalogSelectSourceButton({
    required this.hasBoundSource,
    this.sourceCount = 0,
    required this.onTap,
    this.onLeftFocus,
    this.onDownArrow,
    this.onUpArrow,
  });

  @override
  State<_CatalogSelectSourceButton> createState() =>
      _CatalogSelectSourceButtonState();
}

class _CatalogSelectSourceButtonState
    extends State<_CatalogSelectSourceButton> {
  final FocusNode _focusNode = FocusNode(
    debugLabel: 'catalog-select-source-btn',
  );
  bool _isFocused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          widget.onUpArrow?.call();
          return widget.onUpArrow != null
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            widget.onLeftFocus != null) {
          widget.onLeftFocus!.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          return KeyEventResult.handled; // rightmost button
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          widget.onDownArrow?.call();
          return widget.onDownArrow != null
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: widget.hasBoundSource
                ? HomeTheme.focusGold.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused
                  ? HomeTheme.focusGold
                  : widget.hasBoundSource
                  ? HomeTheme.focusGold.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.14),
              width: _isFocused ? 2 : 1,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: HomeTheme.focusGold.withValues(alpha: 0.32),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.hasBoundSource
                    ? Icons.link_rounded
                    : Icons.link_off_rounded,
                size: 16,
                color: widget.hasBoundSource
                    ? HomeTheme.focusGold
                    : Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 6),
              Text(
                widget.hasBoundSource
                    ? (widget.sourceCount > 1
                          ? 'Sources (${widget.sourceCount})'
                          : 'Source')
                    : 'Select Source',
                style: TextStyle(
                  color: widget.hasBoundSource
                      ? HomeTheme.focusGold
                      : Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
