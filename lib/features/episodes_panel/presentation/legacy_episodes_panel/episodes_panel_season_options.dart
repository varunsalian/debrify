import 'dart:async';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_services.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/media_identity.dart';
import 'package:debrify/services/season_watched_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';

class EpisodesPanelSeasonOptions {
  final EpisodesPanelDeps _deps;
  EpisodesPanelSeasonOptions(this._deps);
  EpisodesPanelViewState get _s => _deps.parts.viewState;
  EpisodesPanelAuth get _a => _deps.parts.auth;
  EpisodesPanelServices get _sv => _deps.parts.services;
  bool get mounted => _deps.mounted();

  bool seasonActionBusy = false;

  final seasonRetries = SeasonWatchedRetryState();

  Future<void> showSeasonOptions(int number) async {
    if (_a.isDirectSource || seasonActionBusy) return;
    final show = _s.selectedShow;
    if (show == null) return;
    seasonActionBusy = true;
    try {
      final connected = [
        true,
        ...await Future.wait([
          _sv.traktService.isAuthenticated(),
          _sv.simklService.isAuthenticated(),
          _sv.mdblistService.isAuthenticated(),
        ]),
      ];
      if (CustomSeriesIdentity.isCustom(show.imdbId)) {
        connected.fillRange(1, connected.length, false);
      }
      if (MediaIdentity.isNative(show.progressId)) {
        connected[1] = false;
        connected[3] = false;
      }
      if (!mounted) return;
      final providers = [
        TrackingSource.local,
        TrackingSource.trakt,
        TrackingSource.simkl,
        TrackingSource.mdblist,
      ];
      final names = ['locally', 'on Trakt', 'on Simkl', 'on MDBList'];
      var season = _s.episodeSeasons
          .where((s) => s.number == number)
          .firstOrNull;
      if (season == null || season.episodes.isEmpty) {
        final seasons = await _deps.parts.seasons.fetchSeasons(show);
        season = seasons.where((s) => s.number == number).firstOrNull;
      }
      if (!mounted) return;
      if (season == null || season.episodes.isEmpty) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          const SnackBar(
            content: Text('Could not load season episodes. Please retry.'),
          ),
        );
        return;
      }
      final episodeNumbers = season.episodes.map((e) => e.number).toList();
      final statuses = await Future.wait([
        for (var i = 0; i < providers.length; i++)
          connected[i]
              ? SeasonWatchedService.isWatched(
                  show.progressId ?? show.id,
                  show.name,
                  number,
                  episodeNumbers,
                  providers[i],
                )
              : Future<bool?>.value(null),
      ]);
      if (!mounted) return;
      final id = show.progressId ?? show.id;
      final retryTargets = [
        for (final provider in providers)
          seasonRetries.pending(id, number, provider),
      ];
      final targets = [
        for (var i = 0; i < providers.length; i++)
          retryTargets[i] ?? (statuses[i] == null ? null : !statuses[i]!),
      ];
      final choice = await showModalBottomSheet<TrackingSource>(
        context: _deps.context(),
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => TvHeldKeyGuard(
          child: SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(title: Text('Season $number')),
                  for (var i = 0; i < providers.length; i++)
                    if (connected[i])
                      ListTile(
                        leading: const Icon(Icons.done_all_rounded),
                        autofocus:
                            _deps.isTelevision() &&
                            !connected.take(i).any((value) => value),
                        enabled: targets[i] != null,
                        title: Text(
                          targets[i] == null
                              ? 'Watch status unavailable ${names[i]}'
                              : '${retryTargets[i] != null ? 'Retry: mark' : 'Mark'} season as ${targets[i]! ? 'watched' : 'unwatched'} ${names[i]}',
                        ),
                        subtitle: targets[i] == null
                            ? const Text('Close and reopen to retry.')
                            : null,
                        onTap: () => Navigator.pop(ctx, providers[i]),
                      ),
                ],
              ),
            ),
          ),
        ),
      );
      if (choice == null || !mounted) return;
      final name = names[providers.indexOf(choice)];
      final watched = targets[providers.indexOf(choice)]!;
      final action = watched ? 'watched' : 'unwatched';
      final messenger = ScaffoldMessenger.of(_deps.context());
      messenger.showSnackBar(
        SnackBar(content: Text('Marking Season $number $action $name…')),
      );
      // Retain intent through partial failure or an exception. A fresh status
      // may now be partial, but must not reverse the user's pending operation.
      seasonRetries.begin(id, number, choice, watched);
      final failures = await SeasonWatchedService.mark(
        id,
        number,
        episodeNumbers,
        choice,
        seriesTitle: show.name,
        watched: watched,
      );
      if (failures == 0) seasonRetries.complete(id, number, choice);
      if (!mounted) return;
      _deps.refreshWatchProgress();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failures == 0
                ? 'Season $number marked $action $name.'
                : 'Could not mark $failures episodes $action $name. Reopen the season menu to retry.',
          ),
        ),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not update season watch status. Please retry.',
            ),
          ),
        );
    } finally {
      seasonActionBusy = false;
    }
  }
}
