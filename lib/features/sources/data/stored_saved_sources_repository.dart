import '../../../models/torrent.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/resolved_playback_link_cache.dart';
import '../../../services/series_source_service.dart';
import '../../../services/stremio_service.dart';
import '../models/saved_sources_state.dart';
import '../models/sources_session.dart';
import 'saved_sources_repository.dart';

class StoredSavedSourcesRepository implements SavedSourcesRepository {
  const StoredSavedSourcesRepository(this.session);
  final SourcesSession session;
  @override
  bool get isCurrent => session.owner == ProfileSessionMemory.captureOwner();

  @override
  Future<bool> remove(SeriesSource source) async {
    if (!isCurrent) return false;
    try {
      await ProfileRuntime.withoutCapturedScope(
        () => SeriesSourceService.removeSourceEntry(
          session.selection.imdbId,
          source,
          canContinue: () => isCurrent,
        ),
      );
      return isCurrent;
    } catch (_) {
      if (!isCurrent) return false;
      rethrow;
    }
  }

  @override
  Future<SavedSourcesState> load() async {
    if (!isCurrent) return SavedSourcesState();
    // Interactive migration must retain the preferences facade's live-profile
    // checks. A captured zone would mask profile changes at its write edge.
    return ProfileRuntime.withoutCapturedScope(() async {
      if (!isCurrent) return SavedSourcesState();
      final selection = session.selection;
      final all = selection.imdbId.isEmpty
          ? <SeriesSource>[]
          : await SeriesSourceService.getSources(
              selection.imdbId,
              canContinue: () => isCurrent,
            );
      if (!isCurrent) return SavedSourcesState();
      final bound = all
          .where(
            (source) => source.matchesCatalogScope(
              catalogId: selection.hasStremioEpisodeIdentity
                  ? selection.stremioCatalogId
                  : null,
              catalogKey: selection.hasStremioEpisodeIdentity
                  ? selection.stremioAddonKey
                  : null,
            ),
          )
          .toList();
      Torrent? cached;
      var cacheUnavailable = false;
      if (selection.isSeries &&
          selection.season != null &&
          selection.episode != null &&
          bound.isNotEmpty &&
          bound.first.isAddonDirect) {
        final pin = bound.first;
        try {
          final addons = await StremioService.instance.getAddons();
          if (!isCurrent) return SavedSourcesState();
          if (addons.any(
            (addon) =>
                addon.enabled &&
                addon.supportsStreams &&
                addon.sourceBindingKey == pin.addonKey,
          )) {
            cached = await ResolvedPlaybackLinkCache.get(
              id: selection.imdbId,
              type: session.contentType ?? 'series',
              season: selection.season,
              episode: selection.episode,
              pin: pin,
            );
          }
        } catch (_) {
          cacheUnavailable = true;
        }
      }
      if (!isCurrent) return SavedSourcesState();
      return SavedSourcesState(
        sources: bound,
        cachedEpisode: cached,
        cacheUnavailable: cacheUnavailable,
      );
    });
  }
}
