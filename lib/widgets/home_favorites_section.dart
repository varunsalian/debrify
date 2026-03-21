import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/storage_service.dart';
import '../services/main_page_bridge.dart';
import '../screens/playlist_content_view_screen.dart';
import 'home_focus_controller.dart';

/// Premium OTT-style horizontal scrollable favorites section for the home screen
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

  final List<FocusNode> _cardFocusNodes = [];
  final ScrollController _scrollController = ScrollController();

  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  static const _accentColor = Color(0xFFFFD700);

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
    widget.focusController?.unregisterSection(HomeSection.favorites);
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    _scrollController.removeListener(_updateScrollIndicators);
    _scrollController.dispose();
    super.dispose();
  }

  void _ensureFocusNodes() {
    while (_cardFocusNodes.length < _favoriteItems.length) {
      _cardFocusNodes
          .add(FocusNode(debugLabel: 'favorite_card_${_cardFocusNodes.length}'));
    }
    while (_cardFocusNodes.length > _favoriteItems.length) {
      _cardFocusNodes.removeLast().dispose();
    }
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);

    try {
      final allItems = await StorageService.getPlaylistItemsRaw();
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

      final favorites = <Map<String, dynamic>>[];
      for (final item in allItems) {
        final dedupeKey = StorageService.computePlaylistDedupeKey(item);
        if (favoriteKeys.contains(dedupeKey)) {
          favorites.add(item);
        }
      }

      for (var item in favorites) {
        final posterOverride =
            await StorageService.getPlaylistPosterOverride(item);
        if (posterOverride != null && posterOverride.isNotEmpty) {
          item['posterUrl'] = posterOverride;
        }
      }

      final progressMap =
          await StorageService.buildPlaylistProgressMap(favorites);

      if (mounted) {
        setState(() {
          _favoriteItems = favorites;
          _progressMap = progressMap;
          _isLoading = false;
        });
        _ensureFocusNodes();
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _updateScrollIndicators());
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

    if (MainPageBridge.playPlaylistItem == null) {
      MainPageBridge.notifyPlaylistItemToAutoPlay(item);
      MainPageBridge.switchTab?.call(1);
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

  // ── Provider info ─────────────────────────────────────────────────────────

  (String badge, Color color) _providerInfo(String provider) {
    switch (provider.toLowerCase()) {
      case 'torbox':
        return ('TB', const Color(0xFF3B82F6));
      case 'pikpak':
        return ('PP', const Color(0xFFF59E0B));
      default:
        return ('RD', const Color(0xFF10B981));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _favoriteItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ──
        _buildSectionHeader(),
        const SizedBox(height: 12),
        // ── Horizontal card row ──
        SizedBox(
          height: 195,
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
                  itemCount: _favoriteItems.length,
                  itemBuilder: (context, index) {
                    final item = _favoriteItems[index];
                    final dedupeKey =
                        StorageService.computePlaylistDedupeKey(item);
                    final progress = _progressMap[dedupeKey];
                    final isPlaying = _playingItemKey == dedupeKey;

                    return Padding(
                      padding: EdgeInsets.only(
                          right:
                              index < _favoriteItems.length - 1 ? 16 : 0),
                      child: _buildFavoriteCard(
                        item: item,
                        progress: progress,
                        isPlaying: isPlaying,
                        onTap: () => _playItem(item),
                        onLongPress: () => _confirmRemoveFavorite(item),
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
        ),
      ],
    ),
    );
  }

  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
      child: Row(
        children: [
          // Star icon
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFD700), Color(0xFFF59E0B)],
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
              child: Icon(Icons.star_rounded, size: 16, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Favorites',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.95),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${_favoriteItems.length}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Landscape card ────────────────────────────────────────────────────────

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
    final providerInfo = _providerInfo(provider);

    double? progressPercent;
    if (progress != null) {
      final position = progress['position'] as int?;
      final duration = progress['duration'] as int?;
      if (position != null && duration != null && duration > 0) {
        progressPercent = position / duration;
      }
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
          widget.focusController
              ?.saveLastFocusedIndex(HomeSection.favorites, idx);
        }
      },
      child: (isFocused, isHovered) {
        final isActive = isFocused || isHovered;

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
                        color: _accentColor.withValues(alpha: 0.35),
                        blurRadius: 24,
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
                  // ── Poster image ──
                  if (posterUrl != null && posterUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: posterUrl,
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
                          _buildPlaceholder(title),
                    )
                  else
                    _buildPlaceholder(title),

                  // ── Cinematic gradient ──
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

                  // ── Top badges ──
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Row(
                      children: [
                        // Provider badge
                        _GlassPill(
                          color: providerInfo.$2,
                          child: Text(
                            providerInfo.$1,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Favorite star
                        _GlassPill(
                          child: const Icon(Icons.star_rounded,
                              size: 13, color: Color(0xFFFFD700)),
                        ),
                      ],
                    ),
                  ),

                  // ── Bottom info ──
                  Positioned(
                    bottom: progressPercent != null ? 5 : 12,
                    left: 12,
                    right: 12,
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.2,
                        letterSpacing: -0.2,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 8),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
                            Container(
                                color:
                                    Colors.white.withValues(alpha: 0.1)),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progressPercent,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFFFD700),
                                      Color(0xFFFFA500),
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

                  // ── Loading overlay ──
                  if (isPlaying)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.7),
                        child: Center(
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  _accentColor),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // ── Play overlay ──
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: isActive && !isPlaying ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.25),
                        child: Center(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(
                                begin: 0.85,
                                end: isActive ? 1.0 : 0.85),
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
                                color: Colors.white
                                    .withValues(alpha: 0.15),
                                border: Border.all(
                                  color: Colors.white
                                      .withValues(alpha: 0.4),
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
            Icon(Icons.movie_rounded,
                size: 28, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                title,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.3)),
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
  final Color? color;

  const _GlassPill({required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color?.withValues(alpha: 0.7) ??
                Colors.black.withValues(alpha: 0.45),
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
