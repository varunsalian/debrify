import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/mdblist/mdblist_continue_watching_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/simkl/simkl_service.dart';
import '../../../services/trakt/trakt_continue_watching_service.dart';
import '../data/home_tracker_resume_repository.dart';
import '../models/home_catalog_session.dart';

final homeTrackerResumeRepositoryProvider = Provider.autoDispose
    .family<HomeTrackerResumeRepository, HomeCatalogSession>(
      (ref, session) {
        Future<T> scoped<T>(Future<T> Function() action) {
          final scope = session.owner.scope;
          return scope == null
              ? action()
              : ProfileRuntime.withCapturedScope(scope, action);
        }

        final repository = HomeTrackerResumeRepository(
          readTraktMovie: (id) => scoped(() async {
            final selection = await TraktContinueWatchingService.instance
                .resolveSelection(
                  traktContentType:
                      TraktContinueWatchingService.moviesContentType,
                  itemId: id,
                );
            return selection?.traktProgressPercent;
          }),
          readSimklMovie: (id) => scoped(
            () => SimklService.instance.fetchMoviePlaybackProgress(id),
          ),
          readMdblist: () =>
              scoped(() => MdblistContinueWatchingService.instance.fetch()),
          isOwnerCurrent: () =>
              session.owner == ProfileSessionMemory.captureOwner(),
          now: DateTime.now,
        );
        ref.onDispose(repository.dispose);
        return repository;
      },
      retry: (count, error) => null,
      dependencies: const [],
    );
