import '../../../models/media_identity.dart';
import '../../../services/local_series_completion_service.dart';
import '../../../services/native_series_metadata_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/stremio_service.dart';
import '../models/sources_session.dart';
import 'source_seasons_repository.dart';

// Keep raw metadata and inventory operations inside the adapter boundary.
class StremioSourceSeasonsRepository implements SourceSeasonsRepository {
  const StremioSourceSeasonsRepository(this.session);
  final SourcesSession session;

  @override
  bool get isCurrent => session.owner == ProfileSessionMemory.captureOwner();

  @override
  Future<SourceSeasonGuide?> load() async {
    if (!isCurrent || session.selection.imdbId.isEmpty) return null;
    final selection = session.selection;
    final builtIn =
        !selection.hasStremioEpisodeIdentity &&
        (MediaIdentity.isNative(selection.imdbId) ||
            session.metadataAddonId == NativeSeriesMetadataService.addon.id);
    Future<List<Map<String, dynamic>>?> fetch() =>
        StremioService.instance.fetchSourcesSeriesGuide(
          imdbId: selection.imdbId,
          catalogItem: session.catalogItem,
          builtIn: builtIn,
        );
    final scope = session.owner.scope;
    final videos = await (scope == null
        ? fetch()
        : ProfileRuntime.withCapturedScope(scope, fetch));
    if (!isCurrent || videos == null) return null;
    return _Guide(this, videos);
  }
}

class _Guide implements SourceSeasonGuide {
  final StremioSourceSeasonsRepository repository;
  final List<Map<String, dynamic>> videos;
  @override
  final List<int> seasons;

  _Guide(this.repository, List<Map<String, dynamic>> videos)
    : videos = List.unmodifiable(
        videos.map((video) => Map<String, dynamic>.unmodifiable(video)),
      ),
      seasons = List.unmodifiable(
        (<int>{
          for (final video in videos)
            if (video['season'] != null && (video['season'] as num).toInt() > 0)
              (video['season'] as num).toInt(),
        }.toList()..sort()),
      );

  @override
  Future<void> record() {
    if (!repository.isCurrent) return Future.value();
    final session = repository.session;
    Future<void> write() =>
        LocalSeriesCompletionService.instance.recordRawEpisodeInventory(
          imdbId: session.selection.imdbId,
          seriesTitle: session.selection.title,
          videos: videos,
          canCommit: () => repository.isCurrent,
        );
    final scope = session.owner.scope;
    return scope == null
        ? write()
        : ProfileRuntime.withCapturedScope(scope, write);
  }
}
