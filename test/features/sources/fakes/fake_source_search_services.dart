import 'dart:async';
import 'package:debrify/features/sources/data/service_source_search_repository.dart';
import 'package:debrify/features/sources/data/source_search_repository.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';

class FakeSourceSearchServices {
  final main = Completer<Map<String, dynamic>>();
  final iptv = Completer<List<IptvSourceResult>>();
  final video = Completer<String?>();
  final calls = <String>[];
  final arguments = <String, Object?>{};
  SourceSearchBatch? batch;
  void Function(IptvSourceResult)? iptvResult;
  bool Function()? shouldContinue;
  late final ServiceSourceSearchRepository
  repository = ServiceSourceSearchRepository(
    owner: ProfileSessionMemory.captureOwner(),
    keywordSearch: (query, {required onBatch, required preserveSourceOrder}) {
      calls.add('keyword');
      arguments.addAll({'query': query, 'preserve': preserveSourceOrder});
      batch = onBatch;
      return main.future;
    },
    imdbSearch:
        (
          id, {
          required isMovie,
          season,
          episode,
          contentType,
          availableSeasons,
          required onBatch,
          required preserveSourceOrder,
          originAddonKey,
          originVideoId,
        }) {
          calls.add('imdb');
          arguments.addAll({
            'id': id,
            'movie': isMovie,
            'season': season,
            'episode': episode,
            'type': contentType,
            'seasons': availableSeasons,
            'preserve': preserveSourceOrder,
            'addon': originAddonKey,
            'video': originVideoId,
          });
          batch = onBatch;
          return main.future;
        },
    iptvSearch:
        (
          selection, {
          required onResult,
          required shouldContinue,
          required deferXtreamSeriesEpisodes,
        }) {
          calls.add('iptv');
          arguments['defer'] = deferXtreamSeriesEpisodes;
          iptvResult = onResult;
          this.shouldContinue = shouldContinue;
          return iptv.future;
        },
    resolveVideo:
        ({
          required addonKey,
          addonId,
          required catalogId,
          required season,
          required episode,
        }) {
          calls.add('resolve');
          arguments.addAll({
            'resolveAddon': addonKey,
            'resolveCatalog': catalogId,
            'resolveSeason': season,
            'resolveEpisode': episode,
          });
          return video.future;
        },
  );
}
