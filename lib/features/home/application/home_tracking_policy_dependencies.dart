import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/storage_service.dart';
import '../../../services/tracking_source_policy.dart';
import '../data/home_tracking_policy_repository.dart';

final homeTrackingPolicyRepositoryProvider = Provider.autoDispose
    .family<HomeTrackingPolicyRepository, ProfileSessionOwner>(
      (ref, owner) {
        Future<T> scoped<T>(Future<T> Function() action) {
          final scope = owner.scope;
          return scope == null
              ? action()
              : ProfileRuntime.withCapturedScope(scope, action);
        }

        return HomeTrackingPolicyRepository(
          isOwnerCurrent: () => owner == ProfileSessionMemory.captureOwner(),
          readTargets: (current) => scoped(
            () =>
                StorageService.getTrackingScrobbleTargets(canContinue: current),
          ),
          readProgress: () => scoped(StorageService.getWatchProgressSource),
          hasCredential: (source, current) => scoped(
            () => switch (source) {
              TrackingSource.trakt => StorageService.hasTraktCredential(
                canContinue: current,
              ),
              TrackingSource.simkl => StorageService.hasSimklCredential(
                canContinue: current,
              ),
              TrackingSource.mdblist => StorageService.hasMdblistCredential(
                canContinue: current,
              ),
              TrackingSource.local => Future.value(true),
            },
          ),
          fallbackDisconnected: (source, current) => scoped(
            () => StorageService.fallbackDisconnectedProgressSource(
              source,
              canContinue: current,
            ),
          ),
          readTicks: () => scoped(StorageService.getHomeTickSources),
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );
