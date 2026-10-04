import 'dart:async';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

typedef PlaylistContentMobileEpisodeDeps = ({
  BuildContext Function() context,
  Widget Function(SeriesEpisode episode) buildThumbnailPlaceholder,
  Widget Function(
    SeriesEpisode episode,
    EpisodeInfo? episodeInfo,
    double progress,
    bool isFinished,
  )
  buildEpisodeMetadataRow,
  Future<void> Function(SeriesEpisode episode) toggleWatchedState,
});

class PlaylistContentMobileEpisode {
  PlaylistContentMobileEpisode(this._deps);
  final PlaylistContentMobileEpisodeDeps _deps;

  /// Build mobile layout — compact horizontal row with thumbnail left, info right (Trakt-style)
  Widget buildMobileEpisodeCard(
    SeriesEpisode episode,
    double progress,
    bool isFinished,
    bool hasMetadata,
    EpisodeInfo? episodeInfo,
  ) {
    final app = AppThemeScope.of(_deps.context());
    final epNum = episode.seriesInfo.episode;
    final titlePrefix = epNum != null
        ? 'E${epNum.toString().padLeft(2, '0')} - '
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Compact thumbnail
          ClipRRect(
            borderRadius: app.shape.brImg(8),
            child: SizedBox(
              width: 120,
              height: 68,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasMetadata && episodeInfo!.poster != null)
                    Image.network(
                      episodeInfo.poster!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _deps.buildThumbnailPlaceholder(episode);
                      },
                    )
                  else
                    _deps.buildThumbnailPlaceholder(episode),

                  if (isFinished)
                    // Black scrim over artwork — stays black on every theme.
                    Container(color: Colors.black.withValues(alpha: 0.6)),

                  // Thin progress bar at bottom
                  if (progress > 0.0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: progress.clamp(0.0, 1.0),
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              // The finished half is statusWatched; the
                              // in-progress indigo is left literal — it is
                              // NOT playlist.progressPlayed (Material blue),
                              // and playlist.accent's role is the surface's
                              // action colour, not a progress bar.
                              gradient: LinearGradient(
                                colors: [
                                  isFinished
                                      ? app.playlist.statusWatched
                                      : const Color(0xFF6366F1),
                                  isFinished
                                      ? app.playlist.statusWatched.withValues(
                                          alpha: 0.7,
                                        )
                                      : const Color(
                                          0xFF6366F1,
                                        ).withValues(alpha: 0.7),
                                ],
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

          const SizedBox(width: 12),

          // Middle: Episode info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$titlePrefix${episode.displayTitle}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                _deps.buildEpisodeMetadataRow(
                  episode,
                  episodeInfo,
                  progress,
                  isFinished,
                ),
                if (hasMetadata && episodeInfo!.plot != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    episodeInfo.plot!,
                    style: TextStyle(
                      color: app.core.tx.withValues(alpha: 0.45),
                      fontSize: 11,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Right: Watched button
          GestureDetector(
            onTap: () => _deps.toggleWatchedState(episode),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // #4CAF50 left literal: playlist.statusWatched is #059669,
                // so no token carries this green.
                color: isFinished
                    ? const Color(0xFF4CAF50)
                    : app.playlist.controlFill,
                border: Border.all(
                  color: isFinished
                      ? const Color(0xFF4CAF50)
                      : app.fade(app.core.tx, 0.4),
                  width: 1.5,
                ),
              ),
              child: Icon(
                isFinished ? Icons.check : Icons.circle_outlined,
                color: app.core.tx,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
