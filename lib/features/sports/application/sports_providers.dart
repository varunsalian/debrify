// Composition boundary for the sports board feature.
//
// Application layer: this is the only sports file that reaches concrete
// adapters from `data/`, and it only declares how to build them. Nothing here
// starts work: the board controller fetches when the view asks for a refresh,
// and the app overrides the profile-backed stores in its own ProviderScope.
import 'package:debrify/features/sports/data/sports_feed_client.dart';
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/data/sports_http_fetch.dart';
import 'package:debrify/features/sports/models/sports_guide_contract.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// The leagues the board fetches, in catalog order.
final sportsLeaguesProvider = Provider<List<SportsLeague>>(
  (ref) => kSportsLeagues,
  dependencies: const [],
);

/// A guide with no playlist loaded: the board still shows fixtures.
class _EmptySportsGuideSource implements SportsGuideSource {
  const _EmptySportsGuideSource();

  @override
  Future<SportsGuideSnapshot> load(SportsGuideQuery query) async =>
      SportsGuideSnapshot.empty;
}
