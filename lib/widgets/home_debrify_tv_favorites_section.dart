import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/debrify_tv/channel.dart';
import '../services/storage_service.dart';
import '../services/debrify_tv_repository.dart';
import '../services/main_page_bridge.dart';
import 'home_focus_controller.dart';

/// Accent color used throughout the Debrify TV section
const Color _accentColor = Color(0xFFE50914);

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
    widget.focusController?.unregisterSection(HomeSection.tvFavorites);
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
        // Check scroll indicators after frame
        WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollIndicators());
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
        // Premium section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: [
              // Glowing icon container
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
                child: const Icon(
                  Icons.tv_rounded,
                  size: 18,
                  color: _accentColor,
                ),
              ),
              const SizedBox(width: 12),
              // Gradient title
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [_accentColor, Color(0xFFFF6B6B)],
                ).createShader(bounds),
                child: const Text(
                  'Debrify TV',
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
        // Horizontal scrolling favorites with edge fade and scroll indicators
        SizedBox(
          height: 150,
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
                  itemCount: _favoriteChannels.length,
                  itemBuilder: (context, index) {
                    final channel = _favoriteChannels[index];
                    return Padding(
                      padding: EdgeInsets.only(right: index < _favoriteChannels.length - 1 ? 12 : 0),
                      child: _buildChannelCard(
                        channel,
                        index: index,
                        focusNode: index < _cardFocusNodes.length ? _cardFocusNodes[index] : null,
                        onLongPress: () => _confirmRemoveFavorite(channel),
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
                  child: _ScrollIndicator(direction: _ScrollDirection.left, accentColor: _accentColor),
                ),
              // Right scroll indicator
              if (_canScrollRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _ScrollIndicator(direction: _ScrollDirection.right, accentColor: _accentColor),
                ),
            ],
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
    final channelNum = channel.channelNumber > 0 ? channel.channelNumber : _favoriteChannels.indexOf(channel) + 1;

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

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 1.0, end: isActive ? 1.05 : 1.0),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            width: 240,
            height: 130,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF2D1B69),
                  _accentColor.withValues(alpha: 0.25),
                  const Color(0xFF0D0D1A),
                ],
                stops: const [0.0, 0.4, 1.0],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isActive
                    ? _accentColor.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.1),
                width: isActive ? 2 : 1,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: _accentColor.withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Stack(
                children: [
                  // Breathing glow decoration
                  Positioned(
                    top: -20,
                    right: -20,
                    child: _BreathingGlow(color: _accentColor),
                  ),
                  // Main content
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Channel number badge with gradient
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_accentColor, Color(0xFFB91C1C)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: _accentColor.withValues(alpha: 0.4),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Text(
                            'CH $channelNum',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Channel name
                        Text(
                          channel.name.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white.withValues(alpha: 0.95),
                            height: 1.2,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (channel.keywords.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          // Keyword chips with frosted glass styling
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: channel.keywords.take(3).map((keyword) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _accentColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: _accentColor.withValues(alpha: 0.25),
                                        width: 0.5,
                                      ),
                                    ),
                                    child: Text(
                                      keyword,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: _accentColor.withValues(alpha: 0.9),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Play overlay on focus
                  if (isActive)
                    Positioned.fill(
                      child: AnimatedOpacity(
                        opacity: isActive ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                          ),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _accentColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: _accentColor.withValues(alpha: 0.5),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 20,
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
}

/// Animated breathing glow decoration for channel cards
class _BreathingGlow extends StatefulWidget {
  final Color color;
  const _BreathingGlow({required this.color});

  @override
  State<_BreathingGlow> createState() => _BreathingGlowState();
}

class _BreathingGlowState extends State<_BreathingGlow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final alpha = 0.06 + (_controller.value * 0.09);
        return Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                widget.color.withValues(alpha: alpha),
                Colors.transparent,
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
