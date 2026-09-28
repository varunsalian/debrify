import '../../../models/advanced_search_selection.dart';
import '../../../models/custom_series_identity.dart';
import '../../../models/media_identity.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/trakt_continue_watching_item.dart';
import '../../../services/native_series_metadata_service.dart';
import '../../../services/tracking_source_policy.dart';
import '../models/home_series_resume_signals.dart';
import 'home_catalog_playback_payload.dart';
import 'home_catalog_playback_readers.dart';
import 'home_series_resume_repository.dart';
import 'home_series_resume_resolver.dart';
import 'home_tracker_resume_repository.dart';

class HomeCatalogPlaybackTarget {
  const HomeCatalogPlaybackTarget.play(this.selection) : openEpisodes = false;
  const HomeCatalogPlaybackTarget.episodes()
    : selection = null,
      openEpisodes = true;
  final AdvancedSearchSelection? selection;
  final bool openEpisodes;
}

/// Catalog target selection; presentation retains loader, routes and player handoff.
class HomeCatalogPlaybackResolver {
  const HomeCatalogPlaybackResolver({
    required this.seriesResume,
    required this.signals,
    required this.trackers,
    required this.readers,
    required this.log,
  });
  final HomeSeriesResumeResolver seriesResume;
  final HomeSeriesResumeRepository signals;
  final HomeTrackerResumeRepository trackers;
  final HomeCatalogPlaybackReaders readers;
  final void Function(String) log;

  /// Resume-label policy shares Play's series resolver and tracker memo.
  /// Movie reads remain sequential, stopping at the first usable position.
  Future<HomeResumePosition> label(
    StremioMeta item,
    StremioAddon addon, {
    required TrackingSourcePolicy trackingPolicy,
    required HomeResumeAvailability Function() availability,
    required TraktContinueWatchingItem? Function() cachedTrakt,
    required bool Function() isCurrent,
    bool isTraktSource = false,
    bool isMdblistSource = false,
  }) async {
    if (!isCurrent()) return (started: false, season: null, episode: null);
    log(
      '[SeriesResume] label-resolve-start title="${item.name}" '
      'id=${item.progressId ?? item.id} type=${item.type} '
      'traktSource=$isTraktSource mdblistSource=$isMdblistSource',
    );
    if (isMdblistSource &&
        trackingPolicy.progressFrom(TrackingSource.mdblist)) {
      final owned = await trackers.mdblistItem(
        item.progressId ?? item.id,
        isCurrent: isCurrent,
      );
      if (!isCurrent()) return (started: false, season: null, episode: null);
      if (owned != null) {
        return (
          started: true,
          season: owned.selection.season,
          episode: owned.selection.episode,
        );
      }
    }
    // Series: the ONE reconciled answer — recency across trackers + local,
    // watched-advance, briefly cached — shared verbatim with _onCatalogPlay
    // so the label and playback can never disagree (see
    // the shared series resolver for the full rules).
    if (item.type == 'series') {
      final r = await seriesResume.resolve(
        item,
        isTraktSource: isTraktSource,
        availability: availability,
        cachedTrakt: cachedTrakt,
        isCurrent: isCurrent,
        preferBuiltIn: addon.id == NativeSeriesMetadataService.addon.id,
        catalogItem: item.withSourceAddon(addon),
      );
      if (!isCurrent() || r == null) {
        return (started: false, season: null, episode: null);
      }
      log(
        '[SeriesResume] label-resolve-result title="${item.name}" '
        'started=${r.started} target=S${r.season}E${r.episode} '
        'source=${HomeSeriesResumeResolver.sourceName(r.sourcePrio)}',
      );
      return (started: r.started, season: r.season, episode: r.episode);
    }

    // Trakt-sourced MOVIE: the cached CW selection carries Trakt's position —
    // same fast path the old Trakt-first arm gave movies (a non-Trakt-sourced
    // movie deliberately stays local-first; Play resumes it from the local
    // byte offset, so a tracker-first label would over-promise).
    if (isTraktSource && trackingPolicy.progressFrom(TrackingSource.trakt)) {
      final resume = await signals.traktPosition(
        item,
        cached: cachedTrakt(),
        isCurrent: isCurrent,
      );
      if (!isCurrent()) return (started: false, season: null, episode: null);
      if (resume != null) return resume;
    }

    // Movie (series returned above): "started" if a local position OR a
    // cross-device tracker position exists — so the button reads "Resume" for
    // a movie paused on another device, matching what Play now seeks to (kept
    // in lock-step with the movie branch of _onCatalogPlay).
    final playId = item.imdbId ?? item.progressId ?? item.id;
    final st = trackingPolicy.progressFrom(TrackingSource.local)
        ? await readers.movieStarted(playId, isCurrent: isCurrent)
        : null;
    if (!isCurrent()) return (started: false, season: null, episode: null);
    var started = st == true;
    if (!started &&
        trackingPolicy.progressFrom(TrackingSource.trakt) &&
        (availability().trakt || isTraktSource)) {
      started =
          (await trackers.traktMovie(
            item.progressId ?? item.id,
            isCurrent: isCurrent,
          )) !=
          null;
      if (!isCurrent()) return (started: false, season: null, episode: null);
    }
    if (!started &&
        trackingPolicy.progressFrom(TrackingSource.simkl) &&
        availability().simkl) {
      started =
          (await trackers.simklMovie(
            item.progressId ?? item.id,
            isCurrent: isCurrent,
          )) !=
          null;
      if (!isCurrent()) return (started: false, season: null, episode: null);
    }
    if (!started &&
        trackingPolicy.progressFrom(TrackingSource.mdblist) &&
        availability().mdblist) {
      started =
          (await trackers.mdblistMovie(
            item.progressId ?? item.id,
            isCurrent: isCurrent,
          )) !=
          null;
      if (!isCurrent()) return (started: false, season: null, episode: null);
    }
    return (started: started, season: null, episode: null);
  }

