import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/storage_service.dart';
import '../../../services/stremio_service.dart';
import '../data/home_local_continuation_repository.dart';

final homeLocalContinuationRepositoryProvider =
    Provider<HomeLocalContinuationRepository>(
      (ref) => HomeLocalContinuationRepository(
        readProgressSource: StorageService.getWatchProgressSource,
        readEnabled: StorageService.getHomeContinueWatchingEnabled,
        readItems: StorageService.getContinueWatchingItems,
        readAddons: StremioService.instance.getEnabledAddons,
        readEpisode: StorageService.getLastPlayedEpisodeByImdbId,
        readMovie: StorageService.getVideoPlaybackStateByImdbId,
      ),
      dependencies: const [],
    );
