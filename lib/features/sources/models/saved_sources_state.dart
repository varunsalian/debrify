import '../../../models/torrent.dart';
import '../../../services/series_source_service.dart';

class SavedSourcesState {
  final List<SeriesSource> sources;
  final Torrent? cachedEpisode;
  final bool cacheUnavailable;

  SavedSourcesState({
    List<SeriesSource> sources = const [],
    this.cachedEpisode,
    this.cacheUnavailable = false,
  }) : sources = List.unmodifiable(sources);
}
