// One match's stats for the stats page, kept fresh while the match is live.
//
// Application layer. Lifetime: one notifier per open stats page
// (auto-disposed with it), keyed by league and event so two pages for
// different matches never share state. The data is public and device-wide —
// nothing here reads or writes profile storage. Polling belongs to this
// notifier and only runs while the match is live (or due to kick off) and
// the page says it may (app in the foreground, page on top). Retries are the poll's: Riverpod's
// automatic retry is off.
import 'dart:async';

import 'package:debrify/features/sports/application/sports_providers.dart';
import 'package:debrify/features/sports/data/sports_match_stats_client.dart';
import 'package:debrify/features/sports/models/sports_match_stats.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final sportsMatchStatsProvider = AsyncNotifierProvider.autoDispose
    .family<SportsMatchStatsNotifier, SportsMatchStats, SportsMatchKey>(
      SportsMatchStatsNotifier.new,
      retry: (_, _) => null,
    );

bool _always() => true;

class SportsMatchStatsNotifier extends AsyncNotifier<SportsMatchStats> {
  SportsMatchStatsNotifier(this.key);

  final SportsMatchKey key;

  /// How often a live match refreshes.
  static const Duration pollInterval = Duration(seconds: 60);

  late SportsMatchStatsClient _client;
  late DateTime Function() _clock;

  /// Bumped by every load; a load that is no longer the latest publishes
  /// nothing, so an old response cannot overwrite a newer one.
  int _generation = 0;
  Timer? _timer;

  /// Set by the page: false while it is covered or the app is in the
  /// background. A due poll waits for the next tick while it says no.
  bool Function() canPoll = _always;

  @override
  Future<SportsMatchStats> build() async {
    _client = ref.watch(sportsMatchStatsClientProvider);
    _clock = ref.watch(sportsMatchStatsClockProvider);
    ref.onDispose(() {
      _generation++;
      _timer?.cancel();
    });
    final generation = ++_generation;
    final stats = await _client.load(key);
    if (generation == _generation) _schedule(stats);
    return stats;
  }

  /// Loads the match again: the error screen's Retry, and every live poll.
  /// What is on screen stays while it loads, and stays if the load fails.
  Future<void> refresh() async {
    final generation = ++_generation;
    _timer?.cancel();
    if (!state.hasValue) state = const AsyncLoading();
    try {
      final stats = await _client.load(key);
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData(stats);
      _schedule(stats);
    } catch (error, stack) {
      if (!ref.mounted || generation != _generation) return;
      final shown = state.value;
      if (shown == null) {
        state = AsyncError(error, stack);
        return;
      }
      // Keep the last good stats and try again on the next tick. The URL in
      // the message is the public ESPN summary: nothing private to redact.
      debugPrint('Sports stats: refresh failed: $error');
      // A bug, not the network: keep where it happened.
      if (error is Error) debugPrint('$stack');
      _schedule(shown);
    }
  }

  /// A live match polls every [pollInterval]; a preview wakes at kick-off
  /// (then polls until the feed says it started), so a page left open turns
  /// live by itself. Anything else is settled.
  void _schedule(SportsMatchStats stats) {
    _timer?.cancel();
    final start = stats.start;
    final Duration delay;
    if (stats.status == SportsEventStatus.live) {
      delay = pollInterval;
    } else if (stats.status == SportsEventStatus.scheduled && start != null) {
      final untilStart = start.difference(_clock());
      delay = untilStart > pollInterval ? untilStart : pollInterval;
    } else {
      return;
    }
    _timer = Timer(delay, _tick);
  }

  void _tick() {
    if (!ref.mounted) return;
    if (!canPoll()) {
      _timer = Timer(pollInterval, _tick);
      return;
    }
    unawaited(refresh());
  }
}
