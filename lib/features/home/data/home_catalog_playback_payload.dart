import '../../../models/advanced_search_selection.dart';
import '../../../models/custom_series_identity.dart';
import '../../../models/media_identity.dart';
import '../../../models/play_loader_art.dart';
import '../../../models/playback_meta.dart';
import '../../../models/stremio_addon.dart';

/// Movie/channel selection shared by catalog Play and manual Sources.
AdvancedSearchSelection homeCatalogMovieSelection(
  StremioMeta item, {
  bool isTraktSource = false,
  bool isMdblistSource = false,
  // Cross-device resume percents for a movie (0-100), when a tracker has a
  // paused position. Null = no tracker position → the player resumes from
  // the local byte offset as before.
  double? traktProgressPercent,
  double? simklProgressPercent,
  double? mdblistProgressPercent,
}) => AdvancedSearchSelection(
  // Prefer the resolved progress identity, including typed native movie IDs.
  // Otherwise retain the raw catalog ID for IPTV/TV and kitsu-only titles,
  // so playback/Sources can resolve the addon's own /stream endpoint.
  // The torrent engines cannot resolve arbitrary catalog IDs, but addon
  // streams can. Metadata may omit an unsupported tracking ID below; the
  // selection still needs this exact identity to find the playable stream.
  imdbId: item.progressId ?? item.id,
  isSeries: false,
  title: item.name,
  year: item.year,
  contentType: item.type,
  posterUrl: item.poster,
  // Trakt-sourced movies scrobble to Trakt like the old home view; catalog
  // movies leave this false so scrobble follows the Tracking master
  // setting.
  traktSource: isTraktSource,
  traktProgressPercent: traktProgressPercent,
  simklProgressPercent: simklProgressPercent,
  mdblistSource: isMdblistSource,
  mdblistProgressPercent: mdblistProgressPercent,
);

/// Catalog identity and resume policy forwarded to the existing player bridge.
PlaybackMeta homeCatalogPlaybackMeta(
  AdvancedSearchSelection sel, {
  required String? fallbackAddonId,
  String? addonId,
  StremioMeta? catalogItem,
  PlayLoaderArt? art,
}) => PlaybackMeta.catalog(
  initialContinuousShuffle: sel.initialContinuousShuffle,
  // Preserve native tracking identity; TrackingSourcePolicy filters out
  // destinations that only accept IMDb. Arbitrary channel IDs stay untracked.
  imdbId:
      sel.imdbId.startsWith('tt') ||
          MediaIdentity.isNative(sel.imdbId) ||
          CustomSeriesIdentity.isCustom(sel.imdbId)
      ? sel.imdbId
      : null,
  contentType: sel.contentType ?? (sel.isSeries ? 'series' : 'movie'),
  season: sel.season,
  episode: sel.episode,
  title: sel.title,
  posterUrl: sel.posterUrl,
  year: sel.year,
  addonId: catalogItem?.sourceAddon?.id ?? addonId ?? fallbackAddonId,
  catalogItem: catalogItem,
  stremioAddonId: sel.stremioAddonId,
  stremioAddonKey: sel.stremioAddonKey,
  stremioCatalogId: sel.stremioCatalogId,
  stremioVideoId: sel.stremioVideoId,
  traktProgressPercent: sel.traktProgressPercent,
  // Trakt-row plays scrobble to Trakt instead of saving a duplicate local
  // Continue Watching entry (mirrors Home passing selection.traktSource).
  traktScrobble: sel.traktSource,
  simklProgressPercent: sel.simklProgressPercent,
  simklScrobble: sel.simklSource,
  mdblistProgressPercent: sel.mdblistProgressPercent,
  mdblistScrobble: sel.mdblistSource,
  art: art,
);
