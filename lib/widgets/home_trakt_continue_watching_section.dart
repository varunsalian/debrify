import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../services/trakt/trakt_service.dart';
import '../services/trakt/trakt_item_transformer.dart';
import 'home_focus_controller.dart';

/// Trakt Continue Watching section for the home screen.
/// Shows two horizontal rows: one for movies, one for shows.
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

  static const _accentColor = Color(0xFFED1C24); // Trakt red

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
          FocusNode(debugLabel: 'trakt_cw_${widget.contentType}_${_cardFocusNodes.length}'));
    }
    while (_cardFocusNodes.length > _items.length) {
      _cardFocusNodes.removeLast().dispose();
    }
  }

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
        // Extract progress from raw items
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
        // For shows, extract per-show progress from the most recent episode
        for (final raw in rawItems) {
          if (raw is! Map<String, dynamic>) continue;
          final progress = raw['progress'] as num?;
          final show = raw['show'] as Map<String, dynamic>?;
          final ids = show?['ids'] as Map<String, dynamic>?;
          final imdbId = ids?['imdb'] as String?;
          if (imdbId != null && progress != null) {
            // Keep the first (most recent) progress per show
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

  void _onItemTap(StremioMeta item) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
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

  /// Browse: same as tapping an item in TraktResultsView.
  /// For movies, triggers a search via onItemSelected.
  /// For series, enters episode mode via onBrowseShow.
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

  /// Quick Play: same as Quick Play in TraktResultsView (onQuickPlay).
  /// For series, fetches next episode from Trakt first.
  void _quickPlayItem(StremioMeta item) async {
    int? season;
    int? episode;
    double? traktProgress = _traktProgressForItem(item);

    if (item.type == 'series') {
      final showId = item.imdbId ?? item.id;
      final next = await _traktService.fetchNextEpisode(showId);
      if (!mounted) return;
      if (next == null) {
        // No next episode (show complete or error) — fall back to browse
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _items.isEmpty) {
      return const SizedBox.shrink();
    }

    final isMovies = widget.contentType == 'movies';
    final title = isMovies ? 'Trakt Continue Watching' : 'Trakt Continue Watching Shows';
    final icon = isMovies ? Icons.movie_rounded : Icons.tv_rounded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: [
              // Icon container
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: _accentColor.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Icon(icon, size: 18, color: _accentColor),
              ),
              const SizedBox(width: 12),
              // Gradient title
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFFED1C24), Color(0xFFFF6B6B)],
                ).createShader(bounds),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Item count badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Text(
                  '${_items.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Horizontal scrolling cards
        SizedBox(
          height: 230,
          child: Stack(
            children: [
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
                    stops: const [0.0, 0.02, 0.98, 1.0],
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
                          right: index < _items.length - 1 ? 14 : 0),
                      child: _buildCard(
                        item: item,
                        progressPercent: progress != null ? progress / 100 : null,
                        index: index,
                        focusNode: index < _cardFocusNodes.length
                            ? _cardFocusNodes[index]
                            : null,
                      ),
                    );
                  },
                ),
              ),
              // Left scroll indicator
              if (_canScrollLeft)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: _ScrollIndicator(
                      direction: _ScrollDirection.left,
                      accentColor: _accentColor),
                ),
              // Right scroll indicator
              if (_canScrollRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _ScrollIndicator(
                      direction: _ScrollDirection.right,
                      accentColor: _accentColor),
                ),
            ],
          ),
        ),
      ],
    );
  }

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

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 1.0, end: isActive ? 1.08 : 1.0),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: 150,
            height: 210,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? _accentColor
                    : Colors.white.withValues(alpha: 0.1),
                width: isActive ? 2.5 : 1,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: _accentColor.withValues(alpha: 0.5),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isActive ? 10 : 11),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Poster image
                  if (item.poster != null && item.poster!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: item.poster!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: const Color(0xFF1A1A2E),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) =>
                          _buildPlaceholder(item.name),
                    )
                  else
                    _buildPlaceholder(item.name),

                  // Gradient overlay
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.6),
                            Colors.black.withValues(alpha: 0.95),
                          ],
                          stops: const [0.0, 0.4, 0.7, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // Trakt badge (top-left)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: _accentColor,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: _accentColor.withValues(alpha: 0.4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Text(
                        'TRAKT',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                  // Title (bottom)
                  Positioned(
                    bottom: progressPercent != null ? 14 : 10,
                    left: 10,
                    right: 10,
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.2,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 6),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Progress bar
                  if (progressPercent != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progressPercent.clamp(0.0, 1.0),
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xFFED1C24),
                                  Color(0xFFFF6B6B),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Play icon overlay on hover/focus
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: isActive ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Center(
                        child: TweenAnimationBuilder<double>(
                          tween:
                              Tween(begin: 0.8, end: isActive ? 1.0 : 0.8),
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutBack,
                          builder: (context, scale, child) {
                            return Transform.scale(
                                scale: scale, child: child);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _accentColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      _accentColor.withValues(alpha: 0.6),
                                  blurRadius: 16,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 28,
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

  Widget _buildPlaceholder(String title) {
    return Container(
      color: const Color(0xFF1E293B),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.movie_rounded,
              size: 32,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.5),
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

/// Focus-aware wrapper for Trakt cards with DPAD/TV support
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

/// Direction for scroll indicator
enum _ScrollDirection { left, right }

/// Subtle scroll indicator widget
class _ScrollIndicator extends StatelessWidget {
  final _ScrollDirection direction;
  final Color accentColor;

  const _ScrollIndicator({
    required this.direction,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isLeft = direction == _ScrollDirection.left;

    return IgnorePointer(
      child: Container(
        width: 28,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
            end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
            colors: [
              const Color(0xFF0F0F1A).withValues(alpha: 0.9),
              Colors.transparent,
            ],
          ),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isLeft
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              size: 16,
              color: accentColor.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}
