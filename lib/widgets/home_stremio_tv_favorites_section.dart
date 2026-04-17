import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stremio_addon.dart';
import '../models/stremio_tv/stremio_tv_channel.dart';
import '../screens/stremio_tv/stremio_tv_service.dart';
import '../services/main_page_bridge.dart';
import '../services/storage_service.dart';
import 'home_focus_controller.dart';

/// Horizontal scrollable Stremio TV channel favorites section for the home screen.
class HomeStremioTvFavoritesSection extends StatefulWidget {
  final HomeFocusController? focusController;
  final VoidCallback? onRequestFocusAbove;
  final VoidCallback? onRequestFocusBelow;
  final bool isTelevision;

  const HomeStremioTvFavoritesSection({
    super.key,
    this.focusController,
    this.onRequestFocusAbove,
    this.onRequestFocusBelow,
    this.isTelevision = false,
  });

  @override
  State<HomeStremioTvFavoritesSection> createState() =>
      _HomeStremioTvFavoritesSectionState();
}

class _HomeStremioTvFavoritesSectionState
    extends State<HomeStremioTvFavoritesSection> {
  static const _accentColor = Color(0xFFED1C24);
  List<StremioTvChannel> _favoriteChannels = [];
  bool _isLoading = true;
  int _rotationMinutes = 90;
  int _seriesRotationMinutes = 45;

  int _rotationFor(StremioTvChannel channel) =>
      channel.type == 'series' ? _seriesRotationMinutes : _rotationMinutes;

  final StremioTvService _service = StremioTvService.instance;
  final List<FocusNode> _cardFocusNodes = [];
  final ScrollController _scrollController = ScrollController();

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
    widget.focusController?.unregisterSection(HomeSection.stremioTvFavorites);
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    _scrollController.removeListener(_updateScrollIndicators);
    _scrollController.dispose();
    super.dispose();
  }

  void _ensureFocusNodes() {
    while (_cardFocusNodes.length < _favoriteChannels.length) {
      _cardFocusNodes.add(
        FocusNode(
          debugLabel: 'stremio_tv_channel_card_${_cardFocusNodes.length}',
        ),
      );
    }
    while (_cardFocusNodes.length > _favoriteChannels.length) {
      _cardFocusNodes.removeLast().dispose();
    }
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);

    try {
      _rotationMinutes = await StorageService.getStremioTvRotationMinutes();
      _seriesRotationMinutes =
          await StorageService.getStremioTvSeriesRotationMinutes();
      final favoriteIds = await StorageService.getStremioTvFavoriteChannelIds();

      if (favoriteIds.isEmpty) {
        if (mounted) {
          setState(() {
            _favoriteChannels = [];
            _isLoading = false;
          });
          _ensureFocusNodes();
          widget.focusController?.registerSection(
            HomeSection.stremioTvFavorites,
            hasItems: false,
            focusNodes: [],
          );
        }
        return;
      }

      final allChannels = await _service.discoverChannels();
      final favorites = allChannels
          .where((ch) => favoriteIds.contains(ch.id))
          .toList();

      await _service.loadAllChannelItems(favorites);

      if (mounted) {
        setState(() {
          _favoriteChannels = favorites;
          _isLoading = false;
        });
        _ensureFocusNodes();
        widget.focusController?.registerSection(
          HomeSection.stremioTvFavorites,
          hasItems: _favoriteChannels.isNotEmpty,
          focusNodes: _cardFocusNodes,
        );
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _updateScrollIndicators(),
        );
      }
    } catch (e) {
      debugPrint('Error loading Stremio TV favorites: $e');
      if (mounted) {
        setState(() {
          _favoriteChannels = [];
          _isLoading = false;
        });
        _ensureFocusNodes();
        widget.focusController?.registerSection(
          HomeSection.stremioTvFavorites,
          hasItems: false,
          focusNodes: [],
        );
      }
    }
  }

  Future<void> _confirmRemoveFavorite(StremioTvChannel channel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from Favorites?'),
        content: Text('Remove "${channel.displayName}" from your favorites?'),
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
      await StorageService.setStremioTvChannelFavorited(channel.id, false);
      HapticFeedback.mediumImpact();
      _loadFavorites();
    }
  }

  void _openChannel(StremioTvChannel channel) {
    if (MainPageBridge.watchStremioTvChannel != null) {
      MainPageBridge.watchStremioTvChannel!(channel.id);
      return;
    }

    MainPageBridge.notifyStremioTvChannelToAutoPlay(channel.id);
    MainPageBridge.switchTab?.call(9);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _favoriteChannels.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final rowHeight = isMobile ? 200.0 : 220.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(),
        const SizedBox(height: 8),
        SizedBox(
          height: rowHeight,
          child: Stack(
            children: [
              if (widget.isTelevision)
                ListView.builder(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
                  clipBehavior: Clip.none,
                  itemCount: _favoriteChannels.length,
                  itemBuilder: (context, index) {
                    final channel = _favoriteChannels[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        right: index < _favoriteChannels.length - 1 ? 16 : 0,
                      ),
                      child: _buildChannelCard(
                        channel,
                        index: index,
                        focusNode: index < _cardFocusNodes.length
                            ? _cardFocusNodes[index]
                            : null,
                        onLongPress: () => _confirmRemoveFavorite(channel),
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
                      stops: [
                        0.0,
                        _canScrollLeft ? 0.015 : 0.0,
                        _canScrollRight ? 0.985 : 1.0,
                        1.0,
                      ],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: ListView.builder(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
                    clipBehavior: Clip.none,
                    itemCount: _favoriteChannels.length,
                    itemBuilder: (context, index) {
                      final channel = _favoriteChannels[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          right: index < _favoriteChannels.length - 1 ? 16 : 0,
                        ),
                        child: _buildChannelCard(
                          channel,
                          index: index,
                          focusNode: index < _cardFocusNodes.length
                              ? _cardFocusNodes[index]
                              : null,
                          onLongPress: () => _confirmRemoveFavorite(channel),
                        ),
                      );
                    },
                  ),
                ),
              if (_canScrollLeft)
                const Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: _StremioScrollIndicator(
                    direction: _ScrollDirection.left,
                  ),
                ),
              if (_canScrollRight)
                const Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _StremioScrollIndicator(
                    direction: _ScrollDirection.right,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Divider(height: 1, thickness: 0.5, color: Color(0x14FFFFFF)),
        ),
        const SizedBox(height: 10),
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
            decoration: const BoxDecoration(
              color: _accentColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Stremio TV - Favorites',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.75),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_favoriteChannels.length}',
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

  Widget _buildChannelCard(
    StremioTvChannel channel, {
    required int index,
    FocusNode? focusNode,
    VoidCallback? onLongPress,
  }) {
    final nowPlaying = _service.getNowPlaying(
      channel,
      rotationMinutes: _rotationFor(channel),
    );
    final item = nowPlaying?.item;

    return _StremioTvCardWithFocus(
      onTap: () => _openChannel(channel),
      onLongPress: onLongPress,
      focusNode: focusNode,
      index: index,
      scrollController: _scrollController,
      onUpPressed: widget.onRequestFocusAbove,
      onDownPressed: widget.onRequestFocusBelow,
      allFocusNodes: _cardFocusNodes,
      isTelevision: widget.isTelevision,
      onFocusChanged: (focused, idx) {
        if (focused) {
          widget.focusController?.saveLastFocusedIndex(
            HomeSection.stremioTvFavorites,
            idx,
          );
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

        final year = item?.year ?? '';
        final rating = item?.imdbRating;
        final genres = item?.genres;
        final progress = nowPlaying?.progress;
        final cardContent = ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildBackdropImage(item),
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
              Positioned(
                top: 10,
                left: 10,
                child: _buildTypeBadge(channel.type),
              ),
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
              Positioned(
                bottom: progress != null ? 5 : 12,
                left: 12,
                right: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item?.name ?? channel.displayName,
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
                    Text(
                      channel.genre != null
                          ? 'CH ${channel.channelNumber.toString().padLeft(2, '0')} · ${channel.catalog.name} · ${channel.genre}'
                          : 'CH ${channel.channelNumber.toString().padLeft(2, '0')} · ${channel.catalog.name}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFFF7A80),
                        letterSpacing: 0.1,
                        shadows: widget.isTelevision
                            ? null
                            : const [
                                Shadow(color: Colors.black, blurRadius: 6),
                              ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (year.isNotEmpty)
                          Text(
                            year,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
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
                    if (nowPlaying != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        nowPlaying.progressText,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (progress != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SizedBox(
                    height: 3.5,
                    child: Stack(
                      children: [
                        Container(color: Colors.white.withValues(alpha: 0.1)),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [_accentColor, Color(0xFFFF4D4D)],
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

  Widget _buildBackdropImage(StremioMeta? item) {
    final imageUrl = item?.background ?? item?.poster;
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
        errorWidget: (context, url, error) => _buildFallbackBackdrop(),
      );
    }
    return _buildFallbackBackdrop();
  }

  Widget _buildFallbackBackdrop() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF261317), Color(0xFF0D1117)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.live_tv_rounded,
          size: 28,
          color: Colors.white.withValues(alpha: 0.16),
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    final color = type == 'series'
        ? const Color(0xFFFF6B72)
        : const Color(0xFFFFA3A8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        type.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _StremioTvCardWithFocus extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final int index;
  final ScrollController? scrollController;
  final VoidCallback? onUpPressed;
  final VoidCallback? onDownPressed;
  final void Function(bool focused, int index)? onFocusChanged;
  final Widget Function(bool isFocused, bool isHovered) child;
  final List<FocusNode>? allFocusNodes;
  final bool isTelevision;

  const _StremioTvCardWithFocus({
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.focusNode,
    this.index = 0,
    this.scrollController,
    this.onUpPressed,
    this.onDownPressed,
    this.onFocusChanged,
    this.allFocusNodes,
    this.isTelevision = false,
  });

  @override
  State<_StremioTvCardWithFocus> createState() =>
      _StremioTvCardWithFocusState();
}

class _StremioTvCardWithFocusState extends State<_StremioTvCardWithFocus> {
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

enum _ScrollDirection { left, right }

class _StremioScrollIndicator extends StatelessWidget {
  final _ScrollDirection direction;

  const _StremioScrollIndicator({required this.direction});

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
