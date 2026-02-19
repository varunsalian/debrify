import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/stremio_addon.dart';
import '../../../models/stremio_tv/stremio_tv_now_playing.dart';

/// Displays the "now playing" poster, title, year, rating, and genres
/// for a Stremio TV channel.
class StremioTvNowPlayingCard extends StatelessWidget {
  final StremioTvNowPlaying nowPlaying;
  final double? displayProgress;
  final bool hideDetails;
  final String? channelGenre;

  const StremioTvNowPlayingCard({
    super.key,
    required this.nowPlaying,
    this.displayProgress,
    this.hideDetails = false,
    this.channelGenre,
  });

  @override
  Widget build(BuildContext context) {
    final item = nowPlaying.item;
    final theme = Theme.of(context);

    return Row(
      children: [
        // Poster
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 60,
            height: 85,
            child: ImageFiltered(
              imageFilter: hideDetails
                  ? ImageFilter.blur(sigmaX: 20, sigmaY: 20)
                  : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
              child: item.poster != null
                  ? CachedNetworkImage(
                      imageUrl: item.poster!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Center(
                          child: Icon(Icons.movie_rounded, size: 24),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Center(
                          child: Icon(Icons.broken_image_rounded, size: 24),
                        ),
                      ),
                    )
                  : Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Center(
                        child: Icon(Icons.movie_rounded, size: 24),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Metadata
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hideDetails ? _buildTeaserTitle(item.type) : item.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontStyle: hideDetails ? FontStyle.italic : null,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              if (hideDetails)
                Text(
                  'Press play to find out!',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                _buildMetaRow(item, theme),
              const SizedBox(height: 6),
              _buildProgressBar(theme),
            ],
          ),
        ),
      ],
    );
  }

  String _buildTeaserTitle(String type) {
    final genre = channelGenre;
    if (genre != null && genre.isNotEmpty) {
      // "An Action movie awaits..." / "A Comedy series awaits..."
      final article = 'aeiouAEIOU'.contains(genre[0]) ? 'An' : 'A';
      final kind = type == 'series' ? 'series' : 'film';
      return '$article $genre $kind awaits...';
    }
    return type == 'series' ? 'A Series awaits...' : 'A Movie awaits...';
  }

  Widget _buildMetaRow(StremioMeta item, ThemeData theme) {
    final parts = <String>[];
    if (item.year != null) parts.add(item.year!);
    if (item.imdbRating != null) parts.add('${item.imdbRating}');
    if (item.genres != null && item.genres!.isNotEmpty) {
      parts.add(item.genres!.first);
    }

    return Row(
      children: [
        if (item.imdbRating != null) ...[
          Icon(Icons.star_rounded, size: 14, color: Colors.amber.shade600),
          const SizedBox(width: 2),
        ],
        Flexible(
          child: Text(
            parts.join(' \u00B7 '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar(ThemeData theme) {
    final progress = displayProgress ?? nowPlaying.progress;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          nowPlaying.progressText,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
