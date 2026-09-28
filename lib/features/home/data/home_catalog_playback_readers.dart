import '../../../models/stremio_addon.dart';
import '../../../services/native_series_metadata_service.dart';
import '../../../services/next_episode_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/simkl/simkl_service.dart';
import '../../../services/storage_service.dart';
import '../../../services/stremio_service.dart';

/// Remaining legacy reads for catalog playback. Every call retains its origin.
class HomeCatalogPlaybackReaders {
  const HomeCatalogPlaybackReaders(this.owner);
  final ProfileSessionOwner owner;

  Future<T?> _read<T>(
    Future<T?> Function() operation,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent() || owner != ProfileSessionMemory.captureOwner()) {
      return null;
    }
    final scope = owner.scope;
    final value = scope == null
        ? await operation()
        : await ProfileRuntime.withCapturedScope(scope, operation);
    return isCurrent() && owner == ProfileSessionMemory.captureOwner()
        ? value
        : null;
  }

  Future<Map<String, dynamic>?> localById(
    String id, {
    required bool Function() isCurrent,
  }) => _read(() => StorageService.getLastPlayedEpisodeByImdbId(id), isCurrent);
  Future<Map<String, dynamic>?> localByTitle(
    String title, {
    required bool Function() isCurrent,
  }) => _read(
    () => StorageService.getLastPlayedEpisode(seriesTitle: title),
    isCurrent,
  );

  Future<void> prepareMovieRewatch(
    StremioMeta item,
    String id, {
    required bool Function() isCurrent,
  }) async {
    final status = await _read(
      () => SimklService.instance
          .fetchTitleStatus(id, contentType: item.type)
          .timeout(const Duration(seconds: 4), onTimeout: () => null),
      isCurrent,
    );
    if (status?.currentStatus != 'completed') return;
    await _read(
      () => SimklService.instance
          .markUnwatched(id, 'movie')
          .timeout(const Duration(seconds: 4), onTimeout: () => false),
      isCurrent,
    );
  }

  Future<({int season, int episode})?> nextEpisode(
    StremioMeta item,
    StremioAddon addon,
    String playId,
    int season,
    int episode, {
    required bool Function() isCurrent,
  }) async {
    final videoId = await _read(
      () => StremioService.instance.episodeVideoIdForLaunch(
        addon: addon,
        imdbId: playId,
        catalogId: item.id,
        season: season,
        episode: episode,
      ),
      isCurrent,
    );
    if (!isCurrent()) return null;
    final custom = videoId != null && videoId.isNotEmpty
        ? !StremioService.isCanonicalEpisodeId(playId, videoId, season, episode)
        : !StremioService.isCanonicalCatalogAlias(item.id, playId);
    if (playId.startsWith('tt') && !custom) {
      return _read(
        () => NextEpisodeService.findNextEpisode(
          playId,
          season,
          episode,
          preferBuiltIn: addon.id == NativeSeriesMetadataService.addon.id,
          catalogItem: item.withSourceAddon(addon),
        ),
        isCurrent,
      );
    }
    final next = await _read(
      () => StremioService.instance.resolveAdjacentSeriesEpisode(
        addonKey: addon.sourceBindingKey,
        addonId: addon.id,
        catalogId: item.id,
        season: season,
        episode: episode,
        direction: 1,
      ),
      isCurrent,
    );
    return next == null ? null : (season: next.season, episode: next.episode);
  }
}
