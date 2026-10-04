import 'dart:async';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_episode_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_series_state.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PlaylistContentEpisodeCardDeps = ({
  BuildContext Function() context,
  PlaylistContentSeriesState seriesState,
  PlaylistContentEpisodeState episodeState,
  Future<void> Function(SeriesEpisode episode) toggleWatchedState,
  Future<void> Function(SeriesEpisode episode) playEpisode,
  Widget Function(
    SeriesEpisode episode,
    double progress,
    bool isFinished,
    bool hasMetadata,
    EpisodeInfo? episodeInfo,
  )
  buildMobileEpisodeCard,
  Widget Function(
    SeriesEpisode episode,
    double progress,
    bool isFinished,
    bool hasMetadata,
    EpisodeInfo? episodeInfo,
  )
  buildDesktopEpisodeCard,
});

class PlaylistContentEpisodeCard {
  PlaylistContentEpisodeCard(this._deps);
  final PlaylistContentEpisodeCardDeps _deps;

  /// Build episode card with responsive layout (vertical on mobile, horizontal on desktop)
  Widget buildEpisodeCard(SeriesEpisode episode) {
    final app = AppThemeScope.of(_deps.context());
    // Get progress for this episode
    double progress = 0.0;
    bool isFinished = false;
    if (episode.seriesInfo.season != null &&
        episode.seriesInfo.episode != null) {
      final key = '${episode.seriesInfo.season}_${episode.seriesInfo.episode}';
      print(
        '🔍 Looking for progress with key: $key for ${episode.displayTitle}',
      );
      print(
        '💾 Available keys in cache: ${_deps.seriesState.fileProgressCache.keys.toList()}',
      );
      final progressData = _deps.seriesState.fileProgressCache[key];
      if (progressData != null) {
        print('✅ Found progress data: $progressData');
        final positionMs = progressData['positionMs'] as int? ?? 0;
        final durationMs = progressData['durationMs'] as int? ?? 0;
        if (durationMs > 0) {
          progress = positionMs / durationMs;
          // Check if finished based on progress OR if it's marked as finished explicitly
          // Dummy data has durationMs = 1 to indicate manually marked as watched
          isFinished =
              progress >= 0.9 ||
              (durationMs - positionMs) < 120000 ||
              (positionMs == 0 && durationMs == 1);
          print(
            '📈 Progress: ${(progress * 100).round()}%, Finished: $isFinished',
          );
        }
      } else {
        print('❌ No progress data found for key: $key');
      }
    }

    final episodeInfo = episode.episodeInfo;
    final hasMetadata = episodeInfo != null;

    // Detect screen width for responsive layout
    final screenWidth = MediaQuery.of(_deps.context()).size.width;
    final isMobile = screenWidth < 600;

    return Focus(
      onFocusChange: (focused) {
        if (!focused) {
          // Clean up long press state when losing focus
          _deps.episodeState.episodeLongPressTimer?.cancel();
          _deps.episodeState.episodeLongPressTriggered = false;
          _deps.episodeState.episodeKeyDownReceived = false;
        }
      },
      onKeyEvent: (node, event) {
        // Handle Select/Enter button press for D-pad long press detection
        if (isActivateKey(event.logicalKey)) {
          if (event is KeyDownEvent) {
            _deps.episodeState.episodeKeyDownReceived = true;
            _deps.episodeState.episodeLongPressTriggered = false;

            // Start timer for long press (800ms) - marks as watched
            _deps.episodeState.episodeLongPressTimer?.cancel();
            _deps.episodeState.episodeLongPressTimer = Timer(
              const Duration(milliseconds: 800),
              () {
                _deps.episodeState.episodeLongPressTriggered = true;
                _deps.episodeState.lastEpisodeLongPressTime = DateTime.now();
                _deps.toggleWatchedState(episode);
              },
            );

            return KeyEventResult.handled;
          } else if (event is KeyRepeatEvent) {
            // Ignore key repeat events - don't restart the timer
            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            _deps.episodeState.episodeLongPressTimer?.cancel();

            // Only process KeyUp if we received KeyDown while focused
            if (!_deps.episodeState.episodeKeyDownReceived) {
              return KeyEventResult.handled;
            }

            // Check if we recently triggered a long press
            final timeSinceLongPress =
                _deps.episodeState.lastEpisodeLongPressTime != null
                ? DateTime.now()
                      .difference(_deps.episodeState.lastEpisodeLongPressTime!)
                      .inMilliseconds
                : 999999;

            // Short press - play episode
            if (!_deps.episodeState.episodeLongPressTriggered &&
                timeSinceLongPress > 300) {
              _deps.playEpisode(episode);
            }
            _deps.episodeState.episodeLongPressTriggered = false;
            _deps.episodeState.episodeKeyDownReceived = false;

            return KeyEventResult.handled;
          }
        }

        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return Stack(
            children: [
              Card(
                // The focused state is the idle veil LIFTED, so it is spelled
                // off rowFill rather than as an unrelated white.
                color: isFocused
                    ? app.playlist.rowFill.withValues(alpha: 0.08)
                    : app.playlist.rowFill,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: app.shape.br(12),
                  side: BorderSide(
                    color: isFocused
                        ? app.playlist.focusRing
                        : app.fade(app.core.tx, 0.06),
                    width: isFocused ? 1.5 : 1,
                  ),
                ),
                child: InkWell(
                  onTap: _deps.episodeState.isAndroidTv
                      ? null
                      : () => _deps.playEpisode(episode),
                  onLongPress: _deps.episodeState.isAndroidTv
                      ? null
                      : () => _deps.toggleWatchedState(episode),
                  child: isMobile
                      ? _deps.buildMobileEpisodeCard(
                          episode,
                          progress,
                          isFinished,
                          hasMetadata,
                          episodeInfo,
                        )
                      : _deps.buildDesktopEpisodeCard(
                          episode,
                          progress,
                          isFinished,
                          hasMetadata,
                          episodeInfo,
                        ),
                ),
              ),
              // Long press hint for Android TV (bottom-right when focused)
              if (_deps.episodeState.isAndroidTv && isFocused)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      // Black glass stays black on every theme.
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: app.shape.br(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isFinished ? Icons.remove_done : Icons.done_all,
                          size: 14,
                          color: app.onGlass.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isFinished
                              ? 'Hold to unmark'
                              : 'Hold to mark watched',
                          style: TextStyle(
                            color: app.onGlass.withValues(alpha: 0.9),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
