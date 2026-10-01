import 'package:debrify/services/storage/quick_play_storage.dart';
import '../../../models/playback_meta.dart';
import '../../../models/torrent.dart';
import '../../../services/durable_source_binding.dart';
import '../../../services/iptv_source_search.dart';
import '../../../services/media_server_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/resolved_playback_link_cache.dart';
import '../../../services/series_source_service.dart';
import '../../../services/source_selection_diagnostics.dart';
import 'source_single_episode.dart';

/// Durable automatic-binding policy for the profile that initiated playback.
/// Callers run the serialized operation in [runOwned] and retain their action guard.
class AutomaticSourceBindings {
  AutomaticSourceBindings.capture()
    : owner = ProfileSessionMemory.captureOwner();

  AutomaticSourceBindings(this.owner);

  static String storedProviderKey(String provider) =>
      provider == 'debrid' ? 'rd' : provider;

  final ProfileSessionOwner owner;
  bool get isCurrent => owner == ProfileSessionMemory.captureOwner();

  Future<void> runOwned(
    bool Function() canContinue,
    Future<void> Function() action,
  ) {
    if (!isCurrent || !canContinue()) return Future<void>.value();
    final scope = owner.scope;
    return scope == null
        ? ProfileRuntime.withoutCapturedScope(action)
        : ProfileRuntime.withCapturedScope(scope, action);
  }

  /// Remove an invalid saved source only while its playback action still owns it.
  Future<void> removeInvalid(
    String id,
    SeriesSource source, {
    required bool Function() canContinue,
  }) => runOwned(
    canContinue,
    () => SeriesSourceService.removeSourceEntry(
      id,
      source,
      canContinue: () => isCurrent && canContinue(),
    ),
  );

  Future<void> removeCachedLink({
    required String id,
    required String type,
    int? season,
    int? episode,
    required SeriesSource pin,
    required bool Function() canContinue,
  }) => runOwned(
    canContinue,
    () => ResolvedPlaybackLinkCache.remove(
      id: id,
      type: type,
      season: season,
      episode: episode,
      pin: pin,
      canContinue: () => isCurrent && canContinue(),
    ),
  );

  /// Old-screen parity: playing a catalog MOVIE remembers the just-played
  /// validated source as that title's single bound source (override), so the
  /// catalog flips "Select Source" → "Edit Source" and the next play reuses
  /// it.
  /// Series use the accumulating path below; keyword play (meta == null) and
  /// non-IMDb / on-device plays don't bind either. Best-effort — a storage
  /// hiccup must never break playback.
  Future<void> bindMovie(
    PlaybackMeta? meta,
    Torrent? winner,
    String provider, {
    required bool Function() canContinue,
  }) async {
    if (!canContinue()) return;
    if (meta == null ||
        meta.contentType != 'movie' ||
        meta.imdbId == null ||
        meta.imdbId!.isEmpty ||
        winner == null) {
      return;
    }
    final source = describe(winner, provider);
    if (source == null) return;
    final isIptv = IptvSourceSearch.owns(winner);
    try {
      await SeriesSourceService.setSources(meta.imdbId!, [
        source,
      ], canContinue: canContinue);
      if (isIptv && canContinue()) {
        logIptvSourceEvent(
          'automatic_pin_completed',
          source: winner,
          outcome: 'saved',
        );
      }
    } catch (error) {
      if (isIptv && canContinue()) {
        logIptvSourceEvent(
          'automatic_pin_completed',
          source: winner,
          outcome: 'storage_failed',
          error: error,
        );
      }
    }
  }

  /// Series counterpart of [bindMovie] (on by default via the
  /// series auto-pin setting): pin whatever source a series play resolved to
  /// — a pack from the pack-first search or a single episode from the fallback
  /// — so subsequent plays go straight through the bound path. A replayed
  /// binding is refreshed and promoted to primary; a new single-episode
  /// binding is capped so a pack-less show binged over time can't grow the
  /// list without bound (older singles are evicted; packs are never touched).
  /// Refreshable addon-direct sources participate without persisting their
  /// signed/temporary URL, and count toward that cap like any other single —
  /// exempting them left the list unbounded. A manually pinned SINGLE is
  /// therefore evictable once 20 accumulate for one series; there is no stored
  /// manual/auto flag to tell them apart, and an unbounded list is the worse
  /// failure. Local sources stay opt-in.
  ///
  /// Gated on [StorageService.getSeriesAutoPinOnPlay] — which is NOT the
  /// "Prefer season packs" toggle. The two shared a preference key until it was
  /// split; turning packs off used to disable pinning here, which left Smart
  /// mode permanently unable to find a pin.
  static const int _maxAutoBoundSingles = 20;

