import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/stremio_service.dart';
import '../data/home_random_episode_selector.dart';

/// Stateless selection uses the same identity rules as ordinary playback.
final homeRandomEpisodeSelectorProvider = Provider<HomeRandomEpisodeSelector>(
  (ref) => HomeRandomEpisodeSelector(
    videoIdFor: StremioService.randomEpisodeVideoId,
    isCanonicalEpisode: StremioService.isCanonicalEpisodeId,
  ),
  dependencies: const [],
);
