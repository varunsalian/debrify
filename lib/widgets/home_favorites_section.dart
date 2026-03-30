import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/storage_service.dart';
import '../services/main_page_bridge.dart';
import '../services/playlist_player_service.dart';
import '../screens/playlist_content_view_screen.dart';
import 'home_focus_controller.dart';

/// Premium OTT-style horizontal scrollable favorites section for the home screen
class HomeFavoritesSection extends StatefulWidget {
  final HomeFocusController? focusController;
  final VoidCallback? onRequestFocusAbove;
  final VoidCallback? onRequestFocusBelow;
  final bool isTelevision;
  final VoidCallback? onChanged;

  const HomeFavoritesSection({
    super.key,
    this.focusController,
    this.onRequestFocusAbove,
    this.onRequestFocusBelow,
    this.isTelevision = false,
    this.onChanged,
  });

  @override
  State<HomeFavoritesSection> createState() => HomeFavoritesSectionState();
}

class HomeFavoritesSectionState extends State<HomeFavoritesSection> {
  List<Map<String, dynamic>> _favoriteItems = [];
  Map<String, Map<String, dynamic>> _progressMap = {};
  bool _isLoading = true;
  String? _playingItemKey;

  final List<FocusNode> _cardFocusNodes = [];
  final ScrollController _scrollController = ScrollController();

  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  static const _accentColor = Color(0xFFED1C24);

  void reload() => _loadFavorites();

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
          _ensureFocusNodes();
          widget.focusController?.registerSection(
            HomeSection.favorites,
            hasItems: false,
            focusNodes: [],
          );
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

      // Sort by addedAt descending (newest first)
      favorites.sort((a, b) {
        final aTime = a['addedAt'] as int? ?? 0;
        final bTime = b['addedAt'] as int? ?? 0;
        return bTime.compareTo(aTime);
      });

      final posterOverrides = await StorageService.getAllPlaylistPosterOverrides();
      for (var item in favorites) {
        final key = StorageService.getPlaylistItemUniqueKey(item);
        final override = posterOverrides[key];
        if (override != null && override.isNotEmpty) {
          item['posterUrl'] = override;
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
      widget.onChanged?.call();
    }
  }