  Future<void> bindSeries(
    PlaybackMeta? meta,
    Torrent? winner,
    String provider, {
    required bool Function() canContinue,
  }) async {
    if (!canContinue()) return;
    // Any non-movie episode play (contentType 'series' or a custom series-like
    // type such as anime) — movies are handled by bindMovie.
    // Scoped to episode plays (season+episode set) to match the pack-first
    // gate and skip whole-series/no-episode plays.
    if (meta == null ||
        meta.contentType == 'movie' ||
        (meta.imdbId ?? meta.stremioCatalogId)?.isEmpty != false ||
        meta.season == null ||
        meta.episode == null ||
        winner == null ||
        // Consistent with the pack-first block: the whole auto-pin feature is
        // off for PikPak (its bindings re-queue real downloads on each replay),
        // so a stale-true pref after switching default to PikPak stays inert.
        (winner.streamType == StreamType.torrent && provider == 'pikpak')) {
      return;
    }
    final source = describe(
      winner,
      provider,
      addonCatalogId: meta.stremioCatalogId,
      addonCatalogKey: meta.stremioAddonKey,
    );
    if (source == null) return;
    final isIptv = IptvSourceSearch.owns(winner);
    try {
      final enabled = await QuickPlayStorage.getSeriesAutoPinOnPlay();
      if (!canContinue()) return;
      if (!enabled) {
        if (isIptv && canContinue()) {
          logIptvSourceEvent(
            'automatic_pin_completed',
            source: winner,
            outcome: 'disabled',
            season: meta.season,
            episode: meta.episode,
          );
        }
        return;
      }
      final imdbId = meta.imdbId ?? meta.stremioCatalogId!;
      final list = List<SeriesSource>.from(
        await SeriesSourceService.getSources(imdbId, canContinue: canContinue),
      );
      final existingIdx = list.indexWhere(
        (s) =>
            s.bindingKey == source.bindingKey ||
            (s.isAddonDirect &&
                source.isAddonDirect &&
                s.addonCatalogId == source.addonCatalogId &&
                s.addonCatalogKey == source.addonCatalogKey &&
                s.addonKey == source.addonKey &&
                s.streamKey == source.streamKey),
      );
      if (existingIdx >= 0) {
        // The source that actually rendered becomes primary, while every
        // other series fallback remains available.
        list.removeAt(existingIdx);
      } else {
        // A NEW single-episode binding: bound how many auto-accumulate so a
        // pack-less show doesn't grow the list forever. Packs and anything else
        // that isn't a single episode are never evicted.
        //
        // Addon-direct singles count here too. Exempting them left the list
        // unbounded, and an unstable identity (see SeriesSource.bindingKey)
        // appended a fresh one on every play. The identity is fixed now; this
        // cap is the backstop for whatever destabilises it next. The cost is
        // that a manually pinned single is evictable once 20 accumulate —
        // there is no stored manual/auto flag to separate them.
        if (singleSourceEpisode(source.torrentName) != null) {
          final singles =
              list
                  .where(
                    (s) =>
                        s.addonCatalogId == source.addonCatalogId &&
                        s.addonCatalogKey == source.addonCatalogKey &&
                        singleSourceEpisode(s.torrentName) != null,
                  )
                  .toList()
                ..sort((a, b) => a.boundAt.compareTo(b.boundAt));
          final overflow = singles.length + 1 - _maxAutoBoundSingles;
          if (overflow > 0) {
            final drop = singles
                .take(overflow)
                .map((s) => s.bindingKey)
                .toSet();
            list.removeWhere((s) => drop.contains(s.bindingKey));
          }
        }
      }
      list.insert(0, source);
      await SeriesSourceService.setSources(
        imdbId,
        list,
        canContinue: canContinue,
      );
      if (isIptv && canContinue()) {
        logIptvSourceEvent(
          'automatic_pin_completed',
          source: winner,
          outcome: 'saved',
          season: meta.season,
          episode: meta.episode,
        );
      }
    } catch (error) {
      if (isIptv && canContinue()) {
        logIptvSourceEvent(
          'automatic_pin_completed',
          source: winner,
          outcome: 'storage_failed',
          season: meta.season,
          episode: meta.episode,
          error: error,
        );
      }
    }
  }

  /// Converts an eligible playback source into its durable binding. Automatic
  /// callers invoke this only after decoder validation. Direct streams keep
  /// only opaque addon provenance so the next play re-queries a fresh URL;
  /// arbitrary/external links and local rows cannot be auto-bound.
  static SeriesSource? describe(
    Torrent source,
    String provider, {
    String? addonCatalogId,
    String? addonCatalogKey,
  }) => durableSourceBinding(
    source,
    provider,
    now: DateTime.now().millisecondsSinceEpoch,
    isMediaServer: MediaServerService.owns,
    mediaServerBinding: MediaServerService.bindingFor,
    isIptv: IptvSourceSearch.owns,
    storedProviderKey: storedProviderKey,
    addonCatalogId: addonCatalogId,
    addonCatalogKey: addonCatalogKey,
  );

