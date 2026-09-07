import '../diagnostic_log.dart';

typedef TraktRowsReader = Future<List<dynamic>?> Function();

/// Read a complete snapshot. A failed playback/filter/history read must not
/// publish a smaller feed and erase a previously visible resume-only card.
Future<List<dynamic>?> loadTraktContinueWatching({
  required TraktRowsReader upNext,
  required TraktRowsReader playback,
  required TraktRowsReader hidden,
  required TraktRowsReader dropped,
  required TraktRowsReader watched,
}) async {
  try {
    final initial = await Future.wait([upNext(), playback()]);
    if (initial.any((rows) => rows == null)) {
      _readFailed('catalog');
      return null;
    }
    final next = initial[0]!.cast<Map<String, dynamic>>();
    final paused = initial[1]!;
    // Up Next already applies visibility rules; extra reads are needed only
    // when independently admitting playback sessions.
    if (paused.isEmpty) return next;
    final filters = await Future.wait([hidden(), dropped(), watched()]);
    if (filters.any((rows) => rows == null)) {
      _readFailed('visibility_history');
      return null;
    }
    final result = mergeTraktContinueWatching(
      paused,
      next,
      hidden: [...filters[0]!, ...filters[1]!],
      watched: filters[2]!,
    );
    DiagnosticLog.instance.recordEvent(
      source: 'trakt',
      event: 'continue_watching_merge',
      fields: {
        'upNextCount': next.length,
        'playbackCount': paused.length,
        'resultCount': result.length,
      },
    );
    return result;
  } catch (_) {
    _readFailed('invalid_or_failed_read');
    return null;
  }
}