  Future<void> _playItem(Map<String, dynamic> item) async {
    String tapAction = await StorageService.getHomeFavoritesTapAction();
    if (tapAction == 'choose') {
      if (!mounted) return;
      final title = (item['title'] as String?) ?? 'Unknown';
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                  _FavMenuItem(
                    icon: Icons.play_circle_filled_rounded,
                    label: 'Play',
                    subtitle: 'Start playback',
                    color: const Color(0xFF10B981),
                    onTap: () => Navigator.pop(context, 'play'),
                    autofocus: true,
                    isTelevision: widget.isTelevision,
                  ),
                  _FavMenuItem(
                    icon: Icons.folder_open_rounded,
                    label: 'View Files',
                    subtitle: 'Browse folder contents',
                    color: const Color(0xFF818CF8),
                    onTap: () => Navigator.pop(context, 'view_files'),
                    isTelevision: widget.isTelevision,
                  ),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                  _FavMenuItem(
                    icon: Icons.heart_broken_rounded,
                    label: 'Remove from Favorites',
                    subtitle: 'Remove from your favorites list',
                    color: const Color(0xFFEF4444),
                    onTap: () => Navigator.pop(context, 'remove'),
                    isTelevision: widget.isTelevision,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
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
    setState(() => _playingItemKey = dedupeKey);

    try {
      await PlaylistPlayerService.play(context, item);
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

  (String badge, Color color, String name) _providerInfo(String provider) {
    switch (provider.toLowerCase()) {
      case 'torbox':
        return ('TB', const Color(0xFF3B82F6), 'Torbox');
      case 'pikpak':
        return ('PP', const Color(0xFFF59E0B), 'PikPak');
      default:
        return ('RD', const Color(0xFF10B981), 'Real-Debrid');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _favoriteItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(),
        const SizedBox(height: 8),
        // ── Horizontal card row ──
        Builder(
          builder: (context) {
            final isMobile = MediaQuery.of(context).size.width < 600;
            return SizedBox(
          height: isMobile ? 200.0 : 220.0,
          child: Stack(
            children: [
              // Skip ShaderMask on TV for GPU performance
              if (widget.isTelevision)
                ListView.builder(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.only(left: 16, top: 8, bottom: 8),
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
                    padding:
                        const EdgeInsets.only(left: 16, top: 8, bottom: 8),
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
        );
          },
        ),
      ],
    );
  }

  Widget _buildSectionHeader() {
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
            'Favorites',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.75),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_favoriteItems.length}',
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
      allFocusNodes: _cardFocusNodes,
      isTelevision: widget.isTelevision,
      onFocusChanged: (focused, idx) {
        if (focused) {
          widget.focusController
              ?.saveLastFocusedIndex(HomeSection.favorites, idx);
        }
      },
      child: (isFocused, isHovered) {
        final isActive = isFocused || isHovered;
        final isHero = index == 0;

        return widget.isTelevision
          ? Transform.scale(
              scale: isActive ? 1.05 : 1.0,
              child: Builder(
            builder: (context) {
              final sw = MediaQuery.of(context).size.width;
              final isMobile = sw < 600;
              return Container(
            width: isMobile
                ? (isHero ? sw * 0.82 : sw * 0.7)
                : (isHero ? 350 : 280),
            height: isMobile
                ? (isHero ? 180.0 : 155.0)
                : (isHero ? 200.0 : 170),
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive
                    ? Colors.white.withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.08),
                width: isActive ? 1.5 : 0.5,
              ),
            ),
            child: Stack(
                fit: StackFit.expand,
                children: [
                  // ── Poster image ──
                  if (posterUrl != null && posterUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: posterUrl,
                      memCacheWidth: 200,
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

                  // ── Badge (top right) ──
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 10, color: Color(0xFFFFD700)),
                          const SizedBox(width: 2),
                          Text(
                            providerInfo.$1,
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
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.2,
                            letterSpacing: -0.2,
                            shadows: widget.isTelevision ? null : const [
                              Shadow(color: Colors.black, blurRadius: 8),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          providerInfo.$3,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
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
                  if (isActive && !isPlaying)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.25),
                      child: Center(
                        child: Transform.scale(
                          scale: 1.0,
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
                    ),
                  ),
                ],
              ),
          );
            },
          ),
            )
          : TweenAnimationBuilder<double>(
          tween: Tween(begin: 1.0, end: isActive ? 1.05 : 1.0),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Builder(
            builder: (context) {
              final sw = MediaQuery.of(context).size.width;
              final isMobile = sw < 600;
              return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            width: isMobile
                ? (isHero ? sw * 0.82 : sw * 0.7)
                : (isHero ? 350 : 280),
            height: isMobile
                ? (isHero ? 180.0 : 155.0)
                : (isHero ? 200.0 : 170),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive
                    ? Colors.white.withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.08),
                width: isActive ? 1.5 : 0.5,
              ),
              boxShadow: widget.isTelevision ? null : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isActive ? 0.9 : 0.6),
                  blurRadius: isActive ? 30 : 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
                fit: StackFit.expand,
                children: [
                  // ── Poster image ──
                  if (posterUrl != null && posterUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: posterUrl,
                      memCacheWidth: 200,
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

                  // ── Badge (top right) ──
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 10, color: Color(0xFFFFD700)),
                          const SizedBox(width: 2),
                          Text(
                            providerInfo.$1,
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
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.2,
                            letterSpacing: -0.2,
                            shadows: widget.isTelevision ? null : const [
                              Shadow(color: Colors.black, blurRadius: 8),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          providerInfo.$3,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
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
                                child: widget.isTelevision
                                  ? Container(
                                      color: Colors.black.withValues(alpha: 0.6),
                                      child: const Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 30,
                                      ),
                                    )
                                  : BackdropFilter(
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
          );
            },
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
  final List<FocusNode>? allFocusNodes;
  final bool isTelevision;

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
    this.allFocusNodes,
    this.isTelevision = false,
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
            duration: widget.isTelevision ? Duration.zero : const Duration(milliseconds: 200),
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

// ── Menu item for favorites action dialog ─────────────────────────────────────

class _FavMenuItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool autofocus;
  final bool isTelevision;

  const _FavMenuItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.autofocus = false,
    this.isTelevision = false,
  });

  @override
  State<_FavMenuItem> createState() => _FavMenuItemState();
}

class _FavMenuItemState extends State<_FavMenuItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: _focused ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: _focused ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.icon, size: 18, color: widget.color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(widget.subtitle, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4))),
              ],
            ),
          ),
        ],
      ),
    );

    return InkWell(
      autofocus: widget.autofocus,
      canRequestFocus: true,
      onTap: widget.onTap,
      onFocusChange: (focused) => setState(() => _focused = focused),
      borderRadius: BorderRadius.circular(8),
      child: widget.isTelevision
          ? content
          : AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: _focused ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: _focused ? 0.2 : 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.icon, size: 18, color: widget.color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text(widget.subtitle, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
