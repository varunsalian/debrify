// Multi-view tile selection model: the channels pinned to tiles, which tile
// carries the sound, and the per-platform limits that shape the grid.
import 'package:debrify/models/iptv_playlist.dart';
import 'package:flutter/foundation.dart';

/// One multi-view layout: the tiles in grid order and which one has sound.
@immutable
final class MultiViewSelection {
  const MultiViewSelection({
    this.channels = const [],
    this.audioIndex = 0,
    this.owner,
  });

  /// The pinned channels, in tile order. Always unmodifiable.
  final List<IptvChannel> channels;

  /// Index into [channels] of the tile with sound; 0 when empty.
  final int audioIndex;

  /// The profile this selection belongs to (compared with ==).
  final Object? owner;

  bool get isEmpty => channels.isEmpty;
}

/// Outcome of trying to pin another channel to a tile.
enum MultiViewAddResult { added, duplicate, full }

/// Platform families with different multi-view capabilities.
enum MultiViewPlatform { androidTv, android, ios, tvos, desktop }

/// Tiles each platform can play at once. tvOS can only hold one video
/// output, so multi-view is not available there at all.
int multiViewMaxTiles(MultiViewPlatform platform) {
  return switch (platform) {
    MultiViewPlatform.androidTv => 4,
    MultiViewPlatform.android => 4,
    MultiViewPlatform.desktop => 4,
    MultiViewPlatform.ios => 2,
    MultiViewPlatform.tvos => 0,
  };
}

/// Grid shape for [count] tiles: 0 → (0, 0), 1 → (1, 1), 2 → (1, 2),
/// 3 or 4 → (2, 2).
({int rows, int cols}) multiViewGrid(int count) {
  return switch (count) {
    <= 0 => (rows: 0, cols: 0),
    1 => (rows: 1, cols: 1),
    2 => (rows: 1, cols: 2),
    _ => (rows: 2, cols: 2),
  };
}
