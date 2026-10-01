import 'dart:async';

import 'package:debrify/features/sources/application/source_iptv_availability.dart';
import 'package:debrify/features/sources/application/source_search_plans.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/media_identity.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
import 'package:flutter/foundation.dart';

final class IptvQuickPlaySearch {
  const IptvQuickPlaySearch._();

  /// Cached IPTV candidates for automatic playback and episode advancement.
  /// Direct-link and source-mode restrictions apply before any catalog lookup.
  @visibleForTesting
  static Future<List<Torrent>> searchIptvForQuickPlay(
    String id,
    String title,
    String? year,
    bool isMovie,
    int? season,
    int? episode,
    QuickPlayRules rules,
    bool Function()? isCancelled, {
    @visibleForTesting
    Duration discoveryTimeout =
        SourceIptvAvailability.iptvQuickPlaySearchTimeout,
  }) async {
    if (!rules.allowDirectLinks ||
        // ignore: invalid_use_of_visible_for_testing_member
        !SourceSearchPlans.allowsAddonSearch(rules) ||
        (!id.startsWith('tt') && !MediaIdentity.isNative(id))) {
      logIptvSourceEvent(
        'quick_play_search_skipped',
        catalogType: isMovie ? 'vod' : 'series',
        season: season,
        episode: episode,
        outcome: !rules.allowDirectLinks
            ? 'direct_links_disabled'
            // ignore: invalid_use_of_visible_for_testing_member
            : (!SourceSearchPlans.allowsAddonSearch(rules)
                  ? 'source_mode_excluded'
                  : 'unsupported_identity'),
      );
      return [];
    }
    final stopwatch = Stopwatch()..start();
    logIptvSourceEvent(
      'quick_play_search_started',
      catalogType: isMovie ? 'vod' : 'series',
      season: season,
      episode: episode,
    );
    final scope = ProfileRuntime.scope.value;
    var expired = false;
    var timedOut = false;
    final completed = <IptvSourceResult>[];
    final results =
        await IptvSourceSearch.search(
          AdvancedSearchSelection(
            imdbId: id,
            title: title,
            year: year,
            isSeries: !isMovie,
            season: season,
            episode: episode,
          ),
          deferXtreamSeriesEpisodes: true,
          shouldContinue: () =>
              !expired &&
              ProfileRuntime.scope.value == scope &&
              !(isCancelled?.call() ?? false),
          onResult: (result) {
            if (!expired) completed.add(result);
          },
        ).timeout(
          discoveryTimeout,
          onTimeout: () {
            expired = true;
            timedOut = true;
            return List<IptvSourceResult>.of(completed);
          },
        );
    expired = true;
    if (ProfileRuntime.scope.value != scope || (isCancelled?.call() ?? false)) {
      logIptvSourceEvent(
        'quick_play_search_completed',
        catalogType: isMovie ? 'vod' : 'series',
        season: season,
        episode: episode,
        outcome: ProfileRuntime.scope.value != scope
            ? 'profile_changed'
            : 'cancelled',
        timedOut: timedOut,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
      return [];
    }
    final expectedYear = RegExp(r'^\d{4}').stringMatch(year ?? '');
    // Broad yearless matches remain in manual Sources. Automatic movie picks
    // require an explicit release-year tag to avoid silently choosing a remake.
    final filtered = [
      for (final result in results)
        for (final source in result.torrents)
          if (!isMovie ||
              (expectedYear != null &&
                  RegExp(
                    '(?:[\\[(]$expectedYear[\\])]|\\s$expectedYear(?:\\s|\$))',
                  ).hasMatch(source.name)))
            source,
    ];
    logIptvSourceEvent(
      'quick_play_search_completed',
      catalogType: isMovie ? 'vod' : 'series',
      season: season,
      episode: episode,
      outcome: filtered.isEmpty ? 'no_match' : 'matched',
      playlistCount: results.length,
      candidateCount: results.fold<int>(
        0,
        (count, result) => count + result.torrents.length,
      ),
      resultCount: filtered.length,
      timedOut: timedOut,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
    return filtered;
  }
}
