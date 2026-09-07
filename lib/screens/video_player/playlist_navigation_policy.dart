import 'dart:math' as math;

import '../../models/playlist_entry.dart';
import '../../models/playlist_view_mode.dart';
import '../../models/series_playlist.dart';

/// Selects navigation indices and owns the continuous-shuffle bag.
/// Inputs and Random are borrowed per call; loading and notifications stay host-owned.
class PlaylistNavigationPolicy {
  bool _continuousShuffleEnabled = false;
  final List<int> _shuffleBag = [];

  bool get continuousEnabled => _continuousShuffleEnabled;

  void setContinuousAndClear(bool enabled) {
    _continuousShuffleEnabled = enabled;
    _shuffleBag.clear();
  }

  void clearBag() {
    _shuffleBag.clear();
  }

  /// Find the next logical episode index for auto-advance
  int nextIndex(List<PlaylistEntry>? entries, SeriesPlaylist? seriesPlaylist,
      int currentIndex, bool sequentialOrder) {

    if (seriesPlaylist == null || !seriesPlaylist.isSeries) {
      // Raw mode OR Sorted mode: sequential navigation through all files
      // In sorted mode, files are already pre-sorted A-Z, so sequential = alphabetical
      if (sequentialOrder) {
        if (entries == null || entries.isEmpty) return -1;
        if (currentIndex + 1 < entries.length) {
          return currentIndex + 1;
        }
        return -1;
      }

      // Collection mode (view mode not specified): navigate within Main group only
      if (entries == null || entries.isEmpty) return -1;
      final indices = mainGroupIndices(entries);
      if (indices.isEmpty) return -1;

      final currentPos = indices.indexOf(currentIndex);
      if (currentPos == -1) {
        return indices.first;
      }

      if (currentPos + 1 < indices.length) {
        return indices[currentPos + 1];
      }

      return -1;
    }

    // Series mode: existing logic
    try {
      // Find current episode in the sorted allEpisodes list
      final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
        (episode) => episode.originalIndex == currentIndex,
        orElse: () {
          if (seriesPlaylist.allEpisodes.isEmpty) {
            throw StateError('allEpisodes is empty');
          }
          return seriesPlaylist.allEpisodes.first;
        },
      );

      // Find the index of current episode in allEpisodes
      final currentEpisodeIndex = seriesPlaylist.allEpisodes.indexOf(
        currentEpisode,
      );

      if (currentEpisodeIndex == -1 ||
          currentEpisodeIndex + 1 >= seriesPlaylist.allEpisodes.length) {
        return -1;
      }

      // Get the next episode from the sorted list
      final nextEpisode = seriesPlaylist.allEpisodes[currentEpisodeIndex + 1];
      return nextEpisode.originalIndex;
    } catch (e) {
      return -1;
    }
  }

  /// Compute the Main group indices for movie collections (size >= 70% of largest)
  List<int> mainGroupIndices(List<PlaylistEntry> entries) {
    int maxSize = -1;
    for (final e in entries) {
      final s = e.sizeBytes ?? -1;
      if (s > maxSize) maxSize = s;
    }
    final double threshold = maxSize > 0 ? maxSize * 0.40 : -1;
    final main = <int>[];
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final isSmall =
          threshold > 0 && (e.sizeBytes != null && e.sizeBytes! < threshold);
      if (!isSmall) main.add(i);
    }
    int sizeOf(int idx) => entries[idx].sizeBytes ?? -1;
    int? yearOf(int idx) {
      final m = RegExp(r'\b(19|20)\d{2}\b').firstMatch(entries[idx].title);
      if (m != null) return int.tryParse(m.group(0)!);
      return null;
    }

    main.sort((a, b) {
      final ya = yearOf(a);
      final yb = yearOf(b);
      if (ya != null && yb != null) return ya.compareTo(yb); // older first
      return sizeOf(b).compareTo(sizeOf(a));
    });
    return main;
  }

  List<int> _shuffleEligibleIndices(List<PlaylistEntry>? entries,
      SeriesPlaylist? seriesPlaylist, PlaylistViewMode? viewMode) {
    if (entries == null || entries.isEmpty) return const [];

    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      final indices = seriesPlaylist.allEpisodes
          .map((episode) => episode.originalIndex)
          .where((index) => index >= 0 && index < entries.length)
          .toSet()
          .toList();
      if (indices.isNotEmpty) return indices;
    }

    if (viewMode == PlaylistViewMode.raw ||
        viewMode == PlaylistViewMode.sorted) {
      return List<int>.generate(entries.length, (index) => index);
    }

    final mainIndices = mainGroupIndices(
      entries,
    ).where((index) => index >= 0 && index < entries.length).toList();
    if (mainIndices.isNotEmpty) return mainIndices;

    return List<int>.generate(entries.length, (index) => index);
  }

  int? pickShuffleIndex(List<PlaylistEntry>? entries,
      SeriesPlaylist? seriesPlaylist, int currentIndex,
      PlaylistViewMode? viewMode, math.Random random) {
    final eligible = _shuffleEligibleIndices(entries, seriesPlaylist, viewMode);
    if (eligible.isEmpty) return null;
    if (eligible.length == 1) return eligible.first;

    final eligibleSet = eligible.toSet();
    _shuffleBag.removeWhere(
      (index) => !eligibleSet.contains(index) || index == currentIndex,
    );

    if (_shuffleBag.isEmpty) {
      _shuffleBag.addAll(
        eligible.where((index) => index != currentIndex).toList()
          ..shuffle(random),
      );
    }

    if (_shuffleBag.isEmpty) return null;
    return _shuffleBag.removeLast();
  }

  /// Find the previous logical episode index
  int previousIndex(List<PlaylistEntry>? entries, SeriesPlaylist? seriesPlaylist,
      int currentIndex, bool sequentialOrder) {

    if (seriesPlaylist == null || !seriesPlaylist.isSeries) {
      // Raw mode OR Sorted mode: sequential navigation through all files
      // In sorted mode, files are already pre-sorted A-Z, so sequential = alphabetical
      if (sequentialOrder) {
        if (entries == null || entries.isEmpty) return -1;
        if (currentIndex - 1 >= 0) {
          return currentIndex - 1;
        }
        return -1;
      }

      // Collection mode (view mode not specified): navigate within Main group only
      if (entries == null || entries.isEmpty) return -1;
      final indices = mainGroupIndices(entries);
      if (indices.isEmpty) return -1;

      final currentPos = indices.indexOf(currentIndex);
      if (currentPos == -1) {
        return indices.first;
      }

      if (currentPos - 1 >= 0) {
        return indices[currentPos - 1];
      }

      return -1;
    }

    // Series mode: existing logic
    try {
      // Find current episode in the sorted allEpisodes list
      final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
        (episode) => episode.originalIndex == currentIndex,
        orElse: () {
          if (seriesPlaylist.allEpisodes.isEmpty) {
            throw StateError('allEpisodes is empty');
          }
          return seriesPlaylist.allEpisodes.first;
        },
      );

      // Find the index of current episode in allEpisodes
      final currentEpisodeIndex = seriesPlaylist.allEpisodes.indexOf(
        currentEpisode,
      );

      if (currentEpisodeIndex <= 0) {
        return -1;
      }

      // Get the previous episode from the sorted list
      final previousEpisode =
          seriesPlaylist.allEpisodes[currentEpisodeIndex - 1];
      return previousEpisode.originalIndex;
    } catch (e) {
      return -1;
    }
  }
}
