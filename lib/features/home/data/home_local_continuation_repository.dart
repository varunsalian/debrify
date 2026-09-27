import '../../../models/stremio_addon.dart';
import '../../../models/custom_series_identity.dart';
import '../../../models/media_identity.dart';
import '../../../models/tracking_source.dart';
import '../../../utils/continue_watching_presentation.dart';
import '../models/home_local_continuation.dart';

/// Reads local continuation data in recency order. No writes, cache or retries.
/// Raw persisted maps are confined to this adapter; callers receive typed data.
class HomeLocalContinuationRepository {
  const HomeLocalContinuationRepository({
    required this.readProgressSource,
    required this.readEnabled,
    required Future<List<Map<String, dynamic>>> Function() readItems,
    required Future<List<StremioAddon>> Function() readAddons,
    required Future<Map<String, dynamic>?> Function(String) readEpisode,
    required Future<Map<String, dynamic>?> Function(String) readMovie,
  }) : _readItems = readItems,
       _readAddons = readAddons,
       _readEpisode = readEpisode,
       _readMovie = readMovie;

  final Future<WatchProgressSource> Function() readProgressSource;
  final Future<bool> Function() readEnabled;
  final Future<List<Map<String, dynamic>>> Function() _readItems;
  final Future<List<StremioAddon>> Function() _readAddons;
  final Future<Map<String, dynamic>?> Function(String) _readEpisode;
  final Future<Map<String, dynamic>?> Function(String) _readMovie;

  /// Null means retirement. Check between reads so an outgoing operation does
  /// not resolve later records through a newly active profile's implicit store.
  Future<HomeLocalContinuation?> load({
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return null;
    final raw = await _readItems();
    if (!isCurrent()) return null;
    final configuredAddons =
        raw.any((m) => CustomSeriesIdentity.isCustom(m['imdbId'] as String?))
        ? await _readAddons()
        : const <StremioAddon>[];
    if (!isCurrent()) return null;
    final items = <StremioMeta>[];
    final progress = <String, double>{};
    final episode = <String, String>{};
    final remainingMinutes = <String, int>{};
    final episodeRefs = <String, ({int season, int episode})>{};
    final ids = <String>{};
    final addonIds = <String, String?>{};
    for (final m in raw) {
      if (!isCurrent()) return null;
      final imdbId = m['imdbId'] as String?;
      if (imdbId == null || imdbId.isEmpty) continue;
      final type = (m['contentType'] as String?) ?? 'movie';
      items.add(
        StremioMeta(
          id: CustomSeriesIdentity.parse(imdbId)?.catalogId ?? imdbId,
          imdbId: MediaIdentity.isNative(imdbId) ? null : imdbId,
          type: type,
          name: (m['title'] as String?) ?? 'Untitled',
          poster: m['posterUrl'] as String?,
          year: m['year'] as String?,
          sourceAddon: configuredAddons
              .where(
                (a) =>
                    a.portableConfigurationKey ==
                        CustomSeriesIdentity.parse(imdbId)?.addonKey ||
                    a.sourceBindingKey ==
                        CustomSeriesIdentity.parse(imdbId)?.addonKey,
              )
              .firstOrNull,
        ),
      );
      ids.add(imdbId);
      addonIds[imdbId] =
          CustomSeriesIdentity.parse(imdbId)?.addonKey ??
          m['addonId'] as String?;

      // Watched fraction — joined from the playback-state store, exactly like
      // HomeContinueWatchingSection (finished episodes count as 100%).
      double? pct;
      if (type == 'series') {
        final lastEp = await _readEpisode(imdbId);
        if (!isCurrent()) return null;
        if (lastEp != null) {
          final finished = lastEp['finished'] == true;
          final posMs = lastEp['positionMs'] as int? ?? 0;
          final durMs = lastEp['durationMs'] as int? ?? 1;
          if (durMs > 0) {
            pct = finished ? 100.0 : (posMs / durMs * 100).clamp(0.0, 100.0);
          }
          final se = continueWatchingEpisodeLabel(
            lastEp['season'] as int?,
            lastEp['episode'] as int?,
          );
          if (se != null) episode[imdbId] = se;
          final season = lastEp['season'] as int?;
          final episodeNumber = lastEp['episode'] as int?;
          if (season != null &&
              episodeNumber != null &&
              season > 0 &&
              episodeNumber > 0) {
            episodeRefs[imdbId] = (season: season, episode: episodeNumber);
          }
          final left = continueWatchingMinutesLeft(
            positionMs: posMs,
            durationMs: durMs,
          );
          if (left != null) remainingMinutes[imdbId] = left;
        }
      } else {
        final state = await _readMovie(imdbId);
        if (!isCurrent()) return null;
        if (state != null) {
          final posMs = state['positionMs'] as int? ?? 0;
          final durMs = state['durationMs'] as int? ?? 1;
          if (durMs > 0) pct = (posMs / durMs * 100).clamp(0.0, 100.0);
          final left = continueWatchingMinutesLeft(
            positionMs: posMs,
            durationMs: durMs,
          );
          if (left != null) remainingMinutes[imdbId] = left;
        }
      }
      if (pct != null) progress[imdbId] = pct / 100.0;
    }

    return HomeLocalContinuation(
      items: items,
      ids: ids,
      progress: progress,
      episode: episode,
      remainingMinutes: remainingMinutes,
      episodeRefs: episodeRefs,
      addonIds: addonIds,
    );
  }
}
