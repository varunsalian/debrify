import '../models/quick_play_rules.dart';
import 'dart:convert';
import '../models/torrent.dart';
import 'series_source_fetcher.dart';
import 'stream_url_validator.dart';

/// One validation budget for the complete recovery, not one per search stage.
class RecoveryDirectPreflight {
  RecoveryDirectPreflight({
    required this.budget,
    required this.isMovie,
    this.probe = StreamUrlValidator.isPlayableVideoUrl,
    required this.shouldProbe,
  });
  int budget;
  final bool isMovie;
  final Future<bool> Function(
    String, {
    int minBytes,
    bool lenient,
    Map<String, String>? headers,
  })
  probe;
  final bool Function(Torrent) shouldProbe;
  final Map<String, bool> _results = {};

  Future<bool> allows(Torrent source, {required bool enabled}) async {
    if (!enabled ||
        source.streamType != StreamType.directUrl ||
        !shouldProbe(source))
      return true;
    final url = source.directUrl;
    if (url == null || url.isEmpty) return false;
    final headerKeys = source.httpHeaders?.keys.toList() ?? <String>[];
    headerKeys.sort();
    final key = jsonEncode([
      url,
      {for (final k in headerKeys) k: source.httpHeaders![k]},
    ]);
    if (_results.containsKey(key)) return _results[key]!;
    if (budget <= 0) return true;
    budget--;
    return _results[key] = await probe(
      url,
      minBytes: isMovie ? StreamUrlValidator.minContentBytes : 10 * 1024 * 1024,
      lenient: true,
      headers: source.httpHeaders,
    );
  }
}

/// A staged automatic retry list, separate from the complete manual browser.
class StartupRecoverySources {
  static List<String> stages({
    required bool isMovie,
    required QuickPlayRules rules,
    required String? provider,
  }) {
    if (isMovie) return ['movie'];
    final packsAllowed =
        provider != null &&
        provider != 'pikpak' &&
        rules.packPreference != QuickPlayPackPreference.exactEpisodeOnly;
    if (!packsAllowed) return ['episodes'];
    return rules.preferSeriesPacks
        ? ['packs', 'episodes']
        : ['episodes', 'packs'];
  }

  /// Merge all rows for manual browsing. Native retries only [automaticIndices]
  /// in the supplied order, keeping old indices stable across fetch stages.
  static ({List<Torrent> sources, List<int> automaticIndices}) merge({
    required List<Torrent> existing,
    required List<Torrent> fetched,
    required List<Torrent> automatic,
    bool replaceExistingAutomatic = false,
  }) {
    // Keep the eligible representation when the manual list has another row
    // for the same hash. Existing native indices must never move or change.
    final eligibleByKey = {
      for (final t in automatic) SeriesSourceFetcher.sourceKey(t): t,
    };
    final sources = SeriesSourceFetcher.mergeSources(existing, [
      for (final t in fetched)
        eligibleByKey[SeriesSourceFetcher.sourceKey(t)] ?? t,
    ]);
    final byKey = <String, int>{
      for (var i = 0; i < sources.length; i++)
        SeriesSourceFetcher.sourceKey(sources[i]): i,
    };
    if (replaceExistingAutomatic) {
      // A previous recovery stage may have kept an ineligible representation
      // for manual browsing. Upgrade that same hash in place without moving
      // indices; the native cursor still prevents replay of attempted rows.
      for (final t in automatic) {
        final index = byKey[SeriesSourceFetcher.sourceKey(t)];
        if (index != null) sources[index] = t;
      }
    }
    final indices = <int>{};
    for (final source in automatic) {
      final index = byKey[SeriesSourceFetcher.sourceKey(source)];
      if (index != null) indices.add(index);
    }
    return (sources: sources, automaticIndices: indices.toList());
  }
}
