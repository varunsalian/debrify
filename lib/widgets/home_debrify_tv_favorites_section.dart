import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/debrify_tv/channel.dart';
import '../services/storage_service.dart';
import '../services/debrify_tv_repository.dart';
import '../services/main_page_bridge.dart';
import 'home_focus_controller.dart';

/// Horizontal scrollable Debrify TV channel favorites section for the home screen
class HomeDebrifyTvFavoritesSection extends StatefulWidget {
  final HomeFocusController? focusController;
  final VoidCallback? onRequestFocusAbove;
  final VoidCallback? onRequestFocusBelow;
  final bool isTelevision;

  const HomeDebrifyTvFavoritesSection({
    super.key,
    this.focusController,
    this.onRequestFocusAbove,
    this.onRequestFocusBelow,
    this.isTelevision = false,
  });

  @override
  State<HomeDebrifyTvFavoritesSection> createState() =>
      _HomeDebrifyTvFavoritesSectionState();
}

class _HomeDebrifyTvFavoritesSectionState
    extends State<HomeDebrifyTvFavoritesSection> {
  List<DebrifyTvChannel> _favoriteChannels = [];
  bool _isLoading = true;

  // Focus management for DPAD navigation
  final List<FocusNode> _cardFocusNodes = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void dispose() {
    // Unregister from controller
    widget.focusController?.unregisterSection(HomeSection.tvFavorites);
    // Dispose focus nodes
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  /// Ensure we have the right number of focus nodes for current items
  void _ensureFocusNodes() {
    while (_cardFocusNodes.length < _favoriteChannels.length) {
      _cardFocusNodes.add(FocusNode(debugLabel: 'tv_channel_card_${_cardFocusNodes.length}'));
    }
    while (_cardFocusNodes.length > _favoriteChannels.length) {
      _cardFocusNodes.removeLast().dispose();
    }
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);

    try {
      // Get favorite channel IDs
      final favoriteIds = await StorageService.getDebrifyTvFavoriteChannelIds();

      if (favoriteIds.isEmpty) {
        if (mounted) {
          setState(() {
            _favoriteChannels = [];
            _isLoading = false;
          });
        }
        return;
      }

      // Get all channels
      final records = await DebrifyTvRepository.instance.fetchAllChannels();
      final allChannels =
          records.map(DebrifyTvChannel.fromRecord).toList(growable: false);

      // Filter to only favorited channels
      final favorites = allChannels
          .where((channel) => favoriteIds.contains(channel.id))
          .toList();

      if (mounted) {
        setState(() {
          _favoriteChannels = favorites;
          _isLoading = false;
        });
        // Update focus nodes and register with controller
        _ensureFocusNodes();
        widget.focusController?.registerSection(
          HomeSection.tvFavorites,
          hasItems: _favoriteChannels.isNotEmpty,
          focusNodes: _cardFocusNodes,
        );
      }
    } catch (e) {
      debugPrint('Error loading Debrify TV favorites: $e');
      if (mounted) {
        setState(() {
          _favoriteChannels = [];
          _isLoading = false;
        });
        // Register as empty section
        _ensureFocusNodes();
        widget.focusController?.registerSection(
          HomeSection.tvFavorites,
          hasItems: false,
          focusNodes: [],
        );
      }
    }
  }

  Future<void> _confirmRemoveFavorite(DebrifyTvChannel channel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from Favorites?'),
        content: Text('Remove "${channel.name}" from your favorites?'),
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
      await StorageService.setDebrifyTvChannelFavorited(channel.id, false);
      HapticFeedback.mediumImpact();
      _loadFavorites();
    }
  }

  void _openChannel(DebrifyTvChannel channel) {
    // Check if watch handler is available (DebrifyTVScreen is mounted)
    if (MainPageBridge.watchDebrifyTvChannel != null) {
      // Directly call the watch handler
      MainPageBridge.watchDebrifyTvChannel!(channel.id);
      return;
    }

    // DebrifyTVScreen not mounted - notify and switch tab
    MainPageBridge.notifyDebrifyTvChannelToAutoPlay(channel.id);
    // Switch to Debrify TV tab (tab index 3)
    MainPageBridge.switchTab?.call(3);
  }

  @override
  Widget build(BuildContext context) {
    // Don't show anything if loading or no favorites
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    if (_favoriteChannels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.tv_rounded,
                size: 18,
                color: const Color(0xFFE50914).withValues(alpha: 0.9),
              ),
              const SizedBox(width: 8),
              Text(
                'Debrify TV - Favorites',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              // Subtle hint for long-press
              Text(
                'Hold to remove',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _loadFavorites,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Horizontal scrolling favorites with DPAD support
        SizedBox(
          height: 100,
          child: ListView.separated(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            itemCount: _favoriteChannels.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final channel = _favoriteChannels[index];
              return _buildChannelCard(
                channel,
                index: index,
                focusNode: index < _cardFocusNodes.length ? _cardFocusNodes[index] : null,
                onLongPress: () => _confirmRemoveFavorite(channel),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChannelCard(
    DebrifyTvChannel channel, {
    int index = 0,
    FocusNode? focusNode,
    VoidCallback? onLongPress,
  }) {
    return _ChannelCardWithFocus(
      onTap: () => _openChannel(channel),
      onLongPress: onLongPress,
      focusNode: focusNode,
      index: index,
      totalCount: _favoriteChannels.length,
      scrollController: _scrollController,
      onUpPressed: widget.onRequestFocusAbove,
      onDownPressed: widget.onRequestFocusBelow,
      onFocusChanged: (focused, idx) {
        if (focused) {
          widget.focusController?.saveLastFocusedIndex(HomeSection.tvFavorites, idx);
        }
      },
      child: (isFocused, isHovered) {
        final isActive = isFocused || isHovered;

        return AnimatedScale(
          scale: isActive ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            width: 160,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(10),
              border: isActive
                  ? Border.all(color: const Color(0xFFE50914), width: 2)
                  : Border.all(
                      color: Colors.white.withValues(alpha: 0.1), width: 1),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: const Color(0xFFE50914).withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Stack(
              children: [
                // Main content
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Channel number badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE50914),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'CH ${channel.channelNumber > 0 ? channel.channelNumber : _favoriteChannels.indexOf(channel) + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Channel name
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          channel.name.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Star indicator
                Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: const Color(0xFFFFD700),
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                // TV icon indicator (top-left)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Icon(
                    Icons.live_tv_rounded,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Focus-aware wrapper for channel cards with DPAD/TV support
class _ChannelCardWithFocus extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final int index;
  final int totalCount;
  final ScrollController? scrollController;
  final VoidCallback? onUpPressed;
  final VoidCallback? onDownPressed;
  final void Function(bool focused, int index)? onFocusChanged;
  final Widget Function(bool isFocused, bool isHovered) child;

  const _ChannelCardWithFocus({
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.focusNode,
    this.index = 0,
    this.totalCount = 1,
    this.scrollController,
    this.onUpPressed,
    this.onDownPressed,
    this.onFocusChanged,
  });

  @override
  State<_ChannelCardWithFocus> createState() => _ChannelCardWithFocusState();
}

class _ChannelCardWithFocusState extends State<_ChannelCardWithFocus> {
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
