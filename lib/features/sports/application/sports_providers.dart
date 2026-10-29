// Composition boundary for the sports board feature.
//
// Application layer: this is the only sports file that reaches concrete
// adapters from `data/`, and it only declares how to build them. Nothing here
// starts work: the board controller fetches when the view asks for a refresh,
// and the app overrides the profile-backed stores in its own ProviderScope.
import 'package:debrify/features/sports/application/sports_league_filter_notifier.dart';
import 'package:debrify/features/sports/data/sports_feed_client.dart';
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/data/sports_http_fetch.dart';
import 'package:debrify/features/sports/data/sports_league_filter_store.dart';
import 'package:debrify/features/sports/models/sports_guide_contract.dart';
import 'package:debrify/features/sports/models/sports_league_filter.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// `sports_providers.dart` exports the filter type and `sports_league_filter.dart`
// also imports it here. Both paths stay: the export is how a caller that only
// wires providers names the type, the import is what this file itself compiles
// against. Without the ignore, either half alone flags the other as redundant.
// ignore_for_file: unnecessary_import
export 'package:debrify/features/sports/application/sports_league_filter_notifier.dart';
export 'package:debrify/features/sports/models/sports_league_filter.dart';

/// One feed cache shared by every board instance.
final sportsFeedClientProvider = Provider<SportsFeedClient>(
  (ref) => SportsFeedClient(fetch: httpSportsFetch),
  dependencies: const [],
);

/// Followed leagues, teams and the score-hiding choice.
///
/// The store is profile-bound, so the app must wire it per active profile
/// rather than letting a device-wide default write into the wrong storage.
final sportsFollowStoreProvider = Provider<SportsFollowStore>(
  (ref) =>
      throw UnimplementedError('sportsFollowStoreProvider must be overridden'),
  dependencies: const [],
);

/// The user's IPTV guide; the app wires the SQLite source next to a playlist.
final sportsGuideSourceProvider = Provider<SportsGuideSource>(
  (ref) => const _EmptySportsGuideSource(),
  dependencies: const [],
);

/// Single clock for board windows, guide windows and the refresh timer.
final sportsClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
  dependencies: const [],
);

/// The leagues the board fetches: the catalog with the user's filter applied.
///
/// While the filter is still loading, or if it failed to read, the board
/// shows the plain catalog defaults.
final sportsLeaguesProvider = Provider<List<SportsLeague>>((ref) {
  final filter = ref.watch(sportsLeagueFilterProvider).value;
  return enabledSportsLeagues(
    kSportsLeagues,
    filter ?? const SportsLeagueFilter(),
  );
}, dependencies: const []);

/// The user's league on/off choices.
///
/// These four providers are app-wide, so they declare no `dependencies`:
/// that keeps them outside Riverpod's scoping checks and lets the board's
/// device-wide providers read them. The app wires the profile-backed store
/// and the profile signals in its own root ProviderScope.
final sportsLeagueFilterStoreProvider = Provider<SportsLeagueFilterStore>(
  (ref) => throw UnimplementedError(
    'sportsLeagueFilterStoreProvider must be overridden',
  ),
  retry: (_, _) => null,
);

/// Identity of the active profile; the app overrides it.
final sportsProfileOwnerProvider = Provider<Object? Function()>(
  (ref) =>
      () => null,
  retry: (_, _) => null,
);

/// Fires when the active profile changes; the app overrides it.
final sportsProfileChangesProvider = Provider<Listenable?>(
  (ref) => null,
  retry: (_, _) => null,
);

final sportsLeagueFilterProvider =
    AsyncNotifierProvider<SportsLeagueFilterNotifier, SportsLeagueFilter>(
      SportsLeagueFilterNotifier.new,
      retry: (_, _) => null,
    );

/// A guide with no playlist loaded: the board still shows fixtures.
class _EmptySportsGuideSource implements SportsGuideSource {
  const _EmptySportsGuideSource();

  @override
  Future<SportsGuideSnapshot> load(SportsGuideQuery query) async =>
      SportsGuideSnapshot.empty;
}