void _readFailed(String stage) {
  DiagnosticLog.instance.recordEvent(
    source: 'trakt',
    event: 'continue_watching_read_failed',
    fields: {'stage': DiagnosticLabel(stage)},
  );
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map<String, dynamic> ? value : null;

int _stamp(Object? value) =>
    value is String ? DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0 : 0;

List<String> _ids(Object? show) {
  final ids = _map(_map(show)?['ids']);
  return [
    if (ids?['trakt'] is int) 'trakt:${ids!['trakt']}',
    if (ids?['imdb'] is String && (ids!['imdb'] as String).trim().isNotEmpty)
      'imdb:${(ids['imdb'] as String).trim().toLowerCase()}',
    if (ids?['tmdb'] is int) 'tmdb:${ids!['tmdb']}',
  ];
}

/// A show has one actionable card. A valid checkpoint newer than its latest
/// completed watch wins over Up Next, including newly started shows/rewatches.
/// Old or undated checkpoints cannot move the user back to an earlier episode.
List<dynamic> mergeTraktContinueWatching(
  List<dynamic> playback,
  List<Map<String, dynamic>> upNext, {
  required List<dynamic> hidden,
  required List<dynamic> watched,
}) {
  // Resolve aliases across all inputs, including responses with only IMDb IDs.
  final parents = <String, String>{};
  String root(String id) {
    final parent = parents[id];
    if (parent == null || parent == id) return id;
    return parents[id] = root(parent);
  }

  for (final raw in [...upNext, ...playback, ...hidden, ...watched]) {
    final ids = _ids(_map(raw)?['show']);
    if (ids.isEmpty) continue;
    for (final id in ids.skip(1)) {
      parents[root(id)] = root(ids.first);
    }
  }
  String? key(Map<String, dynamic> row) {
    final ids = _ids(row['show']);
    return ids.isEmpty ? null : root(ids.first);
  }

  final hiddenShows = <String>{};
  final hiddenSeasons = <String, Set<int>>{};
  var recoveredHidden = 0;
  var recoveredWatched = 0;
  for (final raw in hidden) {
    final row = _map(raw);
    final id = row == null ? null : key(row);
    if (row == null || id == null) {
      throw const FormatException('Invalid hidden progress record');
    }
    final season = _map(row['season'])?['number'];
    if (row['type'] == 'season' || row['season'] != null) {
      if (season is! int || season < 0) {
        // We know the show but cannot safely determine the hidden season.
        // Suppress that show, allowing unrelated titles to keep refreshing.
        hiddenShows.add(id);
        recoveredHidden++;
        continue;
      }
      hiddenSeasons.putIfAbsent(id, () => {}).add(season);
    } else {
      hiddenShows.add(id);
    }
  }
  final completedAt = <String, int>{};
  final uncertainHistory = <String>{};
  for (final raw in watched) {
    final row = _map(raw);
    final id = row == null ? null : key(row);
    final stamp = _stamp(row?['last_watched_at']);
    if (id == null) {
      throw const FormatException('Invalid watched progress record');
    }
    if (stamp == 0) {
      // Up Next can still supply this show's authoritative episode, but its
      // independent checkpoints cannot be checked for staleness.
      uncertainHistory.add(id);
      recoveredWatched++;
      continue;
    }
    if (stamp > (completedAt[id] ?? 0)) completedAt[id] = stamp;
  }
  bool visible(String id, Map<String, dynamic> row) =>
      !hiddenShows.contains(id) &&
      !(hiddenSeasons[id]?.contains(_map(row['episode'])?['season']) ?? false);

  final result = <String, Map<String, dynamic>>{};
  final activity = <String, int>{...completedAt};
  for (final row in upNext) {
    final id = key(row);
    if (id == null) continue;
    final stamp = _stamp(row['paused_at']);
    if (stamp > (activity[id] ?? 0)) activity[id] = stamp;
    if (visible(id, row)) result.putIfAbsent(id, () => Map.of(row));
  }
  final playbackIds = <String, Set<int>>{};
  final selectedPlayback = <String>{};
  for (final raw in playback) {
    final row = _map(raw);
    if (row == null) continue;
    final id = key(row);
    if (id == null) continue;
    final playbackId = row['id'];
    if (playbackId is int) {
      playbackIds.putIfAbsent(id, () => {}).add(playbackId);
    }
    final episode = _map(row['episode']);
    final season = episode?['season'];
    final number = episode?['number'];
    final progress = row['progress'];
    final stamp = _stamp(row['paused_at']);
    final existing = result[id];
    final existingEpisode = _map(existing?['episode']);
    final sameEpisode =
        existingEpisode?['season'] == season &&
        existingEpisode?['number'] == number;
    // Trakt timestamps can have second precision. On a tie, enrich the exact
    // Up Next episode, but never change its coordinate or overwrite a chosen
    // playback checkpoint merely because another equal-time row came later.
    final matchingUpNextTie =
        sameEpisode &&
        !selectedPlayback.contains(id) &&
        stamp == (activity[id] ?? 0) &&
        stamp == _stamp(existing?['paused_at']);
    if (season is! int ||
        season < 0 ||
        number is! int ||
        number <= 0 ||
        progress is! num ||
        !progress.isFinite ||
        progress <= 0 ||
        progress >= 100 ||
        stamp == 0 ||
        !visible(id, row) ||
        uncertainHistory.contains(id) ||
        (stamp <= (activity[id] ?? 0) && !matchingUpNextTie)) {
      continue;
    }
    result[id] = {
      ...?existing,
      ...row,
      'type': 'episode',
      'show': {
        ...?_map(row['show']),
        ...?_map(existing?['show']),
        'ids': {
          ...?_map(_map(row['show'])?['ids']),
          ...?_map(_map(existing?['show'])?['ids']),
        },
      },
      'episode': {...episode!, if (sameEpisode) ...?existingEpisode},
    };
    activity[id] = stamp;
    selectedPlayback.add(id);
  }
  if (recoveredHidden > 0 || recoveredWatched > 0) {
    DiagnosticLog.instance.recordEvent(
      source: 'trakt',
      event: 'continue_watching_records_recovered',
      fields: {
        'hiddenCount': recoveredHidden,
        'watchedCount': recoveredWatched,
      },
    );
  }
  for (final entry in result.entries) {
    final ids = playbackIds[entry.key];
    if (ids != null && ids.isNotEmpty) {
      entry.value['_playback_ids'] = ids.toList();
    }
  }
  // Preserve provider order for ties, including undated Up Next rows.
  final order = result.values.toList();
  final ordinal = {for (var i = 0; i < order.length; i++) order[i]: i};
  order.sort((a, b) {
    final comparison = _stamp(b['paused_at']).compareTo(_stamp(a['paused_at']));
    return comparison != 0 ? comparison : ordinal[a]!.compareTo(ordinal[b]!);
  });
  return order;
}
