import 'custom_series_identity.dart';
import 'play_loader_art.dart';
import 'playback_resume_policy.dart';
import 'stremio_addon.dart';

/// Content identity for a playback, so the player can record Continue Watching,
/// fetch subtitles, and drive the Episodes button (matching Home).
class PlaybackMeta {
  final bool initialContinuousShuffle;
  final String? imdbId;
  final String? contentType; // 'movie' | 'series'
  final int? season;
  final int? episode;
  final String? title; // clean display title
  final String? posterUrl;
  final String? year;
  final String? addonId; // originating Stremio addon (resume / next-episode)
  final StremioMeta?
  catalogItem; // Exact catalog ID and addon configuration for navigation.
  final String? stremioAddonId;
  final String? stremioAddonKey;
  final String? stremioCatalogId;
  final String? stremioVideoId;
  final double? traktProgressPercent; // Trakt watch position, if known
  // Play came from a Trakt row → scrobble to Trakt instead of saving a local
  // Continue Watching entry (mirrors Home passing selection.traktSource).
  final bool traktScrobble;
  // Simkl parallel pair (see the Simkl integration plan).
  final double? simklProgressPercent;
  final bool simklScrobble;
  final double? mdblistProgressPercent;
  final bool mdblistScrobble;

  /// Catalog launches have authoritative content identity, so their local
  /// resume position follows IMDb (plus S/E for episodes) across sources.
  /// Generic keyword/debrid playback leaves this source-specific.
  final PlaybackResumePolicy resumePolicy;

  /// Presentation-only artwork + meta line for the play loader (Marquee).
  /// Null on every path that doesn't have it — the loader falls back to the
  /// poster, exactly as it did before this existed.
  final PlayLoaderArt? art;
  const PlaybackMeta({
    this.initialContinuousShuffle = false,
    this.imdbId,
    this.contentType,
    this.season,
    this.episode,
    this.title,
    this.posterUrl,
    this.year,
    this.addonId,
    this.catalogItem,
    this.stremioAddonId,
    this.stremioAddonKey,
    this.stremioCatalogId,
    this.stremioVideoId,
    this.traktProgressPercent,
    this.traktScrobble = false,
    this.simklProgressPercent,
    this.simklScrobble = false,
    this.mdblistProgressPercent,
    this.mdblistScrobble = false,
    this.resumePolicy = PlaybackResumePolicy.sourceSpecific,
    this.art,
  });

  const PlaybackMeta.catalog({
    this.initialContinuousShuffle = false,
    this.imdbId,
    this.contentType,
    this.season,
    this.episode,
    this.title,
    this.posterUrl,
    this.year,
    this.addonId,
    this.catalogItem,
    this.stremioAddonId,
    this.stremioAddonKey,
    this.stremioCatalogId,
    this.stremioVideoId,
    this.traktProgressPercent,
    this.traktScrobble = false,
    this.simklProgressPercent,
    this.simklScrobble = false,
    this.mdblistProgressPercent,
    this.mdblistScrobble = false,
    this.art,
  }) : resumePolicy = PlaybackResumePolicy.catalogCanonical;

  bool get hasStremioEpisodeIdentity =>
      stremioAddonKey?.trim().isNotEmpty == true &&
      stremioCatalogId?.trim().isNotEmpty == true;

  String? get progressIdentity => CustomSeriesIdentity.isCustom(imdbId)
      ? imdbId
      : hasStremioEpisodeIdentity
      ? CustomSeriesIdentity(stremioAddonKey!, stremioCatalogId!).id
      : imdbId;
}
