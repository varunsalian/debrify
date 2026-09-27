import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/trakt/trakt_continue_watching_service.dart';
import '../../../services/trakt/trakt_service.dart';
import '../data/home_trakt_continuation_repository.dart';

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
