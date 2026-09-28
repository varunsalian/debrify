import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/mdblist/mdblist_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/simkl/simkl_service.dart';
import '../../../services/stremio_service.dart';
import '../../../services/trakt/trakt_service.dart';
import '../data/home_detail_readers.dart';

/// Stateless readers borrow existing services and keep the opening profile scope.
/// Disposal does not cancel service-owned caches or another route's shared reads.
final homeDetailReadersProvider = Provider.autoDispose
    .family<HomeDetailReaders, ProfileSessionOwner>(
      (ref, owner) {
        Future<T> scoped<T>(Future<T> Function() action) {
          final scope = owner.scope;
          return scope == null
              ? action()
              : ProfileRuntime.withCapturedScope(scope, action);
        }

        return HomeDetailReaders(
          isOwnerCurrent: () => owner == ProfileSessionMemory.captureOwner(),
          trakt: (id, type, current) =>
              scoped(() => TraktService.instance.fetchTitleStatus(id, type)),
          simkl: (id, type, current) => scoped(
            () => SimklService.instance.fetchTitleStatus(
              id,
              contentType: type,
              canContinue: current,
            ),
          ),
          mdblist: (id, type, current) =>
              scoped(() => MdblistService.instance.fetchTitleStatus(id, type)),
          recommendations: (id, type, current) => scoped(
            () => StremioService.instance.getRecommendations(
              imdbId: id,
              type: type,
            ),
          ),
          metadata: (id, type, current) => scoped(
            () => StremioService.instance.fetchMetaDetails(
              imdbId: id,
              type: type,
            ),
          ),
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );
