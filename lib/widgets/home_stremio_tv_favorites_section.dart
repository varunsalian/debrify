import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  List<StremioTvChannel> _favoriteChannels = [];
  bool _isLoading = true;
  int _rotationMinutes = 60;

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
    widget.focusController
        ?.unregisterSection(HomeSection.stremioTvFavorites);
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
      final favoriteIds =
          await StorageService.getStremioTvFavoriteChannelIds();

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

      // Discover all channels and filter to favorites
      final allChannels = await _service.discoverChannels();
      final favorites =
          allChannels.where((ch) => favoriteIds.contains(ch.id)).toList();

      // Load items for favorite channels
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
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _updateScrollIndicators());
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
        content:
            Text('Remove "${channel.displayName}" from your favorites?'),
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

    // StremioTvScreen not mounted — notify and switch tab
    MainPageBridge.notifyStremioTvChannelToAutoPlay(channel.id);
    MainPageBridge.switchTab?.call(9); // Stremio TV tab
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _favoriteChannels.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color:
                          theme.colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.smart_display_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.tertiary,
                  ],
                ).createShader(bounds),
                child: const Text(
                  'Stremio TV',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(width: 10),
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
                  '${_favoriteChannels.length}',
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
        // Horizontal scrolling favorites
        SizedBox(
          height: 115,
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
                    stops: [
                      0.0,
                      _canScrollLeft ? 0.03 : 0.0,
                      _canScrollRight ? 0.97 : 1.0,
                      1.0,
                    ],
                  ).createShader(bounds);
                },
                blendMode: BlendMode.dstIn,
                child: ListView.builder(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: _favoriteChannels.length,
                  itemBuilder: (context, index) {
                    final channel = _favoriteChannels[index];
                    final focusNode = index < _cardFocusNodes.length
                        ? _cardFocusNodes[index]
                        : null;
                    return _buildChannelCard(
                      channel,
                      index: index,
                      focusNode: focusNode,
                      onLongPress: () => _confirmRemoveFavorite(channel),
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
                  child: Center(
                    child: Icon(
                      Icons.chevron_left_rounded,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              if (_canScrollRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChannelCard(
    StremioTvChannel channel, {
    required int index,
    FocusNode? focusNode,
    VoidCallback? onLongPress,
  }) {
    final theme = Theme.of(context);
    final nowPlaying = _service.getNowPlaying(
      channel,
      rotationMinutes: _rotationMinutes,
    );

    Widget card = Container(
      width: 150,
      margin: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openChannel(channel),
          onLongPress: onLongPress,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surfaceContainerLow,
              border: Border.all(
                color:
                    theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster thumbnail
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                  child: SizedBox(
                    height: 60,
                    width: double.infinity,
                    child: nowPlaying?.item.poster != null
                        ? CachedNetworkImage(
                            imageUrl: nowPlaying!.item.poster!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: theme
                                  .colorScheme.surfaceContainerHighest,
                              child: const Center(
                                child: Icon(Icons.movie_rounded, size: 20),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: theme
                                  .colorScheme.surfaceContainerHighest,
                              child: const Center(
                                child: Icon(
                                  Icons.broken_image_rounded,
                                  size: 20,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            color:
                                theme.colorScheme.surfaceContainerHighest,
                            child: const Center(
                              child: Icon(Icons.smart_display_rounded,
                                  size: 20),
                            ),
                          ),
                  ),
                ),
                // Channel info
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CH ${channel.channelNumber.toString().padLeft(2, '0')}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        nowPlaying?.item.name ?? channel.displayName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Wrap with Focus for DPAD navigation
    if (widget.isTelevision && focusNode != null) {
      card = Focus(
        focusNode: focusNode,
        onFocusChange: (hasFocus) {
          if (hasFocus) {
            widget.focusController?.saveLastFocusedIndex(
              HomeSection.stremioTvFavorites,
              index,
            );
            // Scroll to make visible
            if (_scrollController.hasClients) {
              final offset = index * 158.0; // 150 width + 8 margin
              _scrollController.animateTo(
                offset.clamp(0, _scrollController.position.maxScrollExtent),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          }
          setState(() {});
        },
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              widget.onRequestFocusAbove?.call();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              widget.onRequestFocusBelow?.call();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              if (index > 0 && _cardFocusNodes.length > index - 1) {
                _cardFocusNodes[index - 1].requestFocus();
                return KeyEventResult.handled;
              }
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              if (index < _cardFocusNodes.length - 1) {
                _cardFocusNodes[index + 1].requestFocus();
                return KeyEventResult.handled;
              }
            }
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter) {
              _openChannel(channel);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedScale(
          scale: focusNode.hasFocus ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: card,
        ),
      );
    }

    return card;
  }
}
