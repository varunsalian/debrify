import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/simkl/simkl_service.dart';
import '../../../services/storage_service.dart';
import '../../../services/trakt/trakt_continue_watching_service.dart';
import '../data/home_series_resume_repository.dart';

/// Stateless adapters may outlive provider disposal for an accepted call.
/// Captured profile ownership and the originating view guard govern acceptance;
/// services retain ownership of their own caches, credentials and native work.
final homeSeriesResumeRepositoryProvider = Provider.autoDispose
    .family<HomeSeriesResumeRepository, ProfileSessionOwner>(
      (ref, owner) {
        Future<T> scoped<T>(Future<T> Function() action) {
          final scope = owner.scope;
          return scope == null
              ? action()
              : ProfileRuntime.withCapturedScope(scope, action);
        }

        return HomeSeriesResumeRepository(
          selectTraktItem: (item, current) => scoped(
            () => TraktContinueWatchingService.instance.selectionForItem(
              item,
              canContinue: current,
            ),
          ),
          readTraktShows: () => scoped(
            () => TraktContinueWatchingService.instance.fetchItems(
              TraktContinueWatchingService.showsContentType,
            ),
          ),
          resolveTraktShow: (id) => scoped(
            () => TraktContinueWatchingService.instance.resolveSelection(
              traktContentType: TraktContinueWatchingService.showsContentType,
              itemId: id,
            ),
          ),
          readSimklPaused: (id) => scoped(
            () => SimklService.instance.fetchShowPlaybackSelection(id),
          ),
          readSimklNext: (id) =>
              scoped(() => SimklService.instance.fetchNextToWatch(id)),
          readLocalById: (id) =>
              scoped(() => StorageService.getLastPlayedEpisodeByImdbId(id)),
          readLocalByTitle: (title) => scoped(
            () => StorageService.getLastPlayedEpisode(seriesTitle: title),
          ),
          isOwnerCurrent: () => owner == ProfileSessionMemory.captureOwner(),
          log: debugPrint,
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );
