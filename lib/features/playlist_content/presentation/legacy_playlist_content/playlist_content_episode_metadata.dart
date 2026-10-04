import 'package:debrify/features/playlist_content/application/playlist_content_formatting.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

typedef PlaylistContentEpisodeMetadataDeps = ({
  BuildContext Function() context,
});

class PlaylistContentEpisodeMetadata {
  PlaylistContentEpisodeMetadata(this._deps);
  final PlaylistContentEpisodeMetadataDeps _deps;

  /// Build compact metadata row (Trakt-style) for episode cards
  Widget buildEpisodeMetadataRow(
    SeriesEpisode episode,
    EpisodeInfo? episodeInfo,
    double progress,
    bool isFinished,
  ) {
    final app = AppThemeScope.of(_deps.context());
    final seString = episode.seasonEpisodeString;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Green S01E01 badge. #34D399 left literal: no token carries it.
        if (seString.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF34D399).withValues(alpha: 0.15),
              borderRadius: app.shape.br(4),
            ),
            child: Text(
              seString,
              style: const TextStyle(
                color: Color(0xFF34D399),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (episodeInfo?.airDate != null)
          Text(
            formatAirDate(episodeInfo!.airDate!),
            style: TextStyle(color: app.playlist.ink3, fontSize: 11),
          ),
        if (episodeInfo?.runtime != null)
          Text(
            '${episodeInfo!.runtime} min',
            style: TextStyle(color: app.playlist.ink3, fontSize: 11),
          ),
        if (episodeInfo?.rating != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Left literal on purpose: value-equal to the DPAD cursor but a
              // RATING, whose real destination (core.rating, #F5C518) is a
              // different colour and therefore a separate sweep decision.
              const Icon(
                Icons.star_rounded,
                size: 13,
                color: Color(0xFFFBBF24),
              ),
              const SizedBox(width: 2),
              Text(
                episodeInfo!.rating!.toStringAsFixed(1),
                style: TextStyle(
                  color: app.core.tx.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        if (progress > 0.0)
          Text(
            isFinished ? 'Watched' : '${(progress * 100).round()}%',
            style: TextStyle(
              color: app.core.tx.withValues(alpha: 0.45),
              fontSize: 11,
            ),
          ),
      ],
    );
  }

  /// Build thumbnail placeholder
  Widget buildThumbnailPlaceholder(SeriesEpisode episode) {
    final app = AppThemeScope.of(_deps.context());
    // `Colors.white38` at its exact alpha, spelled off the page ink.
    final ink38 = app.core.tx.withValues(alpha: 0x62 / 255);
    return Container(
      // Colors.grey.shade900 left literal: no token carries it.
      color: Colors.grey.shade900,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library, color: ink38, size: 48),
            const SizedBox(height: 8),
            Text(
              episode.seasonEpisodeString,
              style: TextStyle(color: ink38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
