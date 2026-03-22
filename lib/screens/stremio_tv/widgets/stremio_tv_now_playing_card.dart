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

    return Row(
      children: [
        // Poster
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 56,
            height: 80,
            child: ImageFiltered(
              imageFilter: hideDetails
                  ? ImageFilter.blur(sigmaX: 20, sigmaY: 20)
                  : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
              child: item.poster != null
                  ? CachedNetworkImage(
                      imageUrl: item.poster!,
                      memCacheWidth: 200,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: Colors.white.withValues(alpha: 0.05),
                        child: Center(
                          child: Icon(
                            Icons.movie_rounded,
                            size: 20,
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.white.withValues(alpha: 0.05),
                        child: Center(
                          child: Icon(
                            Icons.broken_image_rounded,
                            size: 20,
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.white.withValues(alpha: 0.05),
                      child: Center(
                        child: Icon(
                          Icons.movie_rounded,
                          size: 20,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
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
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontStyle: hideDetails ? FontStyle.italic : null,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              if (hideDetails)
                Text(
                  'Press play to find out!',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                )
              else
                _buildMetaRow(item),
              if (!hideDetails &&
                  item.description != null &&
                  item.description!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  item.description!,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.35),
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              _buildProgressBar(),
            ],
          ),
        ),
      ],
    );
  }

  String _buildTeaserTitle(String type) {
    final genre = channelGenre;
    if (genre != null && genre.isNotEmpty) {
      final article = 'aeiouAEIOU'.contains(genre[0]) ? 'An' : 'A';
      final kind = type == 'series' ? 'series' : 'film';
      return '$article $genre $kind awaits...';
    }
    return type == 'series' ? 'A Series awaits...' : 'A Movie awaits...';
  }

  Widget _buildMetaRow(StremioMeta item) {
    final parts = <String>[];
    if (item.year != null) parts.add(item.year!);
    if (item.imdbRating != null) parts.add('${item.imdbRating}');
    if (item.genres != null && item.genres!.isNotEmpty) {
      parts.add(item.genres!.first);
    }

    return Row(
      children: [
        if (item.imdbRating != null) ...[
          Icon(Icons.star_rounded, size: 12, color: Colors.amber.shade600),
          const SizedBox(width: 2),
        ],
        Flexible(
          child: Text(
            parts.join(' \u00B7 '),
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.45),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    final progress = displayProgress ?? nowPlaying.progress;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF6366F1),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          nowPlaying.progressText,
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
      ],
    );
  }
}
