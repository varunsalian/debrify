import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/debrify_tv/channel.dart';
import '../services/storage_service.dart';
import '../services/debrify_tv_repository.dart';
import '../services/main_page_bridge.dart';

/// Horizontal scrollable Debrify TV channel favorites section for the home screen
class HomeDebrifyTvFavoritesSection extends StatefulWidget {
  const HomeDebrifyTvFavoritesSection({super.key});

  @override
  State<HomeDebrifyTvFavoritesSection> createState() =>
      _HomeDebrifyTvFavoritesSectionState();
}

class _HomeDebrifyTvFavoritesSectionState
    extends State<HomeDebrifyTvFavoritesSection> {
  List<DebrifyTvChannel> _favoriteChannels = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
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
      }
    } catch (e) {
      debugPrint('Error loading Debrify TV favorites: $e');
      if (mounted) {
        setState(() {
          _favoriteChannels = [];
          _isLoading = false;
        });
      }
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
        // Horizontal scrolling favorites
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _favoriteChannels.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final channel = _favoriteChannels[index];
              return _buildChannelCard(channel);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChannelCard(DebrifyTvChannel channel) {
    return _ChannelCardWithFocus(
      onTap: () => _openChannel(channel),
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
  final Widget Function(bool isFocused, bool isHovered) child;

  const _ChannelCardWithFocus({
    required this.onTap,
    required this.child,
  });

  @override
  State<_ChannelCardWithFocus> createState() => _ChannelCardWithFocusState();
}

class _ChannelCardWithFocusState extends State<_ChannelCardWithFocus> {
  bool _isFocused = false;
  bool _isHovered = false;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.gameButtonA) {
        widget.onTap?.call();
        return KeyEventResult.handled;
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
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        onKeyEvent: _handleKeyEvent,
        child: GestureDetector(
          onTap: widget.onTap,
          child: widget.child(_isFocused, _isHovered),
        ),
      ),
    );
  }
}
