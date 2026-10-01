import '../../../models/series_source.dart';
import '../../../models/torrent.dart';

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
