// The sports board's presentation state and the action that owns it.
//
// Application layer: the controller is the only owner of the merged fixture
// list, the follow choices shown on the board and the guide matches found for
// them. It fetches nothing until the view calls [SportsBoardController.refresh]
// and drops any result whose profile session or generation has moved on.
import 'dart:async';

import 'package:debrify/features/sports/application/sports_board_sections.dart';
import 'package:debrify/features/sports/application/sports_channel_matcher.dart';
import 'package:debrify/features/sports/application/sports_names.dart';
import 'package:debrify/features/sports/application/sports_providers.dart';
import 'package:debrify/features/sports/data/sports_feed_client.dart';
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/models/sports_guide_contract.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A board belongs to one mounted view in one profile session. The view
/// supplies a fresh identity so two routes showing the same league never share
/// mutable board state.
typedef SportsSession = ({ProfileSessionOwner owner, Object viewIdentity});

/// A fresh board session for one mounted view in the active profile session.
SportsSession captureSportsSession() =>
    (owner: ProfileSessionMemory.captureOwner(), viewIdentity: Object());

/// Shown when no league feed produced anything at all.
const String kSportsBoardLoadFailed =
    "Couldn't load fixtures. Check your connection and try again.";

/// Everything the board renders for one view.
@immutable
class SportsBoardState {
  const SportsBoardState({
    this.events = const [],
    this.follows = const SportsFollows(),
    this.filter = SportsBoardFilter.week,
    this.loading = false,
    this.error,
    this.updatedAt,
    this.watch = const {},
    this.liveSportsListings = const [],
  });

  /// Merged, de-duplicated and sorted by start then id.
  final List<SportsEvent> events;

  final SportsFollows follows;

  /// Active segmented-control choice.
  final SportsBoardFilter filter;

  final bool loading;

  /// Set only when the whole refresh failed.
  final String? error;

  final DateTime? updatedAt;

  /// Watch options keyed by `'<leagueId>/<eventId>'`.
  final Map<String, SportsWatchOptions> watch;

  /// What is airing now on the user's sports channels.
  final List<SportsGuideListing> liveSportsListings;

  SportsWatchOptions watchFor(SportsEvent event) =>
      watch['${event.leagueId}/${event.id}'] ?? SportsWatchOptions.empty;

  /// A copy with the supplied fields replaced; null fields keep their value.
  ///
  /// `error` needs [clearError] because a successful refresh must be able to
  /// say "no error" without inventing a sentinel string.
  SportsBoardState copyWith({
    List<SportsEvent>? events,
    SportsFollows? follows,
    SportsBoardFilter? filter,
    bool? loading,
    String? error,
    bool clearError = false,
    DateTime? updatedAt,
    Map<String, SportsWatchOptions>? watch,
    List<SportsGuideListing>? liveSportsListings,
  }) => SportsBoardState(
    events: events ?? this.events,
    follows: follows ?? this.follows,
    filter: filter ?? this.filter,
    loading: loading ?? this.loading,
    error: clearError ? null : error ?? this.error,
    updatedAt: updatedAt ?? this.updatedAt,
    watch: watch ?? this.watch,
    liveSportsListings: liveSportsListings ?? this.liveSportsListings,
  );
}

final sportsBoardProvider = NotifierProvider.autoDispose
    .family<SportsBoardController, SportsBoardState, SportsSession>(
      SportsBoardController.new,
      retry: (count, error) => null,
      dependencies: [
        sportsFeedClientProvider,
        sportsFollowStoreProvider,
        sportsGuideSourceProvider,
        sportsClockProvider,
        sportsLeaguesProvider,
      ],
    );

/// Owns one board: fixtures, follows, guide matches and the refresh cadence.
class SportsBoardController extends Notifier<SportsBoardState> {
  SportsBoardController(this.session);

  final SportsSession session;

  late SportsFeedClient _client;
  late SportsFollowStore _store;
  late SportsGuideSource _guideSource;
  late DateTime Function() _clock;
  late List<SportsLeague> _leagues;

  int _generation = 0;
  Timer? _timer;

  @override
  SportsBoardState build() {
    _client = ref.watch(sportsFeedClientProvider);
    _store = ref.watch(sportsFollowStoreProvider);
    _guideSource = ref.watch(sportsGuideSourceProvider);
    _clock = ref.watch(sportsClockProvider);
    _leagues = ref.watch(sportsLeaguesProvider);
    ref.onDispose(() {
      _generation++;
      _timer?.cancel();
    });
    return const SportsBoardState(loading: true);
  }

  /// Loads every league feed, merges them with the stored follows and refreshes
  /// the guide matches. [force] bypasses the feed cache (a manual refresh).
  ///
  /// A failed league is dropped silently; only a refresh where every league
  /// failed and nothing is on screen reports an error.
  Future<void> refresh({bool force = false}) async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        session.owner == ProfileSessionMemory.captureOwner();

    final now = _clock();
    final fromUtc = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(_windowBack).toUtc();
    final toUtc = now.add(_windowForward).toUtc();

    var follows = state.follows;
    try {
      final stored = await _store.read();
      if (!current()) return;
      follows = stored;
    } catch (_) {
      // An unreadable store keeps the follows already on screen; the fixtures
      // are still worth loading, and the next refresh reads them again.
    }

    final batches = await Future.wait([
      for (final league in _leagues) _fetch(league, fromUtc, toUtc, force),
    ]);
    if (!current()) return;

