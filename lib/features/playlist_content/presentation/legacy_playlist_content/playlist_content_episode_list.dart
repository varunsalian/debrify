import 'dart:async';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_scroll_state.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:flutter/material.dart';

typedef PlaylistContentEpisodeListDeps = ({
  PlaylistContentScrollState scrollState,
  int? Function(SeriesSeason season) determineInitialEpisodeIndex,
  bool Function() mounted,
  Widget Function(SeriesEpisode episode) buildEpisodeCard,
  BuildContext Function() context,
});

class PlaylistContentEpisodeList {
  PlaylistContentEpisodeList(this._deps);
  final PlaylistContentEpisodeListDeps _deps;

  /// Build episode list
  Widget buildEpisodeList(SeriesSeason season) {
    // Determine which episode to scroll to (if any)
    // Use _isScrollScheduled flag to prevent duplicate scroll scheduling during rebuilds
    if (_deps.scrollState.targetEpisodeIndex == null &&
        !_deps.scrollState.isScrollScheduled) {
      _deps.scrollState.targetEpisodeIndex = _deps.determineInitialEpisodeIndex(
        season,
      );

      // Schedule auto-scroll after the list is built
      // IMPORTANT: Always schedule the callback - hasClients will be checked inside
      if (_deps.scrollState.targetEpisodeIndex != null) {
        _deps.scrollState.isScrollScheduled =
            true; // Mark as scheduled to prevent duplicates
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_deps.mounted()) {
            scrollToEpisode(_deps.scrollState.targetEpisodeIndex!);
          }
          _deps.scrollState.isScrollScheduled =
              false; // Reset after scroll attempt
        });
      }
    }

    return ListView.builder(
      controller: _deps.scrollState.episodeListScrollController,
      padding: const EdgeInsets.all(16),
      itemCount: season.episodes.length,
      itemBuilder: (context, index) {
        final episode = season.episodes[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _deps.buildEpisodeCard(episode),
        );
      },
    );
  }

  /// Scroll to a specific episode index with animation
  void scrollToEpisode(int episodeIndex, {int retryCount = 0}) {
    // Cancel any existing retry timer to prevent memory leaks
    _deps.scrollState.scrollRetryTimer?.cancel();

    if (!_deps.scrollState.episodeListScrollController.hasClients) {
      // Retry up to 3 times with increasing delay
      if (retryCount < 3) {
        print(
          '⏳ ScrollController not ready yet, scheduling retry ${retryCount + 1}/3',
        );
        _deps.scrollState.scrollRetryTimer = Timer(
          Duration(milliseconds: 100 * (retryCount + 1)),
          () {
            if (_deps.mounted()) {
              scrollToEpisode(episodeIndex, retryCount: retryCount + 1);
            }
          },
        );
      } else {
        print(
          '❌ Failed to scroll after 3 retries - ScrollController never attached',
        );
      }
      return;
    }

    // Calculate approximate position
    // Each episode card is roughly 108px (desktop) or 100px (mobile) + 16px padding
    final screenWidth = MediaQuery.of(_deps.context()).size.width;
    final isMobile = screenWidth < 600;
    final estimatedItemHeight = isMobile
        ? 116.0
        : 124.0; // card height + padding
    final targetOffset = episodeIndex * estimatedItemHeight;

    // Ensure we don't scroll beyond the max extent
    final maxScrollExtent =
        _deps.scrollState.episodeListScrollController.position.maxScrollExtent;
    final finalOffset = targetOffset > maxScrollExtent
        ? maxScrollExtent
        : targetOffset;

    print(
      '📜 Auto-scrolling to episode index: $episodeIndex (offset: $finalOffset, max: $maxScrollExtent)',
    );

    // Scroll to the target episode with animation
    _deps.scrollState.episodeListScrollController.animateTo(
      finalOffset,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
    );
  }
}
