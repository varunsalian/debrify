import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/screens/debrify_tv/widgets/tv_focusable_card.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

class DebrifyTvGridCards {
  final DebrifyTvDependencies _deps;
  DebrifyTvGridCards(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  // Favorite Channels Section (horizontal row)
  Widget buildFavoriteChannelsSection() {
    final app = AppThemeScope.of(_deps.context());
    final tv = app.debrifyTv;
    // Get favorite channels from the channels list
    final favoriteChannels = _owners.library.channels
        .where(
          (channel) => _owners.library.favoriteChannelIds.contains(channel.id),
        )
        .toList();

    // Don't show if no favorites
    if (favoriteChannels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.star_rounded,
                size: 18,
                color: tv.favorite.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 8),
              Text(
                'Favorites',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: app.core.tx.withValues(alpha: 0.7),
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
            itemCount: favoriteChannels.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final channel = favoriteChannels[index];
              return _sections.cards._buildFavoriteChannelCard(channel);
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // Favorite Channel Card (compact horizontal card)
  Widget _buildFavoriteChannelCard(DebrifyTvChannel channel) {
    final app = AppThemeScope.of(_deps.context());
    final tv = app.debrifyTv;
    return SizedBox(
      width: 160,
      height: 100,
      child: TvFocusableCard(
        onPressed: () => _sections.channelWatch.watchChannel(channel),
        onLongPress: () => _sections.dialogs.showTvChannelOptionsMenu(channel),
        child: Stack(
          children: [
            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Channel number badge (smaller)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tv.accent,
                      borderRadius: app.shape.br(6),
                    ),
                    child: Text(
                      'CH ${channel.channelNumber > 0 ? channel.channelNumber : _owners.library.channels.indexOf(channel) + 1}',
                      style: TextStyle(
                        color: app.inkOn(tv.accent),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Channel name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      channel.name.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: app.core.tx,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Star indicator
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                Icons.star_rounded,
                size: 14,
                color: tv.favorite,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // TV Channel Card (Grid item)
  Widget buildTvChannelCard(DebrifyTvChannel channel) {
    final app = AppThemeScope.of(_deps.context());
    final tv = app.debrifyTv;
    final isFavorited = _owners.library.favoriteChannelIds.contains(channel.id);

    return TvFocusableCard(
      onPressed: () {
        _sections.channelWatch.watchChannel(channel);
      },
      onLongPress: () {
        _sections.dialogs.showTvChannelOptionsMenu(channel);
      },
      showLongPressHint:
          _owners.settings.isAndroidTv, // Only show hint on Android TV
      child: Stack(
        children: [
          // Favorite star indicator (top-left)
          if (isFavorited)
            Positioned(
              top: 6,
              left: 6,
              child: Icon(
                Icons.star_rounded,
                size: 20,
                color: tv.favorite,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          // Main card content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Channel number badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tv.accent,
                    borderRadius: app.shape.br(8),
                  ),
                  child: Text(
                    'CH ${channel.channelNumber > 0 ? channel.channelNumber : _owners.library.channels.indexOf(channel) + 1}',
                    style: TextStyle(
                      color: app.inkOn(tv.accent),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Channel name - centered
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    channel.name.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: app.core.tx,
                      height: 1.2,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 3-dot menu for non-Android TV devices
          if (!_owners.settings.isAndroidTv)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: app.shape.br(6),
                ),
                child: PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    // Sits on the black plate above, so it takes glass ink.
                    color: app.onGlass.withValues(alpha: 0.9),
                    size: 16,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: 'Options',
                  color: tv.noticeBg,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: app.shape.br(18),
                    side: BorderSide(color: tv.hairline),
                  ),
                  onSelected: (value) {
                    if (value == 'favorite') {
                      _sections.library.toggleChannelFavorite(channel);
                    } else if (value == 'edit') {
                      _sections.actions.handleEditChannel(channel);
                    } else if (value == 'share') {
                      _sections.share.handleShareChannelAsMagnet(channel);
                    } else if (value == 'delete') {
                      _sections.actions.handleDeleteChannel(channel);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'favorite',
                      child: Row(
                        children: [
                          Icon(
                            isFavorited
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 18,
                            color: tv.favorite,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isFavorited
                                ? 'Remove Favorite'
                                : 'Add to Favorites',
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 18),
                          SizedBox(width: 12),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share_rounded, size: 18),
                          SizedBox(width: 12),
                          Text('Share Channel'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18),
                          SizedBox(width: 12),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // TV "Add Channel" Card
  Widget buildTvAddChannelCard() {
    final tv = AppThemeScope.of(_deps.context()).debrifyTv;
    return TvFocusableCard(
      onPressed: _sections.actions.handleAddChannel,
      child: SizedBox(
        height: double.infinity, // Ensures consistent height
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: tv.fillWeak,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add_rounded, size: 32, color: tv.textDim),
            ),
            const SizedBox(height: 12),
            Text(
              'Add Channel',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: tv.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
