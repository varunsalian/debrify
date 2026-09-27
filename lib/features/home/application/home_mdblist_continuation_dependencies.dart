import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/mdblist/mdblist_continue_watching_service.dart';
import '../../../services/mdblist/mdblist_sync_coordinator.dart';
import '../data/home_mdblist_continuation_repository.dart';

final homeMdblistContinuationRepositoryProvider =
    Provider<HomeMdblistContinuationRepository>(
      (ref) => HomeMdblistContinuationRepository(
        invalidate: () => MdblistContinueWatchingService.instance.invalidate(),
        synchronizeInvalidations: () =>
            MdblistSyncCoordinator.instance.synchronizeInvalidations(),
        fetch: ({required force}) =>
            MdblistContinueWatchingService.instance.fetch(force: force),
      ),
      dependencies: const [],
    );
