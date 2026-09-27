import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/episode_tracker_snapshot_revision.dart';
import '../../../services/next_episode_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_series_resume_resolver.dart';
import '../models/home_catalog_session.dart';
import 'home_series_resume_dependencies.dart';
import 'home_tracker_resume_dependencies.dart';
import 'home_tracking_policy_dependencies.dart';

final homeSeriesResumeResolverProvider = Provider.autoDispose
    .family<HomeSeriesResumeResolver, HomeCatalogSession>(
      (ref, session) {
        final resolver = HomeSeriesResumeResolver(
          signals: ref.watch(homeSeriesResumeRepositoryProvider(session.owner)),
          trackers: ref.watch(homeTrackerResumeRepositoryProvider(session)),
          policies: ref.watch(
            homeTrackingPolicyRepositoryProvider(session.owner),
          ),
          findNextEpisode:
              (id, season, episode, {required preferBuiltIn, catalogItem}) {
                Future<({int season, int episode})?> read() =>
                    NextEpisodeService.findNextEpisode(
                      id,
                      season,
                      episode,
                      preferBuiltIn: preferBuiltIn,
                      catalogItem: catalogItem,
                    );
                final scope = session.owner.scope;
                return scope == null
                    ? read()
                    : ProfileRuntime.withCapturedScope(scope, read);
              },
          readRevision: EpisodeTrackerSnapshotRevision.identity,
          isOwnerCurrent: () =>
              session.owner == ProfileSessionMemory.captureOwner(),
          now: DateTime.now,
          log: debugPrint,
        );
        ref.onDispose(resolver.dispose);
        return resolver;
      },
      retry: (count, error) => null,
      dependencies: [
        homeSeriesResumeRepositoryProvider,
        homeTrackerResumeRepositoryProvider,
        homeTrackingPolicyRepositoryProvider,
      ],
    );
