import 'dart:async';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

typedef PlaylistContentDesktopEpisodeDeps = ({
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

class PlaylistContentDesktopEpisode {
  PlaylistContentDesktopEpisode(this._deps);
  final PlaylistContentDesktopEpisodeDeps _deps;

  /// Build desktop horizontal layout (thumbnail left, info right) — Trakt-style
  Widget buildDesktopEpisodeCard(
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Compact thumbnail
          ClipRRect(
            borderRadius: app.shape.brImg(8),
            child: SizedBox(
              width: 155,
              height: 88,
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

                  // Dim overlay for watched episodes
                  if (isFinished)
                    // Black scrim over artwork — stays black on every theme.
                    Container(color: Colors.black.withValues(alpha: 0.6)),

                  // Thin progress bar at bottom of thumbnail
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

          const SizedBox(width: 14),

          // Middle: Episode info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Episode title with E## prefix
                Text(
                  '$titlePrefix${episode.displayTitle}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 4),

                // Metadata row — S01E01 badge, air date, runtime, rating, watch status
                _deps.buildEpisodeMetadataRow(
                  episode,
                  episodeInfo,
                  progress,
                  isFinished,
                ),

                // Description
                if (hasMetadata && episodeInfo!.plot != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    episodeInfo.plot!,
                    style: TextStyle(
                      color: app.core.tx.withValues(alpha: 0.45),
                      fontSize: 11,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Right: Mark as watched button
          GestureDetector(
            onTap: () => _deps.toggleWatchedState(episode),
            child: Container(
              width: 36,
              height: 36,
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
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