    var failures = 0;
    final merged = <String, SportsEvent>{};
    for (final batch in batches) {
      if (batch == null) {
        failures++;
        continue;
      }
      for (final event in batch) {
        merged.putIfAbsent('${event.leagueId}/${event.id}', () => event);
      }
    }
    final events = merged.values.toList()..sort(_byStartThenId);

    if (events.isEmpty && failures > 0 && failures == _leagues.length) {
      state = state.copyWith(loading: false, error: kSportsBoardLoadFailed);
      _schedule(state.events);
      return;
    }

    state = state.copyWith(
      events: events,
      follows: follows,
      loading: false,
      clearError: true,
      updatedAt: now,
    );
    await _applyGuide(now, events, current);
    if (!current()) return;
    _schedule(events);
  }

  /// Chooses the filter; the rows are derived by the view, so nothing reloads.
  void setFilter(SportsBoardFilter filter) {
    if (!ref.mounted) return;
    state = state.copyWith(filter: filter);
  }

  /// Follows or unfollows a league. The choice is visible immediately and the
  /// write is skipped once the profile session has moved on.
  Future<void> toggleLeague(String leagueId) async {
    if (!ref.mounted) return;
    final leagueIds = {...state.follows.leagueIds};
    if (!leagueIds.remove(leagueId)) leagueIds.add(leagueId);
    await _commitFollows(state.follows.copyWith(leagueIds: leagueIds));
  }

  /// Follows or unfollows one team, keyed `'<leagueId>:<teamId>'`.
  Future<void> toggleTeam(String teamKey) async {
    if (!ref.mounted) return;
    final teamKeys = {...state.follows.teamKeys};
    if (!teamKeys.remove(teamKey)) teamKeys.add(teamKey);
    await _commitFollows(state.follows.copyWith(teamKeys: teamKeys));
  }

  /// Hides or shows scores; the same write path as a follow toggle.
  Future<void> setHideScores(bool hide) async {
    if (!ref.mounted) return;
    await _commitFollows(state.follows.copyWith(hideScores: hide));
  }

  /// One owner for both follow writes: publish, then persist for this session.
  Future<void> _commitFollows(SportsFollows follows) async {
    if (!ref.mounted) return;
    state = state.copyWith(follows: follows);
    if (session.owner != ProfileSessionMemory.captureOwner()) return;
    await _store.write(follows);
  }

  /// One league's fixtures, or null when that league failed entirely.
  Future<List<SportsEvent>?> _fetch(
    SportsLeague league,
    DateTime fromUtc,
    DateTime toUtc,
    bool force,
  ) async {
    try {
      return await _client.fetchLeague(
        league,
        fromUtc: fromUtc,
        toUtc: toUtc,
        force: force,
      );
    } catch (_) {
      // A dead league contributes nothing to this board.
      return null;
    }
  }

  /// Matches the near fixtures against the guide and publishes the results.
  Future<void> _applyGuide(
    DateTime now,
    List<SportsEvent> events,
    bool Function() current,
  ) async {
    final near = [
      for (final event in events)
        if (_isNear(now, event)) event,
    ];
    var snapshot = SportsGuideSnapshot.empty;
    try {
      final loaded = await _guideSource.load(
        SportsGuideQuery(
          fromUtc: now.subtract(_guidePast).toUtc(),
          toUtc: now.add(_guideFuture).toUtc(),
          nowUtc: now.toUtc(),
          titleNeedles: _titleNeedles(near),
          channelNeedles: _channelNeedles(near),
        ),
      );
      if (!current()) return;
      snapshot = loaded;
    } catch (_) {
      // An unreadable guide means no watch options this round, nothing more.
    }
    if (!current()) return;
    state = state.copyWith(
      watch: {
        for (final event in near)
          '${event.leagueId}/${event.id}': matchSportsEvent(
            event,
            listings: snapshot.listings,
            channels: snapshot.channels,
          ),
      },
      liveSportsListings: snapshot.liveSportsListings,
    );
  }

  /// Short while anything is live, quiet otherwise.
  void _schedule(List<SportsEvent> events) {
    _timer?.cancel();
    final live = events.any((event) => event.status == SportsEventStatus.live);
    _timer = Timer(
      live ? _liveRefresh : _idleRefresh,
      () => unawaited(refresh()),
    );
  }

  bool _isNear(DateTime now, SportsEvent event) =>
      event.status == SportsEventStatus.live ||
      (!event.start.isBefore(now.subtract(_guidePast).toUtc()) &&
          !event.start.isAfter(now.add(_guideFuture).toUtc()));

  List<String> _titleNeedles(List<SportsEvent> events) {
    final needles = <String>[];
    for (final event in events) {
      for (final needle in sportsTitleNeedles(event)) {
        if (!needles.contains(needle)) needles.add(needle);
      }
    }
    return needles;
  }

  List<String> _channelNeedles(List<SportsEvent> events) {
    final needles = <String>[];
    for (final event in events) {
      for (final broadcaster in event.broadcasts) {
        final base = channelBaseName(broadcaster);
        if (base.isEmpty || needles.contains(base)) continue;
        needles.add(base);
      }
    }
    return needles;
  }
}

const Duration _windowBack = Duration(days: 1);
const Duration _windowForward = Duration(days: 7);
const Duration _guidePast = Duration(hours: 3);
const Duration _guideFuture = Duration(hours: 36);
const Duration _liveRefresh = Duration(seconds: 90);
const Duration _idleRefresh = Duration(minutes: 15);

int _byStartThenId(SportsEvent a, SportsEvent b) {
  final byStart = a.start.compareTo(b.start);
  return byStart != 0 ? byStart : a.id.compareTo(b.id);
}
