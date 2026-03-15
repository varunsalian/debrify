import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../services/trakt/trakt_service.dart';
import '../services/trakt/trakt_item_transformer.dart';
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
  bool _isLoading = true;

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
      _cardFocusNodes.add(FocusNode(
          debugLabel:
              'trakt_cw_${widget.contentType}_${_cardFocusNodes.length}'));
    }
    while (_cardFocusNodes.length > _items.length) {
      _cardFocusNodes.removeLast().dispose();
    }
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);

    try {
      final isAuth = await _traktService.isAuthenticated();
      if (!isAuth) {
        _finishEmpty();
        return;
      }

      final rawItems =
          await _traktService.fetchPlaybackItems(widget.contentType);
      if (rawItems.isEmpty) {
        _finishEmpty();
        return;
      }

      List<StremioMeta> items;
      Map<String, double> progressMap = {};

      if (widget.contentType == 'movies') {
        items = TraktItemTransformer.transformList(rawItems,
            inferredType: 'movie');
        for (final raw in rawItems) {
          if (raw is! Map<String, dynamic>) continue;
          final progress = raw['progress'] as num?;
          final movie = raw['movie'] as Map<String, dynamic>?;
          final ids = movie?['ids'] as Map<String, dynamic>?;
          final imdbId = ids?['imdb'] as String?;
          if (imdbId != null && progress != null) {
            progressMap[imdbId] = progress.toDouble();
          }
        }
      } else {
        items = TraktItemTransformer.transformPlaybackEpisodes(rawItems);
        for (final raw in rawItems) {
          if (raw is! Map<String, dynamic>) continue;
          final progress = raw['progress'] as num?;
          final show = raw['show'] as Map<String, dynamic>?;
          final ids = show?['ids'] as Map<String, dynamic>?;
          final imdbId = ids?['imdb'] as String?;
          if (imdbId != null && progress != null) {
            progressMap.putIfAbsent(imdbId, () => progress.toDouble());
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _items = items;
        _progressMap = progressMap;
        _isLoading = false;
      });
      _ensureFocusNodes();
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _updateScrollIndicators());
      widget.focusController?.registerSection(
        widget.homeSection,
        hasItems: _items.isNotEmpty,
        focusNodes: _cardFocusNodes,
      );
    } catch (e) {
      debugPrint('Error loading Trakt continue watching: $e');
      _finishEmpty();
    }
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
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _onItemTap(StremioMeta item) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'browse'),
            child: const Row(
              children: [
                Icon(Icons.list_rounded, size: 20),
                SizedBox(width: 12),
                Text('Browse'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'quick_play'),
            child: const Row(
              children: [
                Icon(Icons.play_arrow_rounded, size: 20),
                SizedBox(width: 12),
                Text('Quick Play'),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'browse') {
      _browseItem(item);
    } else if (choice == 'quick_play') {
      _quickPlayItem(item);
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
    );
    widget.onItemSelected?.call(selection);
  }

  void _quickPlayItem(StremioMeta item) async {
    int? season;
    int? episode;
    double? traktProgress = _traktProgressForItem(item);

    if (item.type == 'series') {
      final showId = item.imdbId ?? item.id;
      final next = await _traktService.fetchNextEpisode(showId);
      if (!mounted) return;
      if (next == null) {
        _browseItem(item);
        return;
      }
      season = next.season;
      episode = next.episode;

      if (season != null && episode != null) {
        final episodeProgress =
            await _traktService.fetchEpisodePlaybackProgress(showId);
        if (!mounted) return;
        final key = '$season-$episode';
        final p = episodeProgress[key];
        if (p != null && p > 0 && p < 100) {
          traktProgress = p;
        }
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
    );
    if (widget.onQuickPlay != null) {
      widget.onQuickPlay!(selection);
    } else {
      widget.onItemSelected?.call(selection);
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
    if (_isLoading || _items.isEmpty) {
      return const SizedBox.shrink();
    }

    final isMovies = widget.contentType == 'movies';
    final title = isMovies ? 'Trakt Continue Watching - Movies' : 'Trakt Continue Watching - Shows';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ──
        _buildSectionHeader(title),
        const SizedBox(height: 12),
        // ── Horizontal card row ──
        SizedBox(
          height: 195,
          child: Stack(
            children: [
              // Edge fade
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  clipBehavior: Clip.none,
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final progress = _progressMap[item.id];

                    return Padding(
                      padding: EdgeInsets.only(
                          right: index < _items.length - 1 ? 16 : 0),
                      child: _buildCard(
                        item: item,
                        progressPercent:
                            progress != null ? progress / 100 : null,
                        index: index,
                        focusNode: index < _cardFocusNodes.length
                            ? _cardFocusNodes[index]
                            : null,
                      ),
                    );
                  },
                ),
              ),
              // Scroll indicators
              if (_canScrollLeft)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: _ScrollIndicator(direction: _ScrollDirection.left),
                ),
              if (_canScrollRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _ScrollIndicator(direction: _ScrollDirection.right),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Section header ────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          // Trakt "T" logo mark
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFED1C24), Color(0xFFBF1017)],
              ),
              borderRadius: BorderRadius.circular(7),
              boxShadow: [
                BoxShadow(
                  color: _accentColor.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'T',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Title
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.95),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 10),
          // Count pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${_items.length}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
          const Spacer(),
          // Subtle decorative line
          Expanded(
            flex: 3,
            child: Container(
              height: 1,
              margin: const EdgeInsets.only(left: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _accentColor.withValues(alpha: 0.3),
                    _accentColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Landscape card ────────────────────────────────────────────────────────

  Widget _buildCard({
    required StremioMeta item,
    double? progressPercent,
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
      onFocusChanged: (focused, idx) {
        if (focused) {
          widget.focusController
              ?.saveLastFocusedIndex(widget.homeSection, idx);
        }
      },
      child: (isFocused, isHovered) {
        final isActive = isFocused || isHovered;

        // Metadata
        final year = item.year ?? '';
        final rating = item.imdbRating;
        final genres = item.genres;
        final typeBadge = item.type == 'series' ? 'SERIES' : 'MOVIE';

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 1.0, end: isActive ? 1.05 : 1.0),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            width: 290,
            height: 175,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isActive
                    ? _accentColor.withValues(alpha: 0.9)
                    : Colors.white.withValues(alpha: 0.06),
                width: isActive ? 2.0 : 1.0,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: _accentColor.withValues(alpha: 0.4),
                        blurRadius: 24,
                        spreadRadius: 0,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isActive ? 12.5 : 13),
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
                  // Left vignette
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

                  // ── Top badges row ──
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Row(
                      children: [
                        // Type badge
                        _GlassPill(
                          child: Text(
                            typeBadge,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Rating badge
                        if (rating != null)
                          _GlassPill(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded,
                                    size: 12, color: Color(0xFFFFD700)),
                                const SizedBox(width: 3),
                                Text(
                                  rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
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
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.2,
                            letterSpacing: -0.2,
                            shadows: [
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
                                  color:
                                      Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                            if (year.isNotEmpty &&
                                genres != null &&
                                genres.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                child: Container(
                                  width: 3,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.white.withValues(alpha: 0.3),
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
                                    color:
                                        Colors.white.withValues(alpha: 0.5),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
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
                            Container(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                            // Fill
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progressPercent.clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFED1C24),
                                      Color(0xFFFF4D4D),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _accentColor
                                          .withValues(alpha: 0.6),
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
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: isActive ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.25),
                        child: Center(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(
                                begin: 0.85, end: isActive ? 1.0 : 0.85),
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutBack,
                            builder: (context, scale, child) =>
                                Transform.scale(
                                    scale: scale, child: child),
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    Colors.white.withValues(alpha: 0.15),
                                border: Border.all(
                                  color:
                                      Colors.white.withValues(alpha: 0.4),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: 0.4),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                      sigmaX: 10, sigmaY: 10),
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
            ),
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
        errorWidget: (context, url, error) =>
            _buildPlaceholder(item.name),
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
            duration: const Duration(milliseconds: 200),
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
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
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
        child: Center(
          child: Icon(
            isLeft
                ? Icons.chevron_left_rounded
                : Icons.chevron_right_rounded,
            size: 20,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}
