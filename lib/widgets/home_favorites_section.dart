import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/storage_service.dart';
import '../services/main_page_bridge.dart';
import '../screens/playlist_content_view_screen.dart';
import 'home_focus_controller.dart';

/// Horizontal scrollable favorites section for the home screen
class HomeFavoritesSection extends StatefulWidget {
  final HomeFocusController? focusController;
  final VoidCallback? onRequestFocusAbove;
  final VoidCallback? onRequestFocusBelow;
  final bool isTelevision;

  const HomeFavoritesSection({
    super.key,
    this.focusController,
    this.onRequestFocusAbove,
    this.onRequestFocusBelow,
    this.isTelevision = false,
  });

  @override
  State<HomeFavoritesSection> createState() => _HomeFavoritesSectionState();
}

class _HomeFavoritesSectionState extends State<HomeFavoritesSection> {
  List<Map<String, dynamic>> _favoriteItems = [];
  Map<String, Map<String, dynamic>> _progressMap = {};
  bool _isLoading = true;
  String? _playingItemKey;

  // Focus management for DPAD navigation
  final List<FocusNode> _cardFocusNodes = [];
  final ScrollController _scrollController = ScrollController();

  // Scroll indicators
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollIndicators);
    _loadFavorites();
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

  @override
  void dispose() {
    // Unregister from controller
    widget.focusController?.unregisterSection(HomeSection.favorites);
    // Dispose focus nodes
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    _scrollController.removeListener(_updateScrollIndicators);
    _scrollController.dispose();
    super.dispose();
  }

  /// Ensure we have the right number of focus nodes for current items
  void _ensureFocusNodes() {
    // Add nodes if needed
    while (_cardFocusNodes.length < _favoriteItems.length) {
      _cardFocusNodes.add(FocusNode(debugLabel: 'favorite_card_${_cardFocusNodes.length}'));
    }
    // Remove extra nodes if needed
    while (_cardFocusNodes.length > _favoriteItems.length) {
      _cardFocusNodes.removeLast().dispose();
    }
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);

    try {
      // Get all playlist items
      final allItems = await StorageService.getPlaylistItemsRaw();

      // Get favorite keys
      final favoriteKeys = await StorageService.getPlaylistFavoriteKeys();

      if (favoriteKeys.isEmpty) {
        if (mounted) {
          setState(() {
            _favoriteItems = [];
            _isLoading = false;
          });
        }
        return;
      }

      // Filter to only favorited items
      final favorites = <Map<String, dynamic>>[];
      for (final item in allItems) {
        final dedupeKey = StorageService.computePlaylistDedupeKey(item);
        if (favoriteKeys.contains(dedupeKey)) {
          favorites.add(item);
        }
      }

      // Apply poster overrides for items that have saved custom posters
      for (var item in favorites) {
        final posterOverride = await StorageService.getPlaylistPosterOverride(item);
        if (posterOverride != null && posterOverride.isNotEmpty) {
          item['posterUrl'] = posterOverride;
        }
      }

      // Load progress data for all favorites using the same method as PlaylistScreen
      final progressMap = await StorageService.buildPlaylistProgressMap(favorites);

      if (mounted) {
        setState(() {
          _favoriteItems = favorites;
          _progressMap = progressMap;
          _isLoading = false;
        });
        // Update focus nodes and register with controller
        _ensureFocusNodes();
        // Check scroll indicators after frame
        WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollIndicators());
        widget.focusController?.registerSection(
          HomeSection.favorites,
          hasItems: _favoriteItems.isNotEmpty,
          focusNodes: _cardFocusNodes,
        );
      }
    } catch (e) {
      debugPrint('Error loading favorites: $e');
      if (mounted) {
        setState(() {
          _favoriteItems = [];
          _isLoading = false;
        });
        // Register as empty section
        _ensureFocusNodes();
        widget.focusController?.registerSection(
          HomeSection.favorites,
          hasItems: false,
          focusNodes: [],
        );
      }
    }
  }

  Future<void> _confirmRemoveFavorite(Map<String, dynamic> item) async {
    final title = (item['title'] as String?) ?? 'this item';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from Favorites?'),
        content: Text('Remove "$title" from your favorites?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await StorageService.setPlaylistItemFavorited(item, false);
      HapticFeedback.mediumImpact();
      _loadFavorites();
    }
  }

  Future<void> _playItem(Map<String, dynamic> item) async {
    // Check user's preferred tap action
    String tapAction = await StorageService.getHomeFavoritesTapAction();
    if (tapAction == 'choose') {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'play'),
              child: const Row(
                children: [
                  Icon(Icons.play_arrow_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('Play'),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'view_files'),
              child: const Row(
                children: [
                  Icon(Icons.folder_open_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('View Files'),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'remove'),
              child: const Row(
                children: [
                  Icon(Icons.favorite_border_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('Remove from Favorites'),
                ],
              ),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'remove') {
        _confirmRemoveFavorite(item);
        return;
      }
      tapAction = choice;
    }
    if (tapAction == 'view_files') {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PlaylistContentViewScreen(
            playlistItem: item,
          ),
        ),
      );
      return;
    }

    final dedupeKey = StorageService.computePlaylistDedupeKey(item);

    // Check if play handler is available
    if (MainPageBridge.playPlaylistItem == null) {
      // PlaylistScreen not mounted - switch to playlist tab first
      MainPageBridge.notifyPlaylistItemToAutoPlay(item);
      MainPageBridge.switchTab?.call(1); // Playlist tab
      return;
    }

    setState(() => _playingItemKey = dedupeKey);

    try {
      await MainPageBridge.playPlaylistItem!(item);
    } catch (e) {
      debugPrint('Error playing item: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to play: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _playingItemKey = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't show anything if loading or no favorites
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    if (_favoriteItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Premium section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: [
              // Glowing icon container
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.star_rounded,
                  size: 18,
                  color: Color(0xFFFFD700),
                ),
              ),
              const SizedBox(width: 12),
              // Gradient title
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ).createShader(bounds),
                child: const Text(
                  'Favorites',
                  style: TextStyle(
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Text(
                  '${_favoriteItems.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ),
              const Spacer(),
              // Refresh button with hover effect
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _loadFavorites,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Horizontal scrolling favorites with edge fade and scroll indicators
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
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  clipBehavior: Clip.none,
                  itemCount: _favoriteItems.length,
                  itemBuilder: (context, index) {
                    final item = _favoriteItems[index];
                    final dedupeKey = StorageService.computePlaylistDedupeKey(item);
                    final progress = _progressMap[dedupeKey];
                    final isPlaying = _playingItemKey == dedupeKey;

                    return Padding(
                      padding: EdgeInsets.only(right: index < _favoriteItems.length - 1 ? 14 : 0),
                      child: _buildFavoriteCard(
                        item: item,
                        progress: progress,
                        isPlaying: isPlaying,
                        onTap: () => _playItem(item),
                        onLongPress: () => _confirmRemoveFavorite(item),
                        index: index,
                        focusNode: index < _cardFocusNodes.length ? _cardFocusNodes[index] : null,
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
                  child: _ScrollIndicator(direction: _ScrollDirection.left, accentColor: const Color(0xFFFFD700)),
                ),
              // Right scroll indicator
              if (_canScrollRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _ScrollIndicator(direction: _ScrollDirection.right, accentColor: const Color(0xFFFFD700)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFavoriteCard({
    required Map<String, dynamic> item,
    Map<String, dynamic>? progress,
    bool isPlaying = false,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    bool autofocus = false,
    int index = 0,
    FocusNode? focusNode,
  }) {
    final String title = (item['title'] as String?) ?? 'Unknown';
    final String? posterUrl = item['posterUrl'] as String?;
    final String provider =
        ((item['provider'] as String?) ?? 'realdebrid').toLowerCase();

    // Calculate progress percentage
    double? progressPercent;
    if (progress != null) {
      final position = progress['position'] as int?;
      final duration = progress['duration'] as int?;
      if (position != null && duration != null && duration > 0) {
        progressPercent = position / duration;
      }
    }

    // Provider badge text
    String providerBadge;
    Color providerColor;
    switch (provider) {
      case 'torbox':
        providerBadge = 'TB';
        providerColor = const Color(0xFF3B82F6);
        break;
      case 'pikpak':
        providerBadge = 'PP';
        providerColor = const Color(0xFFF59E0B);
        break;
      default:
        providerBadge = 'RD';
        providerColor = const Color(0xFF10B981);
    }

    return _FavoriteCardWithFocus(
      onTap: isPlaying ? null : onTap,
      onLongPress: onLongPress,
      autofocus: autofocus,
      focusNode: focusNode,
      index: index,
      totalCount: _favoriteItems.length,
      scrollController: _scrollController,
      onUpPressed: widget.onRequestFocusAbove,
      onDownPressed: widget.onRequestFocusBelow,
      onFocusChanged: (focused, idx) {
        if (focused) {
          widget.focusController?.saveLastFocusedIndex(HomeSection.favorites, idx);
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
                color: isActive ? const Color(0xFFE50914) : Colors.white.withValues(alpha: 0.1),
                width: isActive ? 2.5 : 1,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: const Color(0xFFE50914).withValues(alpha: 0.5),
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
                  // Poster image or placeholder
                  if (posterUrl != null && posterUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: posterUrl,
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
                      errorWidget: (context, url, error) => _buildPlaceholder(title),
                    )
                  else
                    _buildPlaceholder(title),

                  // Gradient overlay for text readability
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

                  // Provider badge (top-left) with glassmorphism
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: providerColor,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: providerColor.withValues(alpha: 0.4),
                            blurRadius: 8,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Text(
                        providerBadge,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                  // Favorite star (top-right) with glow
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                  ),

                  // Title (bottom)
                  Positioned(
                    bottom: progressPercent != null ? 14 : 10,
                    left: 10,
                    right: 10,
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.2,
                        shadows: [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Progress bar (bottom) with gradient
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
                          widthFactor: progressPercent,
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFFE50914), Color(0xFFFF6B6B)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Loading overlay when playing
                  if (isPlaying)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFFE50914),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Play icon overlay - only show on hover/focus
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: isActive && !isPlaying ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Center(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.8, end: isActive ? 1.0 : 0.8),
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutBack,
                          builder: (context, scale, child) {
                            return Transform.scale(scale: scale, child: child);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE50914),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFE50914).withValues(alpha: 0.6),
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

/// Focus-aware wrapper for favorite cards with DPAD/TV support
class _FavoriteCardWithFocus extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final FocusNode? focusNode;
  final int index;
  final int totalCount;
  final ScrollController? scrollController;
  final VoidCallback? onUpPressed;
  final VoidCallback? onDownPressed;
  final void Function(bool focused, int index)? onFocusChanged;
  final Widget Function(bool isFocused, bool isHovered) child;

  const _FavoriteCardWithFocus({
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.autofocus = false,
    this.focusNode,
    this.index = 0,
    this.totalCount = 1,
    this.scrollController,
    this.onUpPressed,
    this.onDownPressed,
    this.onFocusChanged,
  });

  @override
  State<_FavoriteCardWithFocus> createState() => _FavoriteCardWithFocusState();
}

class _FavoriteCardWithFocusState extends State<_FavoriteCardWithFocus> {
  bool _isFocused = false;
  bool _isHovered = false;
  final GlobalKey _cardKey = GlobalKey();

  void _onFocusChange(bool focused) {
    setState(() => _isFocused = focused);
    widget.onFocusChanged?.call(focused, widget.index);

    // Scroll card into view when focused
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
      // Select/Enter/GameButtonA - activate the card
      if (event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.gameButtonA) {
        widget.onTap?.call();
        return KeyEventResult.handled;
      }

      // Arrow Up - go to previous section
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        widget.onUpPressed?.call();
        return KeyEventResult.handled;
      }

      // Arrow Down - go to next section
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        widget.onDownPressed?.call();
        return KeyEventResult.handled;
      }

      // Arrow Left/Right - let Flutter's directional focus handle it
      // (FocusTraversalGroup will move to adjacent cards)
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
        autofocus: widget.autofocus,
        onFocusChange: _onFocusChange,
        onKeyEvent: _handleKeyEvent,
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
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
      child: AnimatedOpacity(
        opacity: 1.0,
        duration: const Duration(milliseconds: 200),
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
                isLeft ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                size: 16,
                color: accentColor.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
