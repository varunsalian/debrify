/// User-specific server progress. This contains no URLs or credentials.
class MediaServerWatchState {
  const MediaServerWatchState({
    required this.positionMs,
    required this.durationMs,
    required this.played,
    this.lastPlayedAtMs,
  });

  final int positionMs;
  final int durationMs;
  final bool played;
  final int? lastPlayedAtMs;

  /// Played is watch history, not proof that the current viewing is finished.
  /// Servers retain it while a rewatch has its own active resume bookmark.
  bool get hasPartialBookmark =>
      positionMs > 0 && (durationMs <= 0 || positionMs < durationMs);

  factory MediaServerWatchState.fromItem(Map<String, dynamic> item) {
    final data = item['UserData'];
    if (data is! Map || data['Played'] is! bool) {
      throw const FormatException('Missing server user progress');
    }
    int milliseconds(Object? ticks) {
      if (ticks == null) return 0;
      if (ticks is! num || !ticks.isFinite || ticks < 0) {
        throw const FormatException('Invalid server progress');
      }
      return (ticks / 10000).floor();
    }

    final duration = milliseconds(item['RunTimeTicks']);
    final position = milliseconds(data['PlaybackPositionTicks']);
    return MediaServerWatchState(
      positionMs: duration > 0 ? position.clamp(0, duration) : position,
      durationMs: duration,
      played: data['Played'] as bool,
      lastPlayedAtMs: data['LastPlayedDate'] is String
          ? DateTime.tryParse(
              data['LastPlayedDate'] as String,
            )?.millisecondsSinceEpoch
          : null,
    );
  }

  /// Unknown chronology is not permission to overwrite a local bookmark.
  bool shouldImport({
    required int? localUpdatedAtMs,
    required bool localPlayed,
  }) {
    if (localPlayed) return false;
    if (localUpdatedAtMs == null) return played || positionMs > 0;
    return lastPlayedAtMs != null && lastPlayedAtMs! > localUpdatedAtMs;
  }
}