  Future<void> cacheDirect(
    PlaybackMeta? meta,
    Torrent source, {
    required bool Function() canContinue,
  }) async {
    if (!canContinue()) return;
    if (meta?.hasStremioEpisodeIdentity == true) return;
    if (meta?.imdbId == null || source.streamType != StreamType.directUrl) {
      return;
    }
    // The player can advance while its launch callback retains old metadata.
    // Use the addon's actual request identity, never a filename guess.
    final parts = source.stremioVideoId?.split(':');
    final isMovie = meta!.contentType == 'movie';
    if (parts == null || parts.first != meta.imdbId) return;
    final season = !isMovie && parts.length == 3
        ? int.tryParse(parts[1])
        : null;
    final episode = !isMovie && parts.length == 3
        ? int.tryParse(parts[2])
        : null;
    if (!isMovie && (season == null || episode == null)) return;
    try {
      await ResolvedPlaybackLinkCache.save(
        id: meta.imdbId!,
        type: meta.contentType ?? 'series',
        season: season,
        episode: episode,
        source: source,
        canContinue: canContinue,
      );
    } catch (_) {
      // Optional cache persistence must never prevent a durable pin commit.
    }
  }

  /// Keep a title's pinned source in sync when the user switches sources in
  /// the player. A validated switch can update or create the binding; local and
  /// non-refreshable sources are skipped.
  ///
  /// A movie has a single bound source, so it's a straight replace (matching
  /// [bindMovie]). A series keeps ALL other fallbacks and promotes
  /// the chosen source to primary; switching never replaces a series pin.
  /// PikPak torrents are excluded for series
  /// (matching the series auto-pin feature) but allowed for movies (matching
  /// [bindMovie]).
  Future<void> switchSource(
    PlaybackMeta? meta,
    Torrent switched,
    String provider, {
    required bool Function() canContinue,
  }) async {
    if (!canContinue()) return;
    if (meta == null ||
        (meta.imdbId ?? meta.stremioCatalogId)?.isEmpty != false ||
        switched.streamType == StreamType.externalUrl) {
      return;
    }
    final isMovie = meta.contentType == 'movie';
    // A series needs a concrete episode, and its auto-pin feature is off for
    // PikPak; movies have neither constraint.
    if (!isMovie &&
        (meta.season == null ||
            meta.episode == null ||
            (switched.streamType == StreamType.torrent &&
                provider == 'pikpak'))) {
      return;
    }
    final source = describe(
      switched,
      provider,
      addonCatalogId: meta.stremioCatalogId,
      addonCatalogKey: meta.stremioAddonKey,
    );
    if (source == null) return;
    final isIptv = IptvSourceSearch.owns(switched);
    try {
      final imdbId = meta.imdbId ?? meta.stremioCatalogId!;
      final existing = await SeriesSourceService.getSources(
        imdbId,
        canContinue: canContinue,
      );
      if (isMovie) {
        // Single bound source — replace it with the chosen one.
        await SeriesSourceService.setSources(imdbId, [
          source,
        ], canContinue: canContinue);
        if (isIptv && canContinue()) {
          logIptvSourceEvent(
            'source_switch_pin_completed',
            source: switched,
            outcome: 'saved',
          );
        }
        return;
      }
      // A switch after an unpersistable initial row can be the first bind. The
      // existing series auto-pin preference still owns that opt-in boundary;
      // once a list exists, a successful switch keeps it in sync regardless.
      final enabled =
          existing.isNotEmpty ||
          await QuickPlayStorage.getSeriesAutoPinOnPlay();
      if (!canContinue()) return;
      if (!enabled) {
        if (isIptv && canContinue()) {
          logIptvSourceEvent(
            'source_switch_pin_completed',
            source: switched,
            outcome: 'disabled',
            season: meta.season,
            episode: meta.episode,
          );
        }
        return;
      }
      // Series: promote the winner but retain the previous primary and every
      // other fallback. Re-selecting an existing entry just moves/refreshes it.
      final list = List<SeriesSource>.from(existing)
        ..removeWhere(
          (s) =>
              s.bindingKey == source.bindingKey ||
              (s.isAddonDirect &&
                  source.isAddonDirect &&
                  s.addonCatalogId == source.addonCatalogId &&
                  s.addonCatalogKey == source.addonCatalogKey &&
                  s.addonKey == source.addonKey &&
                  s.streamKey == source.streamKey),
        );
      list.insert(0, source);
      await SeriesSourceService.setSources(
        imdbId,
        list,
        canContinue: canContinue,
      );
      if (isIptv && canContinue()) {
        logIptvSourceEvent(
          'source_switch_pin_completed',
          source: switched,
          outcome: 'saved',
          season: meta.season,
          episode: meta.episode,
        );
      }
    } catch (error) {
      if (isIptv && canContinue()) {
        logIptvSourceEvent(
          'source_switch_pin_completed',
          source: switched,
          outcome: 'storage_failed',
          season: meta.season,
          episode: meta.episode,
          error: error,
        );
      }
    }
  }
}
