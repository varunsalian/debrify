import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/debrify_tv/channel.dart';
import '../services/storage_service.dart';
import '../services/debrify_tv_repository.dart';
import '../services/main_page_bridge.dart';
import 'home_focus_controller.dart';

/// Premium Debrify TV channel favorites section for the home screen
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

  final List<FocusNode> _cardFocusNodes = [];
  final ScrollController _scrollController = ScrollController();

  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  static const _accentColor = Color(0xFF8B5CF6); // Purple accent

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
    widget.focusController?.unregisterSection(HomeSection.tvFavorites);
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
          FocusNode(debugLabel: 'tv_channel_card_${_cardFocusNodes.length}'));
    }
    while (_cardFocusNodes.length > _favoriteChannels.length) {
      _cardFocusNodes.removeLast().dispose();
    }
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);

    try {
      final favoriteIds =
          await StorageService.getDebrifyTvFavoriteChannelIds();

      if (favoriteIds.isEmpty) {
        if (mounted) {
          setState(() {
            _favoriteChannels = [];
            _isLoading = false;
          });
          _ensureFocusNodes();
          widget.focusController?.registerSection(
            HomeSection.tvFavorites,
            hasItems: false,
            focusNodes: [],
          );
        }
        return;
      }

      final records =
          await DebrifyTvRepository.instance.fetchAllChannels();
      final allChannels =
          records.map(DebrifyTvChannel.fromRecord).toList(growable: false);

      final favorites = allChannels
          .where((channel) => favoriteIds.contains(channel.id))
          .toList();

      if (mounted) {
        setState(() {
          _favoriteChannels = favorites;
          _isLoading = false;
        });
        _ensureFocusNodes();
        widget.focusController?.registerSection(
          HomeSection.tvFavorites,
          hasItems: _favoriteChannels.isNotEmpty,
          focusNodes: _cardFocusNodes,
        );
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _updateScrollIndicators());
      }
    } catch (e) {
      debugPrint('Error loading Debrify TV favorites: $e');
      if (mounted) {
        setState(() {
          _favoriteChannels = [];
          _isLoading = false;
        });
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
    if (MainPageBridge.watchDebrifyTvChannel != null) {
      MainPageBridge.watchDebrifyTvChannel!(channel.id);
      return;
    }
    MainPageBridge.notifyDebrifyTvChannelToAutoPlay(channel.id);
    MainPageBridge.switchTab?.call(3);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _favoriteChannels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(),
        const SizedBox(height: 8),
        SizedBox(
          height: 140,
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
                  itemCount: _favoriteChannels.length,
                  itemBuilder: (context, index) {
                    final channel = _favoriteChannels[index];
                    return Padding(
                      padding: EdgeInsets.only(
                          right: index < _favoriteChannels.length - 1
                              ? 14
                              : 0),
                      child: _buildChannelCard(
                        channel,
                        index: index,
                        focusNode: index < _cardFocusNodes.length
                            ? _cardFocusNodes[index]
                            : null,
                        onLongPress: () =>
                            _confirmRemoveFavorite(channel),
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
                    itemCount: _favoriteChannels.length,
                    itemBuilder: (context, index) {
                      final channel = _favoriteChannels[index];
                      return Padding(
                        padding: EdgeInsets.only(
                            right: index < _favoriteChannels.length - 1
                                ? 14
                                : 0),
                        child: _buildChannelCard(
                          channel,
                          index: index,
                          focusNode: index < _cardFocusNodes.length
                              ? _cardFocusNodes[index]
                              : null,
                          onLongPress: () =>
                              _confirmRemoveFavorite(channel),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
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
            decoration: BoxDecoration(
              color: _accentColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Debrify TV',
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

  // ── Channel card ──────────────────────────────────────────────────────────

  Widget _buildChannelCard(
    DebrifyTvChannel channel, {
    int index = 0,
    FocusNode? focusNode,
    VoidCallback? onLongPress,
  }) {
    final channelNum = channel.channelNumber > 0
        ? channel.channelNumber
        : _favoriteChannels.indexOf(channel) + 1;

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
          widget.focusController
              ?.saveLastFocusedIndex(HomeSection.tvFavorites, idx);
        }
      },
      allFocusNodes: _cardFocusNodes,
      isTelevision: widget.isTelevision,
      child: (isFocused, isHovered) {
        final isActive = isFocused || isHovered;

        final cardDecoration = BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isActive
                    ? _accentColor.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.06),
                width: isActive ? 2.0 : 1.0,
              ),
              boxShadow: widget.isTelevision ? null : (isActive
                  ? [
                      BoxShadow(
                        color: _accentColor.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]),
            );

        final playOverlayChild = Container(
                          color: Colors.black.withValues(alpha: 0.3),
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white
                                    .withValues(alpha: 0.15),
                                border: Border.all(
                                  color: Colors.white
                                      .withValues(alpha: 0.35),
                                  width: 1.5,
                                ),
                              ),
                              child: ClipOval(
                                child: widget.isTelevision
                                  ? Container(
                                      color: Colors.black.withValues(alpha: 0.6),
                                      child: const Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    )
                                  : BackdropFilter(
                                      filter: ImageFilter.blur(
                                          sigmaX: 8, sigmaY: 8),
                                      child: const Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                              ),
                            ),
                          ),
                        );

        final cardContent = ClipRRect(
              borderRadius: BorderRadius.circular(isActive ? 12.5 : 13),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // ── Background gradient ──
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF1A1030),
                          _accentColor.withValues(alpha: 0.12),
                          const Color(0xFF0D0D1A),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),

                  // ── Decorative glow (skip on TV for GPU perf) ──
                  if (!widget.isTelevision)
                  Positioned(
                    top: -20,
                    right: -20,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _accentColor.withValues(alpha: 0.08),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Content ──
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: channel badge + star
                        Row(
                          children: [
                            // Channel number
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: widget.isTelevision
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          _accentColor,
                                          _accentColor
                                              .withValues(alpha: 0.8),
                                        ],
                                      ),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'CH $channelNum',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  )
                                : BackdropFilter(
                                    filter: ImageFilter.blur(
                                        sigmaX: 8, sigmaY: 8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            _accentColor,
                                            _accentColor
                                                .withValues(alpha: 0.8),
                                          ],
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'CH $channelNum',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ),
                                  ),
                            ),
                            const Spacer(),
                            Icon(Icons.star_rounded,
                                size: 14, color: const Color(0xFFFFD700).withValues(alpha: 0.8)),
                          ],
                        ),
                        const Spacer(),
                        // Channel name
                        Text(
                          channel.name.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                            height: 1.2,
                          ),
                        ),
                        if (channel.keywords.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          // Keywords as subtle pills
                          Row(
                            children: [
                              for (final kw in channel.keywords.take(3)) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: _accentColor
                                        .withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(4),
                                    border: Border.all(
                                      color: _accentColor
                                          .withValues(alpha: 0.2),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    kw,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: _accentColor
                                          .withValues(alpha: 0.9),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Play overlay ──
                  if (isActive)
                    Positioned.fill(
                      child: widget.isTelevision
                        ? playOverlayChild
                        : AnimatedOpacity(
                            opacity: 1.0,
                            duration: const Duration(milliseconds: 200),
                            child: playOverlayChild,
                          ),
                    ),
                ],
              ),
            );

        final containerChild = widget.isTelevision
            ? Container(
                width: 220,
                height: 120,
                decoration: cardDecoration,
                child: cardContent,
              )
            : AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                width: 220,
                height: 120,
                decoration: cardDecoration,
                child: cardContent,
              );

        if (widget.isTelevision) {
          return Transform.scale(
            scale: isActive ? 1.05 : 1.0,
            child: containerChild,
          );
        }

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 1.0, end: isActive ? 1.05 : 1.0),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: containerChild,
        );
      },
    );
  }
}

// ── Focus-aware card wrapper (DPAD/TV) ────────────────────────────────────────

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
  final List<FocusNode>? allFocusNodes;
  final bool isTelevision;

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
    this.allFocusNodes,
    this.isTelevision = false,
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
      // Arrow Left - explicit focus on TV, default traversal otherwise
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
      // Arrow Right - explicit focus on TV, default traversal otherwise
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
