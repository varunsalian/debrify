class PerItemState {
  final int positionMs;
  final int durationMs;
  final int updatedAt;

  const PerItemState({
    this.positionMs = 0,
    this.durationMs = 0,
    this.updatedAt = 0,
  });
}

/// Navigation maps for series playback
/// Maps originalIndex -> next/prev originalIndex based on SeriesPlaylist.allEpisodes order
class NavigationMaps {
  final Map<int, int> nextMap;
  final Map<int, int> prevMap;

  const NavigationMaps({required this.nextMap, required this.prevMap});
}
