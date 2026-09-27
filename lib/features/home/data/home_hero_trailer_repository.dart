import '../../../models/metadata_preferences.dart';
import '../../../models/stremio_addon.dart';
import '../../../services/metadata_details_service.dart' show MetadataTrailer;
import '../../../services/youtube_service.dart' show YoutubeResolvedStreams;

/// Existing metadata and stream services used by ambient hero resolution.
class HomeHeroTrailerRepository {
  const HomeHeroTrailerRepository({
    required this.readPreferences,
    required this.selectTrailers,
    required this.fetchDetails,
    required this.resolveYoutube,
    required this.resolveImdb,
  });

  final Future<MetadataPreferences?> Function(bool Function() current)
  readPreferences;
  final Future<List<MetadataTrailer>> Function(
    StremioMeta item,
    Future<String?> Function() originalTrailer,
    MetadataPreferences preferences,
  )
  selectTrailers;
  final Future<StremioMeta?> Function(String imdbId, String type) fetchDetails;
  final Future<YoutubeResolvedStreams?> Function(String id) resolveYoutube;
  final Future<YoutubeResolvedStreams?> Function(String imdbId) resolveImdb;
}
