import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/trakt/trakt_continue_watching_service.dart';
import '../../../services/trakt/trakt_service.dart';
import '../data/home_trakt_continuation_repository.dart';
import '../data/home_trakt_history_removal.dart';
import '../../../services/profiles/profile_session_memory.dart';

final homeTraktContinuationRepositoryProvider =
    Provider<HomeTraktContinuationRepository>(
      (ref) => HomeTraktContinuationRepository(
        isAuthenticated: () => TraktService.instance.isAuthenticated(),
        readMovies: () =>
            TraktContinueWatchingService.instance.fetchMoviesOrNull(),
        readShows: () =>
            TraktContinueWatchingService.instance.fetchShowsOrNull(),
      ),
      dependencies: const [],
    );

final homeTraktHistoryRemovalProvider = Provider.autoDispose
    .family<HomeTraktHistoryRemoval, ProfileSessionOwner>(
      (ref, owner) => HomeTraktHistoryRemoval(owner),
      dependencies: const [],
    );