  Future<HomeCatalogPlaybackTarget?> resolve(
    StremioMeta item,
    StremioAddon addon, {
    required TrackingSourcePolicy trackingPolicy,
    required HomeResumeAvailability Function() availability,
    required TraktContinueWatchingItem? Function() cachedTrakt,
    required bool Function() isCurrent,
    bool isTraktSource = false,
    bool isMdblistSource = false,
    bool startFromBeginning = false,
    bool skipEpisodeFallback = false,
    bool preferTraktResume = false,
    ({bool started, int season, int episode})? promisedTarget,
  }) async {
    if (!isCurrent()) return null;
    // Rewatch is not resume reconciliation: even a cached S1E1 selection
    // carries stale percentages. Never consult tracker/CW caches here.
    if (startFromBeginning) {
      return HomeCatalogPlaybackTarget.play(
        AdvancedSearchSelection(
          imdbId: item.progressId ?? item.id,
          isSeries: item.type == 'series',
          title: item.name,
          year: item.year,
          season: item.type == 'series' ? 1 : null,
          episode: item.type == 'series' ? 1 : null,
          contentType: item.type,
          posterUrl: item.poster,
          traktSource: isTraktSource,
          mdblistSource: isMdblistSource,
          traktProgressPercent: 0,
          simklProgressPercent: 0,
          mdblistProgressPercent: 0,
        ),
      );
    }

    if (isMdblistSource &&
        trackingPolicy.progressFrom(TrackingSource.mdblist)) {
      final owned = await trackers.mdblistItem(
        item.progressId ?? item.id,
        isCurrent: isCurrent,
      );
      if (!isCurrent()) return null;
      if (owned != null) {
        // This fast path skips the reconciler entirely, so it needs its own
        // promise check — otherwise an in-page watched mutation moves the
        // label while MDBList still reports the previous continue-watching
        // coordinate, and Resume replays the episode the label moved past.
        final p = promisedTarget;
        final stale =
            p != null &&
            (owned.selection.season != p.season ||
                owned.selection.episode != p.episode);
        if (!stale) {
          return HomeCatalogPlaybackTarget.play(owned.selection);
        }
        log(
          '[SeriesResume] play-mdblist-fastpath-skipped title="${item.name}" '
          'owned=S${owned.selection.season}E${owned.selection.episode} '
          'promised=S${p.season}E${p.episode}',
        );
        // Fall through to the reconciled/promised path below.
      }
    }

    // Series on the detail Resume flow (or Trakt-sourced): the SAME
    // reconciled answer the label used (cached ~45s), so the pill and the
    // playback can never land on different episodes — recency across
    // trackers + local, watched-advance; see _reconcileSeriesResume.
    if (item.type == 'series' && (preferTraktResume || isTraktSource)) {
      final r = await seriesResume.resolve(
        item,
        isTraktSource: isTraktSource,
        preferBuiltIn: addon.id == NativeSeriesMetadataService.addon.id,
        catalogItem: item.withSourceAddon(addon),
        availability: availability,
        cachedTrakt: cachedTrakt,
        isCurrent: isCurrent,
      );
      if (!isCurrent() || r == null) return null;
      // The caller's button already promised an episode the reconciler can't
      // see. Honor it: the label is the promise the user acted on, and a
      // silent disagreement here replays an episode they already watched.
      final promised = promisedTarget;
      final overridden =
          promised != null &&
          (promised.season != r.season || promised.episode != r.episode);
      if (overridden) {
        log(
          '[SeriesResume] play-promise-override title="${item.name}" '
          'reconciled=S${r.season}E${r.episode}/started=${r.started} '
          'promised=S${promised.season}E${promised.episode}',
        );
      }
      // Winner's original selection (Trakt or MDBList) — launches with its
      // own progress percent intact. Unusable once overridden: it points at
      // the older coordinate, so it would re-open the episode we just moved
      // past, carrying that episode's resume percent with it.
      if (!overridden && r.selection != null) {
        return HomeCatalogPlaybackTarget.play(r.selection!);
      }
      final rTtId = item.imdbId ?? (item.id.startsWith('tt') ? item.id : '');
      final rTracker = (r.sourcePrio ?? 3) <= 2;
      // A promise IS started-evidence — it is what made the button read
      // "Resume". Without this, the empty-candidates fallback (started=false)
      // drops through to the S01E01 tail below. Keyed on the promise itself
      // rather than on [overridden]: when the promised coordinate happens to
      // MATCH the reconciler's fallback, there is no override, yet the button
      // still said "Resume" and must not fall through.
      final started = r.started || (promised?.started ?? false);
      if (started && (rTtId.isNotEmpty || skipEpisodeFallback || rTracker)) {
        return HomeCatalogPlaybackTarget.play(
          AdvancedSearchSelection(
            imdbId: rTtId.isNotEmpty ? rTtId : (item.progressId ?? item.id),
            isSeries: true,
            title: item.name,
            year: item.year,
            season: overridden ? promised.season : r.season,
            episode: overridden ? promised.episode : r.episode,
            contentType: item.type,
            posterUrl: item.poster,
            // Source flags from the WINNING provider (advanced or not) so
            // player scrobbling attribution follows the tracker that owned
            // the resume — not from how the page happened to be opened.
            traktSource: isTraktSource || r.sourcePrio == 0,
            // Belongs to the reconciled coordinate — carrying it onto a
            // different episode would seek the new one to a stale position.
            simklProgressPercent: overridden ? null : r.simklProgress,
            simklSource: r.sourcePrio == 1,
            // `isMdblistSource ||` mirrors the traktSource term above: when
            // the MDBList fast path is skipped as stale, the reconciler's
            // winner is usually the local candidate, and without this the
            // play would silently stop attributing to MDBList.
            mdblistSource: isMdblistSource || r.sourcePrio == 2,
          ),
        );
      }
      // Not started (or no usable id): fall through to the shared tail —
      // episode-picker fallback for id-less shows, default S01E01 otherwise.
    }

    // Trakt-sourced MOVIE keeps its cached-CW fast path (series resolve
    // through the reconciler above).
    if (item.type != 'series' &&
        isTraktSource &&
        trackingPolicy.progressFrom(TrackingSource.trakt)) {
      final cw = cachedTrakt();
      if (cw != null) {
        final signal = await signals.traktSelection(
          item,
          cached: cw,
          isCurrent: isCurrent,
        );
        final sel = signal?.sel;
        if (!isCurrent()) return null;
        if (sel != null) {
          return HomeCatalogPlaybackTarget.play(sel);
        }
      }
    }

    if (item.type != 'series') {
      // Cross-device movie resume: on the detail-page Play/Resume flow
      // (preferTraktResume, or a tracker-sourced open), pull the movie's paused
      // tracker position and carry it on the selection. The player's resume
      // reconciliation then seeks the furthest of trakt%/simkl%/local — so a
      // movie paused on another device resumes here even when opened from a
      // plain catalog result (previously movies started at 00:00). Row
      // quick-play (no preferTraktResume) keeps its local-only resume.
      double? traktPct;
      double? simklPct;
      double? mdblistPct;
      if (preferTraktResume || isTraktSource) {
        // Concurrent and individually time-boxed: the Play press must never
        // stall behind a degraded tracker API (sequential awaits here could
        // previously block playback for the full HTTP timeouts). On timeout we
        // launch with local-only resume — the reconciliation in the player
        // degrades gracefully to the local position.
        final lookups = await Future.wait<double?>([
          trackingPolicy.progressFrom(TrackingSource.trakt) &&
                  (availability().trakt || isTraktSource)
              ? trackers
                    .traktMovie(
                      item.progressId ?? item.id,
                      isCurrent: isCurrent,
                    )
                    .timeout(const Duration(seconds: 4), onTimeout: () => null)
              : Future<double?>.value(null),
          trackingPolicy.progressFrom(TrackingSource.simkl) &&
                  availability().simkl
              ? trackers
                    .simklMovie(
                      item.progressId ?? item.id,
                      isCurrent: isCurrent,
                    )
                    .timeout(const Duration(seconds: 4), onTimeout: () => null)
              : Future<double?>.value(null),
          trackingPolicy.progressFrom(TrackingSource.mdblist) &&
                  availability().mdblist
              ? trackers
                    .mdblistMovie(
                      item.progressId ?? item.id,
                      isCurrent: isCurrent,
                    )
                    .timeout(const Duration(seconds: 4), onTimeout: () => null)
              : Future<double?>.value(null),
        ]);
        if (!isCurrent()) return null;
        traktPct = lookups[0];
        simklPct = lookups[1];
        mdblistPct = lookups[2];
      }
      // Rewatch (Simkl): a movie already marked `completed` on Simkl has no
      // resume session, and Simkl won't create one on replay — so it can never
      // re-enter Continue Watching. On the detail Play/Resume flow (the
      // "Rewatch" button surface, preferTraktResume), un-mark it watched first
      // so the upcoming catalog scrobble creates a fresh resume session; the
      // ≥80% stop re-marks it completed when the rewatch finishes. Gated on the
      // sync setting + auth so we never un-complete a movie that won't actually
      // be re-tracked. Row quick-play (no preferTraktResume) is left untouched.
      // WRITE-side action: gated on auth + the Scrobble master (below), NOT
      // the Progress source — a This-device user scrobbling to Simkl still
      // needs the replay session created.
      if (preferTraktResume && availability().simkl) {
        // Same id resolution the detail screen's status loader uses (_imdbOf),
        // so the "Rewatch" label and this flip never disagree on the title.
        final rawImdb =
            item.progressId ?? (item.id.startsWith('tt') ? item.id : null);
        final imdb = rawImdb != null && rawImdb.isNotEmpty ? rawImdb : null;
        final scrobblesSimkl = trackingPolicy.scrobbles(TrackingSource.simkl);
        if (!isCurrent()) return null;
        if (imdb != null && scrobblesSimkl) {
          // Time-boxed like the tracker-percent lookups above: a degraded Simkl
          // API must never stall the Play press. On timeout we just skip the
          // flip — worst case the rewatch doesn't surface in Continue Watching,
          // exactly today's behaviour.
          await readers.prepareMovieRewatch(item, imdb, isCurrent: isCurrent);
          if (!isCurrent()) return null;
        }
      }
      // Keep the detail page underneath — the cinematic loading overlay covers
      // it, and after playback Back returns to the detail (like Home).
      return HomeCatalogPlaybackTarget.play(
        homeCatalogMovieSelection(
          item,
          isTraktSource: isTraktSource,
          isMdblistSource: isMdblistSource,
          traktProgressPercent: traktPct,
          simklProgressPercent: simklPct,
          mdblistProgressPercent: mdblistPct,
        ),
      );
    }

    final ttId = item.imdbId ?? (item.id.startsWith('tt') ? item.id : '');
    // Without an IMDb id we can't search torrents for a specific episode, so
    // fall back to the manual episode picker — except from the merged page
    // (episodes are inline there), where we play via the raw id's addon stream.
    if (ttId.isEmpty &&
        !MediaIdentity.isNative(item.id) &&
        !skipEpisodeFallback) {
      return const HomeCatalogPlaybackTarget.episodes();
    }
    // Play id: the `tt…` id when present (torrent-resolvable); otherwise the raw
    // catalog id, which playFromSelection routes to the addon /stream endpoint.
    final playId = ttId.isNotEmpty ? ttId : (item.progressId ?? item.id);

    // Resolve where to resume, mirroring EpisodesScreen's landing logic:
    // last-played episode for this show (by imdbId, then by title), else S01E01.
    int? season;
    int? episode;
    final byId = trackingPolicy.progressFrom(TrackingSource.local)
        ? await readers.localById(playId, isCurrent: isCurrent)
        : null;
    if (!isCurrent()) return null;
    season = byId?['season'] as int?;
    episode = byId?['episode'] as int?;
    final lastFinished = byId?['finished'] == true;
    if (!MediaIdentity.isNative(playId) &&
        !CustomSeriesIdentity.isCustom(playId) &&
        (season == null || episode == null)) {
      final byTitle = trackingPolicy.progressFrom(TrackingSource.local)
          ? await readers.localByTitle(item.name, isCurrent: isCurrent)
          : null;
      if (!isCurrent()) return null;
      season ??= byTitle?['season'] as int?;
      episode ??= byTitle?['episode'] as int?;
    }
    // No local history — last resort: Simkl's next-to-watch, mirroring the
    // label (_resolveResumeInfo) so the two agree. Only on the detail Resume
    // flow, and TIME-BOXED (4s) like the movie branch so a slow Simkl API never
    // freezes the Play press — on timeout it falls through to S01E01.
    if ((season == null || episode == null) &&
        availability().simkl &&
        trackingPolicy.progressFrom(TrackingSource.simkl) &&
        preferTraktResume) {
      final next = await signals
          .simklNext(item, isCurrent: isCurrent)
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
      if (!isCurrent()) return null;
      if (next != null) {
        season = next.season;
        episode = next.episode;
      }
    }
    if ((season == null || episode == null) &&
        availability().mdblist &&
        trackingPolicy.progressFrom(TrackingSource.mdblist) &&
        preferTraktResume) {
      final next = await trackers
          .mdblistItem(item.progressId ?? item.id, isCurrent: isCurrent)
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
      if (!isCurrent()) return null;
      if (next != null) {
        season = next.selection.season;
        episode = next.selection.episode;
      }
    }
    season ??= 1;
    episode ??= 1;
    // If the last-played episode is finished, resume the NEXT one instead of
    // re-opening it — parity with the deprecated home's continue-watching
    // quick-play (only the local, non-Trakt path; Trakt resolves its own next).
    if (lastFinished) {
      final next = await readers.nextEpisode(
        item,
        addon,
        playId,
        season,
        episode,
        isCurrent: isCurrent,
      );
      if (!isCurrent()) return null;
      if (next != null) {
        season = next.season;
        episode = next.episode;
      }
    }
    if (!isCurrent()) return null;

    return HomeCatalogPlaybackTarget.play(
      AdvancedSearchSelection(
        imdbId: playId,
        isSeries: true,
        title: item.name,
        year: item.year,
        season: season,
        episode: episode,
        contentType: item.type,
        posterUrl: item.poster,
        traktSource: isTraktSource,
        mdblistSource: isMdblistSource,
      ),
    );
  }
}
