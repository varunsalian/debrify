import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/alldebrid_file.dart';
import '../models/playlist_view_mode.dart';
import '../models/premiumize_file.dart';
import '../models/rd_torrent.dart';
import '../models/torbox_file.dart';
import '../models/torrent.dart';
import '../screens/video_player/models/playlist_entry.dart';
import '../utils/deovr_utils.dart' as deovr;
import '../utils/dialog_tap_guard.dart';
import '../utils/file_utils.dart';
import '../utils/formatters.dart';
import '../utils/rd_blocked_filter.dart';
import '../utils/rd_folder_tree_builder.dart';
import '../utils/series_parser.dart';
import '../utils/torrent_coverage_detector.dart';
import '../utils/torrent_curation.dart';
import '../widgets/debrid_action_sheet.dart';
import '../widgets/debrid_loading_overlay.dart';
import '../widgets/poster_play_loading_overlay.dart';
import '../widgets/provider_picker_dialog.dart';
import 'alldebrid_service.dart';
import 'debrid_service.dart';
import 'debrify_tv_channel_add_service.dart';
import 'download_service.dart';
import 'local_bound_source_service.dart';
import 'main_page_bridge.dart';
import 'pikpak_api_service.dart';
import 'premiumize_service.dart';
import 'series_source_service.dart';
import 'storage_service.dart';
import 'torbox_service.dart';
import 'torrent_file_service.dart';
import 'torrent_service.dart';
import 'video_player_launcher.dart';

/// Content identity for a playback, so the player can record Continue Watching,
/// fetch subtitles, and drive the Episodes button (matching Home).
class PlaybackMeta {
  final String? imdbId;
  final String? contentType; // 'movie' | 'series'
  final int? season;
  final int? episode;
  final String? title; // clean display title
  final String? posterUrl;
  final String? year;
  final String? addonId; // originating Stremio addon (resume / next-episode)
  final double? traktProgressPercent; // Trakt watch position, if known
  // Play came from a Trakt row → scrobble to Trakt instead of saving a local
  // Continue Watching entry (mirrors Home passing selection.traktSource).
  final bool traktScrobble;
  const PlaybackMeta({
    this.imdbId,
    this.contentType,
    this.season,
    this.episode,
    this.title,
    this.posterUrl,
    this.year,
    this.addonId,
    this.traktProgressPercent,
    this.traktScrobble = false,
  });
}

/// Isolated "add a chosen torrent to debrid → do the configured post-torrent
/// action" flow, composed ONLY from service-layer primitives.
///
/// Deliberately independent of the Home screen's ~2k-line inline engine so the
/// Search tab can play/download/queue without any risk of regressing Home.
/// Reimplements the small dialog UIs (not-cached, chooser) since those are
/// Home-private; everything else calls the shared services directly.
///
/// Multi-file season packs open as a playlist for all providers — TorBox /
/// Premiumize / AllDebrid built here, RD + PikPak ported verbatim from Home's
/// proven builders. The launcher lazily resolves each non-start entry.
/// Channel / advanced-metadata are follow-up slices.
class TorrentPlaybackService {
  const TorrentPlaybackService._();

  /// Distinguishes "user dismissed the provider picker" (silent) from
  /// "no provider configured" (null → prompt to add one in Settings).
  static const String _cancelled = '__cancelled__';

  /// Series-auto-pin negative cache: "imdbId:season" → when to allow
  /// re-searching packs. A pack-first attempt that finds no instantly-playable
  /// pack records an entry so subsequent episodes of the SAME season (a binge,
  /// or an ongoing show with no pack yet) skip the expensive whole-series pack
  /// search instead of repeating it every play. Keyed by season because the
  /// search probes the requested season, so "no pack for S1" must not suppress
  /// finding an S7 season pack. In-memory + TTL so a newly-released pack is
  /// still picked up after the window (or an app restart).
  static final Map<String, DateTime> _noPackUntil = {};
  static const Duration _noPackTtl = Duration(hours: 6);

  static String _noPackKey(String imdbId, int season) => '$imdbId:$season';

  static bool _recentlyNoPack(String imdbId, int season) {
    final key = _noPackKey(imdbId, season);
    final until = _noPackUntil[key];
    if (until == null) return false;
    if (!DateTime.now().isBefore(until)) {
      _noPackUntil.remove(key);
      return false;
    }
    return true;
  }

  static void _markNoPack(String imdbId, int season) {
    // Bound the map so a long session browsing many shows can't grow it
    // without limit; drop expired entries first, then the oldest.
    final now = DateTime.now();
    _noPackUntil.removeWhere((_, until) => !now.isBefore(until));
    const cap = 200;
    if (_noPackUntil.length >= cap) {
      final oldest = _noPackUntil.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
          .key;
      _noPackUntil.remove(oldest);
    }
    _noPackUntil[_noPackKey(imdbId, season)] = now.add(_noPackTtl);
  }

  /// Add [torrent] to the resolved provider and run the user's post-torrent
  /// action (choose / play / download / playlist / open / none / copy).
  /// [forcePlay] overrides the setting to play (used by "auto-best" play).
  static Future<void> activateTorrent(
    BuildContext context,
    Torrent torrent, {
    bool forcePlay = false,
    PlaybackMeta? meta,
    List<Torrent>? sources,
    int sourceIndex = 0,
    String searchKeyword = '',
  }) async {
    // Direct-URL addon streams bypass debrid entirely. Content metadata and
    // the in-player Sources switcher ride along (matching Home's
    // _playDirectStream) so series streams get Continue Watching, subtitles,
    // source switching, and the Next Episode hand-back. No provider is
    // involved, so the advance goes bound-sources → addon-stream flow.
    if (torrent.streamType == StreamType.directUrl &&
        (torrent.directUrl?.isNotEmpty ?? false)) {
      await VideoPlayerLauncher.push(
        context,
        _playerArgs(
          videoUrl: torrent.directUrl!,
          title: torrent.displayTitle,
          subtitle: torrent.source.isNotEmpty ? torrent.source : null,
          stremioSources: sources,
          stremioCurrentSourceIndex: sources != null ? sourceIndex : null,
          resolveSourceToPlaylist: (sources != null && sources.length > 1)
              ? _lazyProviderResolver()
              : null,
          meta: meta,
        ),
        onQuickPlayNextEpisode: _nextEpisodeHandlerFor(context, meta),
      );
      return;
    }

    // External addon streams open in an external app/browser (no debrid), same
    // as Home's _openExternalStream. Both stream kinds carry their URL in
    // directUrl.
    if (torrent.streamType == StreamType.externalUrl &&
        (torrent.directUrl?.isNotEmpty ?? false)) {
      final uri = Uri.tryParse(torrent.directUrl!);
      if (uri == null) {
        _snack(context, 'Invalid stream URL.');
        return;
      }
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok && context.mounted) {
          _snack(context, 'Could not open link — no app to handle it.');
        }
      } catch (e) {
        if (context.mounted) _snack(context, 'Could not open link: $e');
      }
      return;
    }

    final provider = await _pickProvider(context);
    if (!context.mounted) return;
    if (provider == _cancelled) return; // user dismissed the picker
    if (provider == null) {
      _snack(context, 'No debrid provider configured. Add one in Settings.');
      return;
    }
    final magnet = await _magnetFor(torrent);
    if (!context.mounted) return;
    if (magnet == null) {
      _snack(context, 'This result has no magnet or infohash to play.');
      return;
    }
    final action = forcePlay ? 'play' : await _postAction(provider);
    if (!context.mounted) return;

    final rootNav = Navigator.of(context, rootNavigator: true);
    _showLoading(context, provider, torrent.displayTitle);
    _Resolved? resolved;
    Object? notCached;
    try {
      resolved = await _add(provider, magnet, torrent);
    } on TorrentNotCachedException catch (e) {
      notCached = e;
    } on AllDebridTorrentNotReadyException catch (e) {
      notCached = e;
    } on _TorboxNotCached catch (e) {
      notCached = e;
    } on _PremiumizeNotCached catch (e) {
      notCached = e;
    } on _PikPakStillProcessing {
      if (rootNav.canPop()) rootNav.pop();
      if (context.mounted) {
        _snack(context,
            'Files still processing on PikPak. Check the PikPak Files page later.');
      }
      return;
    } on _PikPakFailed {
      if (rootNav.canPop()) rootNav.pop();
      if (context.mounted) _snack(context, 'Download failed on PikPak.');
      return;
    } catch (e) {
      if (rootNav.canPop()) rootNav.pop();
      if (context.mounted) _snack(context, 'Could not resolve source: $e');
      return;
    }
    if (rootNav.canPop()) rootNav.pop();
    if (!context.mounted) return;

    if (notCached != null) {
      await _handleNotCached(context, notCached, provider, magnet);
      return;
    }
    if (resolved == null) {
      _snack(context, 'No playable source found for this result.');
      return;
    }

    switch (action) {
      case 'none':
        _snack(context, 'Torrent added to ${_label(provider)} successfully.');
        break;
      case 'open':
        if (resolved.isRarArchive) {
          _snack(context, 'Not available for RAR archives.');
        } else {
          resolved.openInTab?.call();
        }
        break;
      case 'copy':
        if (resolved.playUrl != null && resolved.playUrl!.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: resolved.playUrl!));
          if (context.mounted) {
            _snack(context,
                'Torrent added to ${_label(provider)}! Download link copied to clipboard.');
          }
        } else {
          _snack(context,
              'Added to ${_label(provider)}, but no link was available to copy.');
        }
        break;
      case 'download':
        await _download(context, resolved, torrent);
        break;
      case 'playlist':
        await _addToPlaylist(context, resolved, torrent, provider, meta: meta);
        break;
      case 'channel':
        // Saved "Add to channel" action (parity with the old screen): cache the
        // torrent into a Debrify TV channel instead of playing it. Without this
        // case the switch fell through to `default` and silently played.
        await DebrifyTvChannelAddService.addTorrentsToChannel(
          context,
          torrents: [torrent],
          searchKeyword: searchKeyword,
        );
        break;
      case 'choose':
        await _showChooser(context, resolved, torrent, provider,
            magnet: magnet,
            meta: meta,
            sources: sources,
            sourceIndex: sourceIndex,
            searchKeyword: searchKeyword);
        break;
      case 'play':
      default:
        await _play(context, resolved, torrent,
            provider: provider,
            meta: meta,
            sources: sources,
            sourceIndex: sourceIndex);
        break;
    }
  }

  /// Catalog "Play" — auto-pick the best instantly-playable source and play it.
  /// Cache-first ordering for TorBox/Premiumize; the resolve loop cleans up any
  /// uncached torrent it probes on RD/AllDebrid so the account isn't polluted.
  static Future<void> playBest(
    BuildContext context,
    List<Torrent> torrents, {
    String? provider,
    String? title,
    PlaybackMeta? meta,
    bool overlayAlreadyShown = false,
    PosterPlayLoadingOverlay? overlay,
    bool Function()? isCancelled,
  }) async {
    final rootNav = Navigator.of(context, rootNavigator: true);
    // Dismiss whichever loading affordance is on screen, exactly once (the
    // poster mask handle, else the DebridLoadingOverlay route).
    void closeLoading() {
      if (overlay != null) {
        overlay.dismiss();
      } else if (rootNav.canPop()) {
        rootNav.pop();
      }
    }

    bool cancelled() => isCancelled?.call() ?? false;

    // A direct-URL addon stream, if present, is the cheapest instant play — and
    // needs no debrid provider, so play it before prompting for one. This is the
    // IPTV / non-IMDb catalog path (streams come straight from the addon).
    Torrent? direct;
    for (final t in torrents) {
      if (t.streamType == StreamType.directUrl &&
          (t.directUrl?.isNotEmpty ?? false)) {
        direct = t;
        break;
      }
    }
    if (direct != null) {
      if (overlayAlreadyShown) closeLoading();
      // Content metadata and the Sources switcher ride along (matching Home's
      // _playDirectStream) so series streams get Continue Watching, subtitles,
      // source switching, and the Next Episode hand-back. The advance reuses
      // [provider] when the caller resolved one (torrent chain); otherwise it
      // stays on the bound-sources → addon-stream path this play came from.
      await VideoPlayerLauncher.push(
        context,
        _playerArgs(
          videoUrl: direct.directUrl!,
          title: direct.displayTitle,
          subtitle: direct.source.isNotEmpty ? direct.source : null,
          stremioSources: torrents,
          stremioCurrentSourceIndex: torrents.indexOf(direct),
          resolveSourceToPlaylist:
              torrents.length > 1 ? _lazyProviderResolver() : null,
          meta: meta,
        ),
        onQuickPlayNextEpisode:
            _nextEpisodeHandlerFor(context, meta, provider: provider),
      );
      return;
    }

    final prov = provider ?? await _pickProvider(context);
    // These bail-outs are reachable when the caller passed no provider (the
    // non-IMDb addon-stream path with only torrent results). Dismiss the
    // caller's overlay on each, or it stays stuck full-screen (both overlays
    // are non-dismissable by the system back button).
    if (!context.mounted) {
      if (overlayAlreadyShown) closeLoading();
      return;
    }
    if (prov == _cancelled) {
      if (overlayAlreadyShown) closeLoading(); // user dismissed the picker
      return;
    }
    if (prov == null) {
      if (overlayAlreadyShown) closeLoading();
      _snack(context, 'No debrid provider configured. Add one in Settings.');
      return;
    }

    var candidates = torrents
        .where((t) =>
            t.streamType != StreamType.externalUrl && _hasAcquisition(t))
        .toList();
    if (candidates.isEmpty) {
      if (overlayAlreadyShown) closeLoading();
      _snack(context, 'No playable sources found for this title.');
      return;
    }
    if (prov == 'torbox' || prov == 'premiumize') {
      candidates = await _cacheFirst(prov, candidates);
      if (!context.mounted) {
        // Screen went away mid cache-check — still dismiss our overlay so it
        // can't get stuck covering the next screen (guarded so a direct
        // playBest call, which hasn't shown its overlay yet, never pops).
        if (overlayAlreadyShown) closeLoading();
        return;
      }
    }
    if (cancelled()) return; // user tapped Cancel during the cache-check

    if (!overlayAlreadyShown) {
      _showLoading(context, prov,
          title ?? (candidates.isNotEmpty ? candidates.first.displayTitle : ''));
    }
    final (res, winner) = await _probeCandidates(
      prov,
      candidates,
      season: meta?.season,
      episode: meta?.episode,
      isCancelled: cancelled,
    );
    if (cancelled()) return; // dismissed by the Cancel tap; nothing more to do
    closeLoading();
    if (!context.mounted) return;
    if (res == null) {
      _snack(context,
          'No instantly-playable source found. Open Sources to pick or download one.');
      return;
    }
    final idx = torrents.indexOf(winner!);
    await _launch(
      context,
      res,
      winner.displayTitle,
      provider: prov,
      meta: meta,
      sources: torrents,
      sourceIndex: idx < 0 ? 0 : idx,
    );
  }

  /// Probe [candidates] in order on [prov] until one resolves to an instantly
  /// playable URL — and, when [season]/[episode] are both set, actually
  /// contains that episode (a pack that resolved fine but lacks the episode is
  /// skipped and its fresh RD/PikPak entry deleted, matching _playViaBound).
  /// Honors the Quick-Play retry settings: PikPak probes only the top
  /// candidate (each probe queues a real download we can't cheaply clean up);
  /// others try one candidate, or up to the configured max when "try multiple
  /// torrents" is on. Returns the resolution and the winning torrent, or
  /// (null, null) on failure/cancel.
  static Future<(_Resolved?, Torrent?)> _probeCandidates(
    String prov,
    List<Torrent> candidates, {
    int? season,
    int? episode,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;
    final tryMultiple = await StorageService.getQuickPlayTryMultipleTorrents();
    final maxRetries = await StorageService.getQuickPlayMaxRetries();
    // Clamp to a floor of 1 so a corrupted/out-of-range pref can never yield 0
    // probes (getQuickPlayMaxRetries doesn't clamp on read).
    final maxAttempts =
        prov == 'pikpak' ? 1 : (tryMultiple ? maxRetries.clamp(1, 10) : 1);
    for (final t in candidates.take(maxAttempts)) {
      if (cancelled()) return (null, null);
      try {
        final magnet = await _magnetFor(t);
        if (magnet == null) continue;
        if (cancelled()) return (null, null);
        final r = await _add(prov, magnet, t);
        if (r.playUrl != null && r.playUrl!.isNotEmpty) {
          // For a series episode, don't accept a pack that resolved fine but
          // doesn't actually contain the requested episode (mislabeled or
          // wrong-season result) — mirror _playViaBound instead of letting the
          // player silently start the wrong/first episode. Keep probing the
          // remaining candidates for one that genuinely has it.
          if (season != null &&
              episode != null &&
              !_resolvedHasEpisode(r, season, episode)) {
            // Delete the fresh RD/PikPak entry this probe created so skips
            // don't pile up orphans (TorBox/AllDebrid dedup the add; Premiumize
            // adds nothing), matching _playViaBound's cleanup.
            if (prov == 'debrid' && (r.rdTorrentId?.isNotEmpty ?? false)) {
              try {
                final apiKey = (await StorageService.getApiKey()) ?? '';
                await DebridService.deleteTorrent(apiKey, r.rdTorrentId!);
              } catch (_) {}
            } else if (prov == 'pikpak' &&
                (r.pikpakFileId?.isNotEmpty ?? false)) {
              try {
                await PikPakApiService.instance.batchDeleteFiles([
                  r.pikpakFileId!,
                ]);
              } catch (_) {}
            }
            continue;
          }
          return (r, t);
        }
      } on TorrentNotCachedException catch (e) {
        // Probed torrent is downloading — remove it so RD stays clean.
        try {
          await DebridService.deleteTorrent(e.apiKey, e.torrentId);
        } catch (_) {}
      } on AllDebridTorrentNotReadyException catch (e) {
        try {
          await AllDebridService.deleteMagnet(e.apiKey, e.magnetId);
        } catch (_) {}
      } catch (_) {
        // _TorboxNotCached / _PremiumizeNotCached / transient — try next.
      }
    }
    return (null, null);
  }

  /// Full catalog-play flow: pick provider, show the cinematic overlay (with the
  /// real provider name), search torrents for the title, and auto-play the best
  /// — all under ONE overlay. Used by the Search tab's catalog Play button.
  static Future<void> playFromSelection(
    BuildContext context, {
    required String imdbId,
    required bool isMovie,
    int? season,
    int? episode,
    required PlaybackMeta meta,
    // Skip the provider picker and use this provider directly — set by the
    // next-episode auto-advance so a binge never re-prompts mid-chain.
    String? preferredProvider,
  }) async {
    final label = meta.title ?? '';
    if (imdbId.isEmpty) {
      _snack(context, 'No IMDb match to find sources for "$label".');
      return;
    }

    // Any non-`tt` id can't be resolved by the torrent engines — they key on
    // `tt…` ids — so it must resolve from the addon's own /stream endpoint. This
    // covers IPTV/TV channels AND kitsu/tmdb-only movie & series catalogs, and
    // matches old home, whose quick-play always ran the Stremio-inclusive search
    // (so a non-`tt` series episode played from the addon stream instead of
    // failing a doomed torrent search). A `tt…` id — even a non-standard type
    // like some anime catalogs — keeps the normal torrent search below so the
    // on-device engines still run. (imdbId.isEmpty is already handled above.)
    if (!imdbId.startsWith('tt')) {
      await _playAddonStream(context, imdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
          meta: meta,
          label: label);
      return;
    }

    // Bound-source reuse: if the user pinned a source for this title, play it
    // directly and skip the torrent search entirely. A series binding is only
    // usable when a concrete season+episode is requested (to land in the pack).
    final bound = await SeriesSourceService.getSources(imdbId);
    if (!context.mounted) return;
    // A series binding needs a concrete season+episode to land inside the pack.
    // Gate on the same fields _launch forwards to the player (meta.*), so the
    // requested episode is guaranteed to reach findOriginalIndexBySeasonEpisode.
    final boundUsable = bound.isNotEmpty &&
        (isMovie || (meta.season != null && meta.episode != null));
    if (boundUsable) {
      final played = await _playViaBound(context, imdbId, bound,
          label: label, meta: meta);
      if (played) return;
      if (!context.mounted) return;
      // Bound source unplayable → fall through to a normal search below.
    }

    final provider = preferredProvider ?? await _pickProvider(context);
    if (!context.mounted) return;
    if (provider == _cancelled) return;
    if (provider == null) {
      _snack(context, 'No debrid provider configured. Add one in Settings.');
      return;
    }
    final rootNav = Navigator.of(context, rootNavigator: true);
    // With a poster, show the cinematic poster mask (with Cancel); otherwise the
    // provider-branded loading overlay. ONE overlay spans search → resolve → play.
    final usePoster = meta.posterUrl != null && meta.posterUrl!.isNotEmpty;
    final cancel = _PlaybackCancelToken();
    PosterPlayLoadingOverlay? overlay;
    if (usePoster) {
      overlay = PosterPlayLoadingOverlay.show(
        context,
        posterUrl: meta.posterUrl,
        title: label,
        provider: _label(provider),
        accentColor: _providerGradient(provider).first,
        icon: _providerIcon(provider),
        onCancel: () => cancel.cancelled = true,
      );
    } else {
      _showLoading(context, provider, label);
    }
    final shownOverlay = overlay;
    void closeLoading() {
      if (shownOverlay != null) {
        shownOverlay.dismiss();
      } else if (rootNav.canPop()) {
        rootNav.pop();
      }
    }

    // Series auto-pin (on by default, toggle in Quick Play settings): with no
    // usable pinned source, search PACKS
    // first — the whole-series search with season probing, same as the
    // Sources screen's "Show Season Packs" — and play the widest pack that
    // actually contains the requested episode (complete series → multi-season
    // → season pack). _launch's auto-bind then pins the winner, so every later
    // play of this series goes straight through the bound path. When no pack
    // qualifies or none is instantly playable, fall through to the normal
    // episode search below (whose winner also gets pinned).
    // PikPak is excluded: it has no cache check, so each pack probe queues a
    // real (large) offline download to the user's account that can't be
    // cheaply cleaned up — pack-first there would be actively harmful.
    if (!isMovie &&
        season != null &&
        episode != null &&
        provider != 'pikpak' &&
        !_recentlyNoPack(imdbId, season) &&
        await StorageService.getAutoBindSeriesPacksOnPlay()) {
      List<Torrent> packs = const [];
      var searchOk = false;
      try {
        final packRes = await TorrentService.searchByImdbWithStremio(
          imdbId,
          isMovie: false,
          contentType: 'series',
          // No season/episode → the whole-series smart-fallback path. Seed the
          // probe with the requested season so its season-pack tier is found
          // for ANY season (the default probe is only S1–S5).
          availableSeasons: [season],
        );
        packs = (packRes['torrents'] as List).cast<Torrent>();
        searchOk = true;
      } catch (_) {
        // Pack search failed (e.g. transient network) — the episode search
        // below still runs, and we DON'T poison the negative cache so the next
        // episode retries rather than deferring for the whole TTL.
      }
      if (cancel.cancelled) return;
      if (!context.mounted) {
        closeLoading();
        return;
      }
      packs = await _curatePackCandidates(packs,
          label: label, season: season, provider: provider);
      if (packs.isNotEmpty &&
          (provider == 'torbox' || provider == 'premiumize')) {
        packs = await _cacheFirst(provider, packs);
      }
      if (cancel.cancelled) return;
      if (!context.mounted) {
        closeLoading();
        return;
      }
      if (packs.isNotEmpty) {
        final (packResolved, packWinner) = await _probeCandidates(
          provider,
          packs,
          season: season,
          episode: episode,
          isCancelled: () => cancel.cancelled,
        );
        if (cancel.cancelled) return;
        if (!context.mounted) {
          closeLoading();
          return;
        }
        if (packResolved != null && packWinner != null) {
          closeLoading();
          final idx = packs.indexOf(packWinner);
          await _launch(context, packResolved, packWinner.displayTitle,
              provider: provider,
              meta: meta,
              sources: packs,
              sourceIndex: idx < 0 ? 0 : idx);
          return;
        }
        // No pack was instantly playable — fall through to the episode search.
      }
      // Reached only when no pack played (cancel / unmount paths returned
      // above). Remember it — but only when the search actually SUCCEEDED with
      // no playable pack (not a transient failure) — so the next episode of
      // this season skips the pack search until the TTL lapses.
      if (searchOk) _markNoPack(imdbId, season);
    }

    Map<String, dynamic> res;
    try {
      res = await TorrentService.searchByImdb(imdbId,
          isMovie: isMovie, season: season, episode: episode);
    } catch (e) {
      if (cancel.cancelled) return; // overlay already dismissed by Cancel
      closeLoading();
      if (context.mounted) _snack(context, 'Search failed: $e');
      return;
    }
    if (cancel.cancelled) return;
    if (!context.mounted) {
      closeLoading();
      return;
    }
    var torrents = (res['torrents'] as List).cast<Torrent>();
    if (torrents.isEmpty) {
      closeLoading();
      _snack(context, 'No sources found for "$label".');
      return;
    }
    // Curate candidates so the RIGHT torrent is probed first (mirrors old home):
    // drop unrelated titles, keep/relevance-sort by the requested episode/season,
    // then drop RD-blocked keywords when RD is the provider. Without this the raw
    // seeder-ranked list can lead with wrong-episode/other-season packs that
    // resolve fine but get rejected by _resolvedHasEpisode, burning the probes.
    torrents = await _curateCandidates(
      torrents,
      label: label,
      isMovie: isMovie,
      season: season,
      episode: episode,
      provider: provider,
    );
    if (torrents.isEmpty) {
      closeLoading();
      _snack(context, 'No sources found for "$label".');
      return;
    }
    await playBest(context, torrents,
        provider: provider,
        title: label,
        meta: meta,
        overlayAlreadyShown: true,
        overlay: overlay,
        isCancelled: () => cancel.cancelled);
  }

  /// Curate torrent candidates before probing, mirroring the old Home engine:
  ///   1. drop torrents whose name doesn't match the title (unrelated packs),
  ///   2. keep + relevance-sort by the requested episode/season,
  ///   3. when RD is the provider and the user's "skip blocked" setting is on,
  ///      drop RD-blocked-keyword torrents.
  /// Every step falls back to the pre-step list if it would empty the set, so
  /// curation can never turn a non-empty result into a "no sources" failure.
  static Future<List<Torrent>> _curateCandidates(
    List<Torrent> torrents, {
    required String label,
    required bool isMovie,
    int? season,
    int? episode,
    required String provider,
  }) async {
    var out = torrents;

    // 1. Title match (skip when we have no label to match against).
    if (label.trim().isNotEmpty) {
      final matched =
          out.where((t) => torrentMatchesTitle(t.name, label)).toList();
      if (matched.isNotEmpty) out = matched;
    }

    // 2. Episode relevance filter + sort (no-op for movies / missing S-E).
    out = curateEpisodeCandidates(
      out,
      isSeries: !isMovie,
      season: season,
      episode: episode,
    );

    // 3. RD blocked-keyword filter (RD provider + setting enabled).
    if (provider == 'debrid' &&
        await StorageService.getRdSkipBlockedTorrents()) {
      final unblocked = out.where((t) => !isRdBlockedTorrent(t.name)).toList();
      if (unblocked.isNotEmpty) out = unblocked;
    }

    return out;
  }

  /// Pack candidates for the series auto-pin pack-first play: torrent-type
  /// sources whose name matches the title and whose coverage spans [season],
  /// widest coverage first (complete series → multi-season → season pack),
  /// then more seasons, then seeders. STRICT — no fall-back-to-unfiltered like
  /// [_curateCandidates]: a wrong pack here would get PINNED, so when nothing
  /// qualifies the caller falls back to the normal episode search instead.
  static Future<List<Torrent>> _curatePackCandidates(
    List<Torrent> torrents, {
    required String label,
    required int season,
    required String provider,
  }) async {
    var out = torrents
        .where((t) =>
            t.streamType == StreamType.torrent &&
            _hasAcquisition(t) &&
            t.infohash.isNotEmpty)
        .toList();

    if (label.trim().isNotEmpty) {
      out = out.where((t) => torrentMatchesTitle(t.name, label)).toList();
    }

    bool coversSeason(Torrent t) {
      switch (t.coverageType) {
        case 'completeSeries':
          return true;
        case 'multiSeasonPack':
          if (t.startSeason != null && t.endSeason != null) {
            return t.startSeason! <= season && t.endSeason! >= season;
          }
          return true; // unknown range — the probe validates episode presence
        case 'seasonPack':
          return t.seasonNumber == season;
        default:
          return false; // singles/unknown → the episode fallback handles them
      }
    }

    out = out.where(coversSeason).toList();

    if (provider == 'debrid' &&
        await StorageService.getRdSkipBlockedTorrents()) {
      out = out.where((t) => !isRdBlockedTorrent(t.name)).toList();
    }

    int tier(Torrent t) {
      switch (t.coverageType) {
        case 'completeSeries':
          return 0;
        case 'multiSeasonPack':
          return 1;
        default: // seasonPack
          return 2;
      }
    }

    out.sort((a, b) {
      final d = tier(a) - tier(b);
      if (d != 0) return d;
      final s = b.seasonCount.compareTo(a.seasonCount); // more seasons first
      if (s != 0) return s;
      return b.seeders.compareTo(a.seeders);
    });
    return out;
  }

  /// Play non-IMDb catalog content (IPTV / TV channels) straight from the
  /// addon's own stream endpoint — no torrent engine, no debrid provider. Shows
  /// the same cinematic overlay as [playFromSelection] and hands the resolved
  /// streams to [playBest], which plays a direct stream instantly.
  static Future<void> _playAddonStream(
    BuildContext context,
    String id, {
    required bool isMovie,
    int? season,
    int? episode,
    required PlaybackMeta meta,
    required String label,
  }) async {
    const accent = Color(0xFF7B5CFF);
    final cancel = _PlaybackCancelToken();
    final rootNav = Navigator.of(context, rootNavigator: true);
    final usePoster = meta.posterUrl != null && meta.posterUrl!.isNotEmpty;
    PosterPlayLoadingOverlay? overlay;
    if (usePoster) {
      overlay = PosterPlayLoadingOverlay.show(
        context,
        posterUrl: meta.posterUrl,
        title: label,
        provider: 'Stream',
        accentColor: accent,
        icon: Icons.live_tv_rounded,
        onCancel: () => cancel.cancelled = true,
      );
    } else {
      DebridLoadingOverlay.show(context,
          provider: 'Stream',
          torrentName: label,
          accentColor: accent,
          icon: Icons.live_tv_rounded);
    }
    void closeLoading() {
      if (overlay != null) {
        overlay.dismiss();
      } else if (rootNav.canPop()) {
        rootNav.pop();
      }
    }

    Map<String, dynamic> res;
    try {
      res = await TorrentService.searchByImdbWithStremio(
        id,
        isMovie: isMovie,
        season: season,
        episode: episode,
        contentType: meta.contentType,
      );
    } catch (e) {
      if (cancel.cancelled) return;
      closeLoading();
      if (context.mounted) _snack(context, 'Search failed: $e');
      return;
    }
    if (cancel.cancelled) return;
    if (!context.mounted) {
      closeLoading();
      return;
    }
    final torrents = (res['torrents'] as List).cast<Torrent>();
    if (torrents.isEmpty) {
      closeLoading();
      _snack(context, 'No stream found for "$label".');
      return;
    }
    // playBest plays a direct addon stream instantly (no provider needed); if
    // there somehow isn't one it falls through to the normal provider path.
    await playBest(context, torrents,
        title: label,
        meta: meta,
        overlayAlreadyShown: true,
        overlay: overlay,
        isCancelled: () => cancel.cancelled);
  }

  /// Real-Debrid is `'rd'` in [SeriesSource] (Home's convention, shared
  /// storage) but `'debrid'` as this service's provider key. Map between them so
  /// bindings created in Home replay here and vice-versa.
  static String _providerFromStored(String stored) =>
      stored == 'rd' ? 'debrid' : stored;
  static String storedProviderKey(String provider) =>
      provider == 'debrid' ? 'rd' : provider;

  /// Providers whose bound sources this isolated engine can replay — the five
  /// debrid providers plus 'local' (on-device file/folder).
  static bool _boundProviderSupported(String stored) {
    const supported = {
      'rd',
      'torbox',
      'premiumize',
      'alldebrid',
      'pikpak',
      SeriesSource.localService,
    };
    return supported.contains(stored);
  }

  /// Resolve a 'local' bound source (on-device movie file or series folder) into
  /// a playable [_Resolved]. Self-heals (removes) a source whose file/folder is
  /// gone. Returns (null, hint) when unavailable so the caller falls back to
  /// search — the hint (may be null) says why, using Home's exact wording.
  static Future<(_Resolved?, String?)> _resolveLocalBound(
    String imdbId,
    SeriesSource source,
    PlaybackMeta meta,
  ) async {
    final localPath = (source.localPath?.trim().isNotEmpty ?? false)
        ? source.localPath!.trim()
        : source.debridTorrentId.trim();
    if (localPath.isEmpty) return (null, null);

    final isSeries = meta.contentType == 'series' || source.isLocalSeriesFolder;
    if (isSeries) {
      if (meta.season == null || meta.episode == null) return (null, null);
      if (!await Directory(localPath).exists()) {
        await SeriesSourceService.removeSourceByHash(imdbId, source.torrentHash);
        return (
          null,
          'Saved local folder is no longer available. Falling back to search.'
        );
      }
      final episodes = await LocalBoundSourceService.scanSeriesFolder(localPath);
      if (episodes.isEmpty) {
        await SeriesSourceService.removeSourceByHash(imdbId, source.torrentHash);
        return (
          null,
          'Saved local folder has no playable episodes. Falling back to search.'
        );
      }
      final targetIndex = episodes.indexWhere(
          (e) => e.season == meta.season && e.episode == meta.episode);
      if (targetIndex < 0) {
        // Episode not in folder → search fallback.
        return (
          null,
          '${_seLabel(meta.season!, meta.episode!)} not found in local source. Falling back to search.'
        );
      }
      final playlist = episodes
          .map((e) => PlaylistEntry(
                url: Uri.file(e.file.path).toString(),
                title: e.relativePath,
                relativePath: e.relativePath,
                provider: SeriesSource.localService,
                sizeBytes: e.sizeBytes,
              ))
          .toList();
      return (
        _Resolved(
          title: source.torrentName,
          playUrl: playlist[targetIndex].url,
          playlist: playlist,
          startIndex: targetIndex,
        ),
        null
      );
    }

    // Movie / single local file.
    final file = File(localPath);
    final fileName = FileUtils.getFileName(localPath);
    if (!await file.exists() || !FileUtils.isVideoFile(fileName)) {
      await SeriesSourceService.removeSourceByHash(imdbId, source.torrentHash);
      return (
        null,
        'Saved local source is no longer available. Falling back to search.'
      );
    }
    final stat = await file.stat();
    final videoUrl = (source.localUri?.trim().isNotEmpty ?? false)
        ? source.localUri!.trim()
        : Uri.file(localPath).toString();
    final title =
        source.torrentName.trim().isNotEmpty ? source.torrentName : fileName;
    return (
      _Resolved(
        title: title,
        playUrl: videoUrl,
        playlist: [
          PlaylistEntry(
            url: videoUrl,
            title: title,
            provider: SeriesSource.localService,
            sizeBytes: stat.size,
          ),
        ],
        startIndex: 0,
      ),
      null
    );
  }

  /// "S04E01"-style label for bound-source hint messages.
  static String _seLabel(int season, int episode) =>
      'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';

  /// Whether the resolved add actually contains [season]/[episode] — the same
  /// SeriesParser filename check Home runs before launching a bound pack
  /// (_findEpisodeInFilenames). Without it, a binding that only covers earlier
  /// seasons still resolves fine and the player silently starts a different
  /// episode (last-played or S1E1) instead of falling back to search.
  ///
  /// Parses BASENAMES only — Home and the player's SeriesPlaylist both parse
  /// the filename, not the folder path; a folder segment like
  /// "Show.S04E01-E10.Pack/" would make this check disagree with the player.
  ///
  /// Errs toward playing: when the resolve exposes no real filename
  /// (single-file RD/PikPak, RAR archives) or nothing in the pack parses to a
  /// season/episode at all (absolute-numbered anime, "Episode 5" naming),
  /// trust the binding and let the player open it — rejecting those would
  /// regress packs that played fine before this check existed.
  /// The (season, episode) of a source whose name is exactly ONE specific
  /// episode, else null. STRICT — returns null for anything that could cover
  /// more than one episode (ranges "S01E01-E10", doubles "S01E01E02",
  /// multiple tokens, or non-singleEpisode coverage) so the [_playViaBound]
  /// cheap-skip below never drops a binding that genuinely contains the
  /// requested episode. When null, the source falls through to the normal
  /// resolve + [_resolvedHasEpisode] check (always correct, just not free).
  static (int, int)? _singleEpisodeOf(String name) {
    final normalized = name.replaceAll(RegExp(r'[._]+'), ' ');
    final matches = RegExp(r's(\d{1,2})e(\d{1,3})', caseSensitive: false)
        .allMatches(normalized)
        .toList();
    if (matches.length != 1) return null; // 0, or several distinct episodes
    // Reject anything that could span more than one episode. Kept greedy on
    // purpose: a false positive here just returns null (→ normal resolve,
    // always correct), whereas MISSING a range would wrongly skip a valid
    // multi-episode binding. Covers "E01-E10", "E01 to E10", "E01 & E02",
    // "E01,E02", and the adjacent double "E01E02".
    if (RegExp(r'e\d{1,3}\s*(?:-|–|to|thru|through|and|&|,)\s*e?\d{1,3}',
                caseSensitive: false)
            .hasMatch(normalized) ||
        RegExp(r'e\d{1,3}\s*e\d{1,3}', caseSensitive: false)
            .hasMatch(normalized)) {
      return null;
    }
    // Final cross-check against the coverage classifier.
    if (TorrentCoverageDetector.detectCoverage(title: name).coverageType !=
        CoverageType.singleEpisode) {
      return null;
    }
    final m = matches.first;
    final s = int.tryParse(m.group(1)!);
    final e = int.tryParse(m.group(2)!);
    if (s == null || e == null) return null;
    return (s, e);
  }

  static bool _resolvedHasEpisode(_Resolved r, int season, int episode) {
    final List<String> names;
    if (r.playlist != null && r.playlist!.length > 1) {
      names = r.playlist!.map((e) => _fileName(e.title)).toList();
    } else {
      // Single-file resolve: only RD/PikPak leave fileName unset (RD single
      // and RAR resolves carry just the torrent name, which isn't the file).
      final single = r.fileName ??
          ((r.playlist?.isNotEmpty ?? false) ? r.playlist!.first.title : null);
      if (single == null) return true; // no filename to judge → play
      names = <String>[_fileName(single)];
    }
    var sawEpisode = false;
    for (final info in SeriesParser.parsePlaylist(names)) {
      if (info.season == null || info.episode == null) continue;
      if (info.season == season && info.episode == episode) return true;
      sawEpisode = true;
    }
    return !sawEpisode;
  }

  /// Reconstruct a [Torrent] from a stored binding so it can flow through the
  /// normal add→resolve→launch pipeline (debrid dedup makes the re-add instant).
  static Torrent _torrentFromSource(SeriesSource s) => Torrent(
        rowid: 0,
        infohash: s.torrentHash,
        name: s.torrentName,
        sizeBytes: 0,
        createdUnix: 0,
        seeders: 0,
        leechers: 0,
        completed: 0,
        scrapedDate: 0,
        magnetUrl:
            'magnet:?xt=urn:btih:${s.torrentHash}&dn=${Uri.encodeComponent(s.torrentName)}',
        hasRealInfoHash: true,
      );

  /// Play a pinned source directly (no search). Tries each bound source in
  /// priority order; returns true once one plays. Self-heals a source that is
  /// confirmed dead/uncached (removes it) so the caller can fall back to search.
  static Future<bool> _playViaBound(
    BuildContext context,
    String imdbId,
    List<SeriesSource> sources, {
    required String label,
    required PlaybackMeta meta,
  }) async {
    final usable =
        sources.where((s) => _boundProviderSupported(s.debridService)).toList();
    if (usable.isEmpty) return false;

    final firstProv = _providerFromStored(usable.first.debridService);
    final usePoster = meta.posterUrl != null && meta.posterUrl!.isNotEmpty;
    final cancel = _PlaybackCancelToken();
    final rootNav = Navigator.of(context, rootNavigator: true);
    PosterPlayLoadingOverlay? overlay;
    if (usePoster) {
      overlay = PosterPlayLoadingOverlay.show(
        context,
        posterUrl: meta.posterUrl,
        title: label,
        provider: _label(firstProv),
        accentColor: _providerGradient(firstProv).first,
        icon: _providerIcon(firstProv),
        onCancel: () => cancel.cancelled = true,
      );
    } else {
      _showLoading(context, firstProv, label);
    }
    final shownOverlay = overlay;
    void closeLoading() {
      if (shownOverlay != null) {
        shownOverlay.dismiss();
      } else if (rootNav.canPop()) {
        rootNav.pop();
      }
    }

    // Series requests carry a concrete season+episode (gated by the caller);
    // movies leave them null and skip the episode-presence check.
    final season = meta.season;
    final episode = meta.episode;
    // Why the most recent source failed — shown once after the loop so the
    // user knows why playback fell back to a normal search (mirrors Home's
    // last-source hints in _tryPlayFromBoundSource*).
    String? fallbackHint;

    for (final source in usable) {
      if (cancel.cancelled) return true; // Cancel already dismissed the overlay.

      // Cheap skip: a bound DEBRID source whose name is a single specific
      // episode can only serve that episode — skip it (no debrid round-trip)
      // when a different episode is requested, so a series pinned only as
      // single episodes doesn't churn through every binding on each play.
      // Packs and ambiguous names fall through to the normal resolve + episode
      // check. Local sources are excluded: a series FOLDER resolves the
      // episode internally regardless of its name, and resolving is free.
      if (season != null &&
          episode != null &&
          source.debridService != SeriesSource.localService) {
        final se = _singleEpisodeOf(source.torrentName);
        if (se != null && (se.$1 != season || se.$2 != episode)) {
          continue;
        }
      }

      // Local (on-device file/folder) sources resolve without a debrid add.
      if (source.debridService == SeriesSource.localService) {
        final (r, hint) = await _resolveLocalBound(imdbId, source, meta);
        if (cancel.cancelled) return true;
        if (r != null) {
          closeLoading();
          if (!context.mounted) return false;
          await _launch(context, r, r.title,
              provider: SeriesSource.localService, meta: meta);
          return true;
        }
        if (!context.mounted) {
          closeLoading();
          return false;
        }
        // Always overwrite (even with null) so the hint reflects THIS
        // source's failure, never a stale one from an earlier attempt.
        fallbackHint = hint;
        continue; // unavailable / episode not found → try next source
      }

      final prov = _providerFromStored(source.debridService);
      final t = _torrentFromSource(source);
      _Resolved? res;
      // Default reason if this attempt fails without a more specific one
      // (no magnet, empty play URL, not-cached, transient error) — Home's
      // generic wording. Overwritten below when we know more.
      fallbackHint = 'Saved source is no longer available. Falling back to search.';
      try {
        final magnet = await _magnetFor(t);
        if (magnet == null) continue;
        if (cancel.cancelled) return true;
        final r = await _add(prov, magnet, t);
        if (r.playUrl != null && r.playUrl!.isNotEmpty) {
          if (season != null &&
              episode != null &&
              !_resolvedHasEpisode(r, season, episode)) {
            // Pack resolved fine but doesn't contain the requested episode
            // (e.g. an S1–S3 binding asked for S4E1) — skip it, matching
            // Home, instead of letting the player silently start a
            // different file. Keep the binding: it's still valid for the
            // seasons it covers.
            fallbackHint =
                '${_seLabel(season, episode)} not in saved sources. Use Edit Source to change them.';
            // RD's addMagnet / PikPak's addOfflineDownload created a fresh
            // account entry just for this attempt — delete it so repeated
            // fallbacks don't pile up orphans. TorBox/AllDebrid dedup the
            // add to an existing entry (deleting could break other bindings)
            // and Premiumize adds nothing, so those are left alone.
            if (prov == 'debrid' && (r.rdTorrentId?.isNotEmpty ?? false)) {
              try {
                final apiKey = (await StorageService.getApiKey()) ?? '';
                await DebridService.deleteTorrent(apiKey, r.rdTorrentId!);
              } catch (_) {}
            } else if (prov == 'pikpak' &&
                (r.pikpakFileId?.isNotEmpty ?? false)) {
              try {
                await PikPakApiService.instance
                    .batchDeleteFiles([r.pikpakFileId!]);
              } catch (_) {}
            }
          } else {
            res = r;
          }
        }
      } on TorrentNotCachedException catch (e) {
        // Bound RD source is no longer cached → self-heal and try the next.
        try {
          await DebridService.deleteTorrent(e.apiKey, e.torrentId);
        } catch (_) {}
        await SeriesSourceService.removeSourceByHash(imdbId, source.torrentHash);
      } on AllDebridTorrentNotReadyException catch (e) {
        // Transient (still resolving) — keep the binding, just fail this attempt.
        try {
          await AllDebridService.deleteMagnet(e.apiKey, e.magnetId);
        } catch (_) {}
        fallbackHint =
            'Saved source is not ready on AllDebrid. Falling back to search.';
      } catch (_) {
        // TorBox/Premiumize uncached or transient — keep binding, try next.
      }
      if (cancel.cancelled) return true;
      if (res != null) {
        closeLoading();
        if (!context.mounted) return false;
        await _launch(context, res, t.displayTitle,
            provider: prov, meta: meta, sources: [t], sourceIndex: 0);
        return true;
      }
      if (!context.mounted) {
        closeLoading();
        return false;
      }
    }
    closeLoading();
    // Mirror Home: say why bound playback failed before the caller falls back
    // to a normal search.
    if (fallbackHint != null && context.mounted) _snack(context, fallbackHint);
    return false;
  }

  /// Pin [torrent] as the playback source for [imdbId]. Adds it to the chosen
  /// provider first to confirm it's instantly playable (Home only binds cached
  /// sources); on success stores a [SeriesSource] — movies keep one, series
  /// accumulate a priority list. Returns true if bound.
  static Future<bool> bindSource(
    BuildContext context,
    Torrent torrent, {
    required String imdbId,
    required bool isMovie,
  }) async {
    if (imdbId.isEmpty) {
      _snack(context, 'No IMDb match — can\'t pin a source.');
      return false;
    }
    final provider = await _pickProvider(context);
    if (!context.mounted || provider == _cancelled) return false;
    if (provider == null) {
      _snack(context, 'No debrid provider configured. Add one in Settings.');
      return false;
    }
    // Capture the root navigator BEFORE showing the loader so we can always
    // dismiss it — even if the screen tears down during the await (otherwise the
    // barrier-less full-screen loader can get stuck covering the whole app).
    final rootNav = Navigator.of(context, rootNavigator: true);
    _showLoading(context, provider, torrent.name);
    _Resolved? res;
    String? failMessage;
    try {
      final magnet = await _magnetFor(torrent);
      if (magnet != null) {
        final r = await _add(provider, magnet, torrent);
        if (r.playUrl != null && r.playUrl!.isNotEmpty) res = r;
      }
    } on TorrentNotCachedException catch (e) {
      try {
        await DebridService.deleteTorrent(e.apiKey, e.torrentId);
      } catch (_) {}
    } on AllDebridTorrentNotReadyException catch (e) {
      try {
        await AllDebridService.deleteMagnet(e.apiKey, e.magnetId);
      } catch (_) {}
    } on _PikPakStillProcessing {
      // PikPak queued a download that isn't instantly playable — can't pin.
      failMessage =
          'Added to PikPak — it\'s still downloading. Pin it again once ready.';
    } on _PikPakFailed {
      failMessage = 'Download failed on PikPak.';
    } catch (_) {}
    // Pop the loader FIRST (using the captured navigator, no context), then
    // guard context use.
    if (rootNav.canPop()) rootNav.pop();
    if (!context.mounted) return false;
    if (res == null) {
      _snack(
          context,
          failMessage ??
              'That source isn\'t instantly playable on ${_label(provider)} — pick a cached one.');
      return false;
    }
    final source = SeriesSource(
      torrentHash: torrent.infohash,
      torrentName: torrent.name,
      debridService: storedProviderKey(provider),
      debridTorrentId: '',
      boundAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (isMovie) {
      await SeriesSourceService.setSources(imdbId, [source]);
    } else {
      await SeriesSourceService.addSource(imdbId, source);
    }
    if (context.mounted) _snack(context, 'Source pinned for instant playback.');
    return true;
  }

  /// Pin an ON-DEVICE file (movie) or folder (series) as [imdbId]'s source via
  /// the shared local picker. Desktop-only — the picker shows its own
  /// "unavailable on mobile" message on Android/iOS (matching Home). Returns
  /// true if a local source was pinned.
  static Future<bool> bindLocalSource(
    BuildContext context, {
    required String imdbId,
    required bool isMovie,
    required String title,
    String? year,
  }) async {
    if (imdbId.isEmpty) {
      _snack(context, 'No IMDb match — can\'t pin a source.');
      return false;
    }
    final SeriesSource? source;
    if (isMovie) {
      source = await LocalBoundSourceService.pickMovieSource(context,
          title: title, year: year);
    } else {
      source = await LocalBoundSourceService.pickSeriesSource(context,
          title: title);
    }
    if (source == null || !context.mounted) return false;
    if (isMovie) {
      await SeriesSourceService.setSources(imdbId, [source]);
    } else {
      await SeriesSourceService.addSource(imdbId, source);
    }
    if (context.mounted) _snack(context, 'Local source pinned.');
    return true;
  }

  /// Whether on-device local binding is available on this platform (false on
  /// Android/iOS). Lets the UI hide/adjust the local-pin affordance.
  static bool get localBindingAvailable =>
      !LocalBoundSourceService.isLocalBindingDisabled;

  // ── Per-provider add + resolve ─────────────────────────────────────────────

  static Future<_Resolved> _add(
    String provider,
    String magnet,
    Torrent torrent,
  ) async {
    final title = torrent.displayTitle;
    switch (provider) {
      case 'debrid':
        {
          final apiKey = (await StorageService.getApiKey()) ?? '';
          final result = await DebridService.addTorrentToDebrid(apiKey, magnet);
          final playUrl = result['downloadLink'] as String?;
          final linksRaw = (result['links'] as List?) ?? const [];
          final filesRaw = (result['files'] as List?) ?? const [];
          final links = linksRaw.map((e) => e.toString()).toList();
          // RD returns multiple selected files but a single link for an
          // unextracted RAR archive — the provider "open" view isn't useful then.
          final isRar = filesRaw.isNotEmpty
              ? RDFolderTreeBuilder.isRarArchive(
                  filesRaw.map((f) => f as Map<String, dynamic>).toList(),
                  linksRaw)
              : false;
          final rd = RDTorrent(
            id: result['torrentId']?.toString() ?? '',
            filename: title,
            hash: torrent.infohash,
            bytes: torrent.sizeBytes,
            host: '',
            split: 0,
            progress: 100,
            status: 'downloaded',
            added: DateTime.now().toIso8601String(),
            links: links,
          );
          void open() => MainPageBridge.openDebridOptions?.call(rd);
          final playlist = await _buildRdPlaylist(linksRaw, filesRaw, apiKey);
          if (playlist != null && playlist.length > 1) {
            var startIndex = playlist.indexWhere((e) => e.url.isNotEmpty);
            if (startIndex < 0) startIndex = 0;
            final start = playlist[startIndex].url.isNotEmpty
                ? playlist[startIndex].url
                : playUrl;
            return _Resolved(
              title: title,
              playUrl: start,
              downloadUrls: playUrl != null ? [playUrl] : const [],
              openInTab: open,
              playlist: playlist,
              startIndex: startIndex,
              isRarArchive: isRar,
              rdTorrentId: rd.id.isNotEmpty ? rd.id : null,
            );
          }
          return _Resolved(
            title: title,
            playUrl: playUrl,
            downloadUrls: playUrl != null ? [playUrl] : const [],
            openInTab: open,
            // Single video file: expose its real name so the bound-source
            // episode check can judge it (RAR resolves keep playlist null AND
            // fileName null, staying deliberately lenient).
            fileName: (playlist != null && playlist.length == 1)
                ? playlist.first.title
                : null,
            isRarArchive: isRar,
            rdTorrentId: rd.id.isNotEmpty ? rd.id : null,
            // Raw restricted link so a saved playlist item re-unrestricts later.
            restrictedLink: links.isNotEmpty ? links.first : null,
          );
        }
      case 'torbox':
        {
          final apiKey = (await StorageService.getTorboxApiKey()) ?? '';
          final resp = await TorboxService.createTorrent(
              apiKey: apiKey, magnet: magnet, addOnlyIfCached: true);
          final ok = resp['success'] == true ||
              resp['error'].toString().contains('ALREADY_ADDED');
          if (!ok) {
            if (resp['error'].toString().contains('NOT_CACHED')) {
              throw const _TorboxNotCached();
            }
            throw Exception(resp['error']?.toString() ?? 'TorBox add failed');
          }
          final data = resp['data'];
          final torrentId =
              data is Map ? (data['torrent_id'] as num?)?.toInt() : null;
          if (torrentId == null) throw Exception('TorBox: no torrent id');
          final tt = await TorboxService.getTorrentById(apiKey, torrentId);
          final open =
              tt == null ? null : () => MainPageBridge.openTorboxFolder?.call(tt);
          final videos = (tt?.files ?? const <TorboxFile>[])
              .where((f) => FileUtils.isVideoFile(f.name))
              .toList();
          if (videos.length <= 1) {
            final file = videos.isNotEmpty
                ? videos.first
                : _pickTorbox(tt?.files ?? const []);
            final playUrl = file == null
                ? null
                : await TorboxService.requestFileDownloadLink(
                    apiKey: apiKey, torrentId: torrentId, fileId: file.id);
            return _Resolved(
              title: title,
              playUrl: playUrl,
              downloadUrls: playUrl != null ? [playUrl] : const [],
              openInTab: open,
              fileName: file == null ? null : _fileName(file.name),
              torboxTorrentId: torrentId,
              // File id so a saved playlist item re-requests a fresh link later.
              torboxFileId: file?.id,
            );
          }
          final (sorted, startIndex) = _orderBySeries(videos, (f) => f.name);
          final startUrl = await TorboxService.requestFileDownloadLink(
              apiKey: apiKey, torrentId: torrentId, fileId: sorted[startIndex].id);
          final entries = [
            for (var i = 0; i < sorted.length; i++)
              PlaylistEntry(
                url: i == startIndex ? startUrl : '',
                title: _fileName(sorted[i].name),
                provider: 'torbox',
                torboxTorrentId: torrentId,
                torboxFileId: sorted[i].id,
                sizeBytes: sorted[i].size,
                torrentHash: torrent.infohash,
              ),
          ];
          return _Resolved(
            title: title,
            playUrl: startUrl,
            downloadUrls: [startUrl],
            openInTab: open,
            playlist: entries,
            startIndex: startIndex,
            torboxTorrentId: torrentId,
          );
        }
      case 'premiumize':
        {
          final apiKey = (await StorageService.getPremiumizeApiKey()) ?? '';
          if (!await PremiumizeService.isCached(apiKey, magnet)) {
            throw const _PremiumizeNotCached();
          }
          final files = await PremiumizeService.directDownload(apiKey, magnet);
          void open() => MainPageBridge.openPremiumizeFolder?.call();
          final videos =
              files.where((f) => FileUtils.isVideoFile(f.path)).toList();
          if (videos.length <= 1) {
            final file = videos.isNotEmpty ? videos.first : _pickPremiumize(files);
            return _Resolved(
              title: title,
              playUrl: file?.link,
              downloadUrls: file?.link != null ? [file!.link] : const [],
              openInTab: open,
              fileName: file == null ? null : _fileName(file.path),
              // File path so a saved playlist item re-resolves from the cloud.
              premiumizePath: file?.path,
            );
          }
          // Premiumize direct links are all ready — no lazy resolution needed.
          final (sorted, startIndex) = _orderBySeries(videos, (f) => f.path);
          final entries = [
            for (final f in sorted)
              PlaylistEntry(
                url: f.link,
                title: _fileName(f.path),
                provider: 'premiumize',
                premiumizeHash: torrent.infohash,
                premiumizePath: f.path,
                sizeBytes: f.size,
                torrentHash: torrent.infohash,
              ),
          ];
          return _Resolved(
            title: title,
            playUrl: sorted[startIndex].link,
            downloadUrls: [sorted[startIndex].link],
            openInTab: open,
            playlist: entries,
            startIndex: startIndex,
          );
        }
      case 'alldebrid':
        {
          final apiKey = (await StorageService.getAllDebridApiKey()) ?? '';
          final result =
              await AllDebridService.addMagnetAndResolveFiles(apiKey, magnet);
          void open() => MainPageBridge.openAllDebridFolder?.call();
          final videos =
              result.files.where((f) => FileUtils.isVideoFile(f.path)).toList();
          if (videos.length <= 1) {
            final file =
                videos.isNotEmpty ? videos.first : _pickAllDebrid(result.files);
            final playUrl = file == null
                ? null
                : await AllDebridService.unlockLink(apiKey, file.link);
            return _Resolved(
              title: title,
              playUrl: playUrl,
              downloadUrls: playUrl != null ? [playUrl] : const [],
              openInTab: open,
              fileName: file == null ? null : _fileName(file.path),
              // Locked link so a saved playlist item re-unlocks a fresh URL.
              allDebridLink: file?.link,
            );
          }
          final (sorted, startIndex) = _orderBySeries(videos, (f) => f.path);
          final startUrl =
              await AllDebridService.unlockLink(apiKey, sorted[startIndex].link);
          final entries = [
            for (var i = 0; i < sorted.length; i++)
              PlaylistEntry(
                url: i == startIndex ? startUrl : '',
                title: _fileName(sorted[i].path),
                provider: 'alldebrid',
                allDebridLink: sorted[i].link,
                sizeBytes: sorted[i].size,
                torrentHash: torrent.infohash,
              ),
          ];
          return _Resolved(
            title: title,
            playUrl: startUrl,
            downloadUrls: [startUrl],
            openInTab: open,
            playlist: entries,
            startIndex: startIndex,
          );
        }
      case 'pikpak':
        return _addPikPak(magnet, torrent);
      default:
        throw Exception('Unknown provider: $provider');
    }
  }

  // ── Post-action branch handlers ────────────────────────────────────────────

  static Future<void> _play(
    BuildContext context,
    _Resolved r,
    Torrent torrent, {
    required String provider,
    PlaybackMeta? meta,
    List<Torrent>? sources,
    int sourceIndex = 0,
  }) async {
    if (r.playUrl == null || r.playUrl!.isEmpty) {
      _snack(context, 'No playable link for this source.');
      return;
    }
    // Refuse a resolved single file that clearly isn't a video (parity with the
    // old screen's MIME check). Scoped to KEYWORD play (meta == null) so this
    // shared path doesn't add a new constraint to catalog board plays. Only
    // fires when we know the real filename; packs are video-filtered upstream.
    if (meta == null &&
        !r.hasPlaylist &&
        r.fileName != null &&
        r.fileName!.isNotEmpty &&
        !FileUtils.isVideoFile(r.fileName!)) {
      _snack(context,
          'Added to ${_label(provider)}, but the file is not a video.');
      return;
    }
    // For keyword play (no catalog meta) prefer the provider's canonical file
    // name as the title, so the player's resume/Continue-Watching key matches
    // the same item played from the Debrid screen (old-screen parity). Catalog
    // play keeps its clean meta title.
    final playTitle = (meta == null &&
            !r.hasPlaylist &&
            r.fileName != null &&
            r.fileName!.isNotEmpty)
        ? r.fileName!
        : torrent.displayTitle;
    await _launch(
      context,
      r,
      playTitle,
      provider: provider,
      meta: meta,
      sources: sources ?? [torrent],
      sourceIndex: sourceIndex,
    );
  }

  /// Player "Next Episode" hand-back (matching Home's _quickPlayNextCallback):
  /// when a series playback runs out of playlist items and the user taps Next,
  /// both players hand the next episode back to the host — the Flutter player
  /// pops with a quickPlayNext payload and the Android TV activity requests it
  /// over the bridge (VideoPlayerLauncher resolves both to the same callback).
  /// Without this callback the launcher drops the request and the player just
  /// closes.
  ///
  /// [provider] is the debrid provider the CURRENT episode played with (null
  /// for direct addon streams and local bound sources) — the advance reuses it
  /// so a binge never re-prompts the provider picker mid-chain.
  static Future<void> Function(Map<String, dynamic>)? _nextEpisodeHandlerFor(
    BuildContext context,
    PlaybackMeta? meta, {
    String? provider,
  }) {
    final imdbId = meta?.imdbId;
    if (meta == null ||
        meta.contentType != 'series' ||
        imdbId == null ||
        imdbId.isEmpty) {
      return null;
    }
    return (Map<String, dynamic> result) async {
      // Both players already resolved WHICH episode comes next (via
      // NextEpisodeService) — the payload names it directly.
      final season = result['season'] as int?;
      final episode = result['episode'] as int?;
      if (season == null || episode == null) return;
      final nextMeta = PlaybackMeta(
        imdbId: imdbId,
        contentType: 'series',
        season: season,
        episode: episode,
        title: meta.title,
        posterUrl: meta.posterUrl,
        year: meta.year,
        addonId: meta.addonId,
        // Keep scrobbling across the binge — a Trakt-row play must not stop
        // updating Trakt (and start saving duplicate local Continue Watching
        // entries) from episode 2 onward. Home drops this and goes stale
        // mid-binge; deliberately better here. traktProgressPercent IS
        // dropped: the next episode starts fresh, not at the previous
        // episode's resume point.
        traktScrobble: meta.traktScrobble,
      );
      // Defer one frame (matching Home's addPostFrameCallback) so the previous
      // episode's entire play chain unwinds before the next one starts — an
      // awaited re-entry would nest one full search+play chain per episode,
      // retaining every prior episode's scopes across a binge.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        unawaited(_advanceToNextEpisode(
          context,
          imdbId: imdbId,
          meta: nextMeta,
          provider: provider,
        ));
      });
    };
  }

  /// Play the next episode of a binge. Provider-backed playbacks re-enter
  /// [playFromSelection] with the provider the previous episode used; direct
  /// addon-stream / local playbacks (no debrid provider) replay bound sources
  /// first, then the addon-stream flow — which plays direct streams without a
  /// provider, i.e. the same path that produced the episode being advanced.
  static Future<void> _advanceToNextEpisode(
    BuildContext context, {
    required String imdbId,
    required PlaybackMeta meta,
    String? provider,
  }) async {
    final label = meta.title ?? '';
    if (provider != null) {
      await playFromSelection(
        context,
        imdbId: imdbId,
        isMovie: false,
        season: meta.season,
        episode: meta.episode,
        meta: meta,
        preferredProvider: provider,
      );
      return;
    }
    final bound = await SeriesSourceService.getSources(imdbId);
    if (!context.mounted) return;
    if (bound.isNotEmpty && meta.season != null && meta.episode != null) {
      final played =
          await _playViaBound(context, imdbId, bound, label: label, meta: meta);
      if (played) return;
      if (!context.mounted) return;
    }
    await _playAddonStream(
      context,
      imdbId,
      isMovie: false,
      season: meta.season,
      episode: meta.episode,
      meta: meta,
      label: label,
    );
  }

  /// Shared meta → player-args plumbing. ONE place builds the content-identity
  /// fields for every push site — a field missed at a single site would
  /// silently break Continue Watching / scrobble / Next Episode for that entry
  /// path only.
  static VideoPlayerLaunchArgs _playerArgs({
    required String videoUrl,
    required String title,
    String? subtitle,
    List<PlaylistEntry>? playlist,
    int? startIndex,
    List<Torrent>? stremioSources,
    int? stremioCurrentSourceIndex,
    Future<List<PlaylistEntry>?> Function(Torrent)? resolveSourceToPlaylist,
    PlaybackMeta? meta,
    String? rdTorrentId,
    int? torboxTorrentId,
    PlaylistViewMode? viewMode,
  }) =>
      VideoPlayerLaunchArgs(
        videoUrl: videoUrl,
        title: title,
        subtitle: subtitle,
        playlist: playlist,
        startIndex: startIndex,
        viewMode: viewMode,
        stremioSources: stremioSources,
        stremioCurrentSourceIndex: stremioCurrentSourceIndex,
        resolveSourceToPlaylist: resolveSourceToPlaylist,
        contentImdbId: meta?.imdbId,
        contentType: meta?.contentType,
        contentSeason: meta?.season,
        contentEpisode: meta?.episode,
        contentTitle: meta?.title,
        posterUrl: meta?.posterUrl,
        contentYear: meta?.year,
        addonId: meta?.addonId,
        traktScrobble: meta?.traktScrobble ?? false,
        traktProgressPercent: meta?.traktProgressPercent,
        // Debrid torrent ids let the player back-fill poster/IMDb onto a saved
        // Playlist-library entry and power the in-player "Fix Metadata" action
        // (matching Home). PikPak is intentionally omitted: the launcher wants a
        // collection/folder id, but _Resolved only carries a per-file id.
        rdTorrentId: rdTorrentId,
        torboxTorrentId: torboxTorrentId?.toString(),
      );

  /// Providers with credentials configured (in this service's precedence
  /// order) plus the user's saved default when it's still configured — the
  /// single source of truth shared by [_pickProvider] and
  /// [_defaultConfiguredProvider], so adding a provider is a one-list edit.
  static Future<(List<String>, String?)> _configuredProviders() async {
    final configured = <String>[];
    for (final p in ['debrid', 'torbox', 'premiumize', 'alldebrid', 'pikpak']) {
      if (await _isConfigured(p)) configured.add(p);
    }
    if (configured.isEmpty) return (configured, null);
    final def = await StorageService.getDefaultTorrentProvider();
    final defaultProvider =
        (def != 'none' && configured.contains(def)) ? def : null;
    return (configured, defaultProvider);
  }

  /// The provider a silent (no-dialog) resolution should use: the configured
  /// default, else the first configured one, else null. Uses this service's
  /// _pickProvider precedence (Premiumize before PikPak) — deliberately NOT
  /// Home's resolver order, which prefers PikPak; a silent PikPak fallback
  /// would queue real downloads on the account.
  static Future<String?> _defaultConfiguredProvider() async {
    final (configured, def) = await _configuredProviders();
    if (configured.isEmpty) return null;
    return def ?? configured.first;
  }

  /// In-player Sources-switcher resolver for launches that didn't go through a
  /// debrid provider (direct addon streams). Direct streams resolve without
  /// one; a torrent switch silently uses the default/first-configured provider
  /// (matching Home's _createSourcePlaylistResolver) and fails gracefully
  /// (null) when none is configured.
  static Future<List<PlaylistEntry>?> Function(Torrent) _lazyProviderResolver() {
    return (Torrent t) async {
      if (t.streamType == StreamType.directUrl &&
          (t.directUrl?.isNotEmpty ?? false)) {
        return [PlaylistEntry(url: t.directUrl!, title: t.displayTitle)];
      }
      final provider = await _defaultConfiguredProvider();
      if (provider == null) return null;
      return _resolverFor(provider)(t);
    };
  }

  /// Old-screen parity: playing a catalog MOVIE remembers the just-played
  /// torrent as that title's single bound source (override), so the catalog
  /// flips "Select Source" → "Edit Source" and the next play reuses it. Series
  /// never auto-bind (they accumulate an explicit priority list via "Pin as
  /// source"); keyword play (meta == null) and non-IMDb / on-device plays don't
  /// bind either. Best-effort — a storage hiccup must never break playback.
  static Future<void> _autoBindMovieOnPlay(
    PlaybackMeta? meta,
    Torrent? winner,
    String provider,
  ) async {
    if (meta == null ||
        meta.contentType != 'movie' ||
        meta.imdbId == null ||
        meta.imdbId!.isEmpty ||
        winner == null ||
        winner.infohash.isEmpty ||
        provider == SeriesSource.localService) {
      return;
    }
    try {
      await SeriesSourceService.setSources(meta.imdbId!, [
        SeriesSource(
          torrentHash: winner.infohash,
          torrentName: winner.name,
          debridService: storedProviderKey(provider),
          debridTorrentId: '',
          boundAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ]);
    } catch (_) {}
  }

  /// Series counterpart of [_autoBindMovieOnPlay] (on by default via the
  /// series auto-pin setting): pin whatever torrent a series play resolved to
  /// — a pack from the pack-first search or a single episode from the fallback
  /// — so subsequent plays go straight through the bound path. A same-hash
  /// binding is refreshed in place (keeps its priority); a new single-episode
  /// binding is capped so a pack-less show binged over time can't grow the
  /// list without bound (older singles are evicted; packs and manually-pinned
  /// sources are never touched). Never binds addon direct streams or local
  /// sources.
  static const int _maxAutoBoundSingles = 20;

  static Future<void> _autoBindSeriesOnPlay(
    PlaybackMeta? meta,
    Torrent? winner,
    String provider,
  ) async {
    // Any non-movie episode play (contentType 'series' or a custom series-like
    // type such as anime) — movies are handled by _autoBindMovieOnPlay.
    // Scoped to episode plays (season+episode set) to match the pack-first
    // gate and skip whole-series/no-episode plays.
    if (meta == null ||
        meta.contentType == 'movie' ||
        meta.imdbId == null ||
        meta.imdbId!.isEmpty ||
        meta.season == null ||
        meta.episode == null ||
        winner == null ||
        winner.infohash.isEmpty ||
        winner.streamType != StreamType.torrent ||
        provider == SeriesSource.localService ||
        // Consistent with the pack-first block: the whole auto-pin feature is
        // off for PikPak (its bindings re-queue real downloads on each replay),
        // so a stale-true pref after switching default to PikPak stays inert.
        provider == 'pikpak') {
      return;
    }
    try {
      if (!await StorageService.getAutoBindSeriesPacksOnPlay()) return;
      final imdbId = meta.imdbId!;
      final source = SeriesSource(
        torrentHash: winner.infohash,
        torrentName: winner.name,
        debridService: storedProviderKey(provider),
        debridTorrentId: '',
        boundAt: DateTime.now().millisecondsSinceEpoch,
      );
      final list = List<SeriesSource>.from(
        await SeriesSourceService.getSources(imdbId),
      );
      final existingIdx =
          list.indexWhere((s) => s.torrentHash == source.torrentHash);
      if (existingIdx >= 0) {
        // Same source replayed — refresh in place, keep priority.
        list[existingIdx] = source;
      } else {
        // A NEW single-episode binding: bound how many auto-accumulate so a
        // pack-less show doesn't grow the list forever. Packs and any
        // non-single (e.g. manually pinned) sources are never evicted.
        if (_singleEpisodeOf(source.torrentName) != null) {
          final singles = list
              .where((s) => _singleEpisodeOf(s.torrentName) != null)
              .toList()
            ..sort((a, b) => a.boundAt.compareTo(b.boundAt));
          final overflow = singles.length + 1 - _maxAutoBoundSingles;
          if (overflow > 0) {
            final drop =
                singles.take(overflow).map((s) => s.torrentHash).toSet();
            list.removeWhere((s) => drop.contains(s.torrentHash));
          }
        }
        list.add(source);
      }
      await SeriesSourceService.setSources(imdbId, list);
    } catch (_) {}
  }

  /// Launch the player. Passes the full source list + a resolver (so the player
  /// shows the in-player "Sources" switcher) and content metadata (so Continue
  /// Watching, subtitles and the Episodes button work) — matching Home.
  static Future<void> _launch(
    BuildContext context,
    _Resolved r,
    String title, {
    required String provider,
    PlaybackMeta? meta,
    List<Torrent>? sources,
    int sourceIndex = 0,
  }) async {
    // Secondary metadata line (file size / source / file count), matching Home.
    final winner = (sources != null &&
            sourceIndex >= 0 &&
            sourceIndex < sources.length)
        ? sources[sourceIndex]
        : null;
    String? subtitleLine;
    if (r.hasPlaylist) {
      subtitleLine = '${r.playlist!.length} files';
    } else if (winner != null) {
      subtitleLine = winner.sizeBytes > 0
          ? Formatters.formatFileSize(winner.sizeBytes)
          : (winner.source.isNotEmpty ? winner.source : null);
    }
    // Organize the playlist as a TV series when the file names look like one, so
    // a keyword-launched season pack groups by season/episode and "next" walks
    // episode order — parity with the old screen. Scoped to KEYWORD play
    // (meta == null): catalog already drives series/movie view from its own
    // contentType, so this shared launcher must not override that. We pass
    // `series` only when detected and leave it null otherwise (null lets the
    // launcher's contentType fallback win).
    final PlaylistViewMode? viewMode =
        (meta == null && r.hasPlaylist && _isSeriesPlaylist(r.playlist!))
            ? PlaylistViewMode.series
            : null;
    // VR hand-off (parity with the old search screen): for a single video file
    // played from KEYWORD search (meta == null), when the user's VR mode says
    // so, play in DeoVR instead of the in-app player. Scoped to keyword so this
    // shared launcher doesn't newly divert catalog board plays. Packs keep the
    // normal player (DeoVR takes one video).
    if (meta == null && !r.hasPlaylist && await _shouldUseDeoVR(title)) {
      if (!context.mounted) return;
      await _launchWithDeoVR(context, videoUrl: r.playUrl!, filename: title);
      return;
    }
    // Remember a catalog movie's source before handing off to the player, so the
    // binding is saved even if the screen tears down during playback. The series
    // counterpart is gated by the series auto-pin setting (on by default).
    await _autoBindMovieOnPlay(meta, winner, provider);
    await _autoBindSeriesOnPlay(meta, winner, provider);
    if (!context.mounted) return;
    await VideoPlayerLauncher.push(
      context,
      _playerArgs(
        videoUrl: r.playUrl!,
        title: title,
        subtitle: subtitleLine,
        playlist: r.hasPlaylist ? r.playlist : null,
        startIndex: r.hasPlaylist ? r.startIndex : null,
        stremioSources: sources,
        stremioCurrentSourceIndex: sources != null ? sourceIndex : null,
        resolveSourceToPlaylist: (sources != null && sources.length > 1)
            ? _switchAwareResolver(provider, meta)
            : null,
        meta: meta,
        rdTorrentId: r.rdTorrentId,
        torboxTorrentId: r.torboxTorrentId,
        viewMode: viewMode,
      ),
      // 'local' isn't a debrid provider the advance could search with — the
      // null makes the advance replay bound sources first, then addon streams.
      onQuickPlayNextEpisode: _nextEpisodeHandlerFor(context, meta,
          provider:
              provider == SeriesSource.localService ? null : provider),
    );
  }

  /// Whether VR playback (DeoVR) should be used for [filename], per the user's
  /// VR-mode setting. Android-only. Ported from the old search screen.
  static Future<bool> _shouldUseDeoVR(String filename) async {
    if (!Platform.isAndroid) return false;
    final vrMode = await StorageService.getQuickPlayVrMode();
    switch (vrMode) {
      case 'always':
        return true;
      case 'auto':
        return deovr.isVrContent(filename);
      case 'disabled':
      default:
        return false;
    }
  }

  /// Hand a single video file off to DeoVR: pick a screen/stereo format (auto
  /// from the filename or the user's defaults, optionally confirmed via a
  /// dialog), upload a DeoVR JSON descriptor to jsonblob, then launch the
  /// `deovr://` intent. Ported verbatim from the old search screen.
  static Future<void> _launchWithDeoVR(
    BuildContext context, {
    required String videoUrl,
    required String filename,
  }) async {
    if (!Platform.isAndroid) return;
    // Capture the root navigator while context is synchronously valid, so the
    // loading overlay can always be dismissed even if the widget unmounts during
    // the awaited upload below.
    final rootNav = Navigator.of(context, rootNavigator: true);

    final autoDetectFormat =
        await StorageService.getQuickPlayVrAutoDetectFormat();
    final showFormatDialog = await StorageService.getQuickPlayVrShowDialog();

    String screenType;
    String stereoMode;
    if (autoDetectFormat) {
      final detected = deovr.detectVRFormat(filename);
      screenType = detected.screenType;
      stereoMode = detected.stereoMode;
    } else {
      screenType = await StorageService.getQuickPlayVrDefaultScreenType();
      stereoMode = await StorageService.getQuickPlayVrDefaultStereoMode();
    }

    if (showFormatDialog && context.mounted) {
      String selectedScreenType = screenType;
      String selectedStereoMode = stereoMode;
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('DeoVR Format'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filename,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                const Text('Screen Type',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedScreenType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: deovr.screenTypeLabels.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedScreenType = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                const Text('Stereo Mode',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedStereoMode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: deovr.stereoModeLabels.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedStereoMode = value);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  DialogTapGuard.markKeyAction();
                  Navigator.of(context).pop(false);
                },
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () {
                  DialogTapGuard.markKeyAction();
                  Navigator.of(context).pop(true);
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
            ],
          ),
        ),
      );
      if (result != true || !context.mounted) return;
      screenType = selectedScreenType;
      stereoMode = selectedStereoMode;
    }

    // Tracks whether the blocking loading dialog is still on screen, so the
    // catch below never pops the underlying screen after we've already
    // dismissed the dialog (e.g. a failed `intent.launch()` when DeoVR isn't
    // installed would otherwise bounce the user back a screen).
    bool loadingShown = false;
    try {
      if (context.mounted) {
        loadingShown = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );
      }

      final json = deovr.generateDeoVRJson(
        videoUrl: videoUrl,
        title: filename,
        screenType: screenType,
        stereoMode: stereoMode,
      );
      final response = await http.post(
        Uri.parse('https://jsonblob.com/api/jsonBlob'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(json),
      );
      if (response.statusCode != 201) {
        throw Exception('Failed to upload JSON: ${response.statusCode}');
      }
      final location = response.headers['location'];
      if (location == null) {
        throw Exception('No location header in response');
      }
      final jsonUrl = 'https://jsonblob.com$location';

      if (loadingShown) {
        rootNav.pop();
        loadingShown = false;
      }

      final intent =
          AndroidIntent(action: 'action_view', data: 'deovr://$jsonUrl');
      await intent.launch();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Launching DeoVR...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (loadingShown) rootNav.pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open with DeoVR: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Builds the in-player source-switch resolver: given another [Torrent] the
  /// user picked, add it to [provider] and return its playlist (so switching
  /// sources works without leaving the player).
  static Future<List<PlaylistEntry>?> Function(Torrent) _resolverFor(
      String provider) {
    return (Torrent t) async {
      if (t.streamType == StreamType.directUrl &&
          (t.directUrl?.isNotEmpty ?? false)) {
        return [PlaylistEntry(url: t.directUrl!, title: t.displayTitle)];
      }
      final magnet = await _magnetFor(t);
      if (magnet == null) return null;
      try {
        final r = await _add(provider, magnet, t);
        if (r.playlist != null && r.playlist!.isNotEmpty) return r.playlist;
        if (r.playUrl != null && r.playUrl!.isNotEmpty) {
          return [PlaylistEntry(url: r.playUrl!, title: t.displayTitle)];
        }
      } catch (_) {}
      return null;
    };
  }

  /// [_resolverFor] wrapped so that a SUCCESSFUL in-player source switch also
  /// updates the series' pinned source (see [_rebindOnSourceSwitch]). Both
  /// players (Flutter + native TV) funnel every switch through this one
  /// closure, so wrapping it here keeps the binding in sync on both.
  static Future<List<PlaylistEntry>?> Function(Torrent) _switchAwareResolver(
      String provider, PlaybackMeta? meta) {
    final inner = _resolverFor(provider);
    return (Torrent t) async {
      final playlist = await inner(t);
      if (playlist != null && playlist.isNotEmpty) {
        await _rebindOnSourceSwitch(meta, t, provider);
      }
      return playlist;
    };
  }

  /// Keep a series' pinned source in sync when the user switches sources in
  /// the player: the chosen [switched] source becomes the primary binding,
  /// replacing the one being switched away from (so the next play uses what
  /// the user actually picked). Only syncs a series that ALREADY has a binding
  /// — never creates one from a switch — and skips movies, non-torrent /
  /// PikPak / local sources, and re-selecting the current source keeps the
  /// rest of the list intact.
  static Future<void> _rebindOnSourceSwitch(
    PlaybackMeta? meta,
    Torrent switched,
    String provider,
  ) async {
    if (meta == null ||
        meta.contentType == 'movie' ||
        meta.imdbId == null ||
        meta.imdbId!.isEmpty ||
        meta.season == null ||
        meta.episode == null ||
        switched.infohash.isEmpty ||
        switched.streamType != StreamType.torrent ||
        provider == SeriesSource.localService ||
        provider == 'pikpak') {
      return;
    }
    try {
      final imdbId = meta.imdbId!;
      final existing = await SeriesSourceService.getSources(imdbId);
      // Only keep an existing binding in sync; never create one from a switch.
      if (existing.isEmpty) return;
      final source = SeriesSource(
        torrentHash: switched.infohash,
        torrentName: switched.name,
        debridService: storedProviderKey(provider),
        debridTorrentId: '',
        boundAt: DateTime.now().millisecondsSinceEpoch,
      );
      final currentPrimaryHash = existing.first.torrentHash;
      final list = List<SeriesSource>.from(existing)
        ..removeWhere((s) => s.torrentHash == source.torrentHash);
      // Drop the source being switched away from (the previous primary), but
      // not when the user re-selected the source that's already primary.
      if (currentPrimaryHash != source.torrentHash && list.isNotEmpty) {
        list.removeAt(0);
      }
      list.insert(0, source);
      await SeriesSourceService.setSources(imdbId, list);
    } catch (_) {}
  }

  /// Download a direct/external addon stream to device (parity with the old
  /// screen's direct-stream "Download to device" action). Follows redirects
  /// first — MediaFusion-style playback URLs 30x-hop to the real file — then
  /// queues the resolved URL.
  static Future<void> downloadDirectStream(
      BuildContext context, Torrent torrent) async {
    final raw = torrent.directUrl ?? '';
    if (raw.isEmpty) {
      _snack(context, 'No stream URL available.');
      return;
    }
    _snack(context, 'Resolving download URL…');
    final resolved = await _resolveDownloadUrl(raw);
    try {
      await DownloadService.instance.enqueueDownload(
        url: resolved,
        fileName: torrent.displayTitle,
        torrentName: torrent.displayTitle,
      );
      if (context.mounted) _snack(context, 'Download queued.');
    } catch (_) {
      if (context.mounted) _snack(context, 'Failed to queue download.');
    }
  }

  /// Follow up to 10 redirects (HEAD, no auto-follow) to resolve a stream URL to
  /// its final downloadable location, handling relative Location headers. Ported
  /// from the old screen's `_resolveDownloadUrl`.
  static Future<String> _resolveDownloadUrl(String url) async {
    var currentUrl = url;
    var redirectCount = 0;
    while (redirectCount < 10) {
      try {
        final uri = Uri.parse(currentUrl);
        final client = http.Client();
        try {
          final request = http.Request('HEAD', uri);
          request.followRedirects = false;
          request.headers['User-Agent'] =
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
          final response =
              await client.send(request).timeout(const Duration(seconds: 10));
          if (response.statusCode == 301 ||
              response.statusCode == 302 ||
              response.statusCode == 303 ||
              response.statusCode == 307 ||
              response.statusCode == 308) {
            final location = response.headers['location'];
            if (location != null && location.isNotEmpty) {
              currentUrl = uri.resolve(location).toString();
              redirectCount++;
              continue;
            }
          }
          return currentUrl; // no redirect → final URL
        } finally {
          client.close();
        }
      } catch (_) {
        break;
      }
    }
    return currentUrl; // best effort (possibly partially resolved)
  }

  /// Resolve a playlist entry to a concrete download URL, unlocking a lazy
  /// debrid entry on demand: RD `restrictedLink` → unrestrict, TorBox
  /// torrent+file id → download link, AllDebrid locked link → unlock. Premiumize
  /// entries already carry a URL. Returns null if it can't be resolved.
  static Future<String?> _resolveEntryUrl(PlaylistEntry e) async {
    if (e.url.isNotEmpty) return e.url;
    try {
      if (e.restrictedLink != null && e.restrictedLink!.isNotEmpty) {
        final key = (await StorageService.getApiKey()) ?? '';
        final r = await DebridService.unrestrictLink(key, e.restrictedLink!);
        return r['download']?.toString();
      }
      if (e.torboxTorrentId != null && e.torboxFileId != null) {
        final key = (await StorageService.getTorboxApiKey()) ?? '';
        return await TorboxService.requestFileDownloadLink(
            apiKey: key, torrentId: e.torboxTorrentId!, fileId: e.torboxFileId!);
      }
      if (e.allDebridLink != null && e.allDebridLink!.isNotEmpty) {
        final key = (await StorageService.getAllDebridApiKey()) ?? '';
        return await AllDebridService.unlockLink(key, e.allDebridLink!);
      }
    } catch (_) {}
    return null;
  }

  /// Multi-select download picker (parity with the old per-file download
  /// dialog): lists the pack's files with sizes, defaults all selected, shows a
  /// running total, and returns the chosen entries — or null if cancelled.
  static Future<List<PlaylistEntry>?> _showDownloadPicker(
      BuildContext context, List<PlaylistEntry> entries) {
    return showDialog<List<PlaylistEntry>>(
      context: context,
      builder: (dialogCtx) {
        final scheme = Theme.of(dialogCtx).colorScheme;
        final selected = {...entries}; // default: all selected
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final totalBytes = selected.fold<int>(
                0, (sum, e) => sum + (e.sizeBytes ?? 0));
            final allOn = selected.length == entries.length;
            return AlertDialog(
              title: const Text('Download files'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setLocal(() {
                          if (allOn) {
                            selected.clear();
                          } else {
                            selected
                              ..clear()
                              ..addAll(entries);
                          }
                        }),
                        child: Text(allOn ? 'None' : 'All'),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final e in entries)
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                              value: selected.contains(e),
                              title: Text(e.title,
                                  style: TextStyle(
                                      fontSize: 13, color: scheme.onSurface),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              secondary: Text(
                                (e.sizeBytes ?? 0) > 0
                                    ? Formatters.formatFileSize(e.sizeBytes!)
                                    : '',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant),
                              ),
                              onChanged: (_) => setLocal(() {
                                if (selected.contains(e)) {
                                  selected.remove(e);
                                } else {
                                  selected.add(e);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.of(dialogCtx)
                          .pop(entries.where(selected.contains).toList()),
                  child: Text(totalBytes > 0
                      ? 'Download · ${Formatters.formatFileSize(totalBytes)}'
                      : 'Download'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Future<void> _download(
      BuildContext context, _Resolved r, Torrent torrent) async {
    // Multi-file pack: let the user choose which files (parity with the old
    // per-file download dialog), then queue each — unlocking lazy debrid entries
    // on demand (RD/TorBox/AllDebrid resolve only the start file up front;
    // Premiumize resolves all).
    if (r.playlist != null && r.playlist!.length > 1) {
      final chosen = await _showDownloadPicker(context, r.playlist!);
      if (chosen == null || chosen.isEmpty) return; // cancelled
      var n = 0;
      for (final e in chosen) {
        final url = await _resolveEntryUrl(e);
        if (url == null || url.isEmpty) continue;
        try {
          await DownloadService.instance.enqueueDownload(
            url: url,
            fileName: e.title,
            torrentName: torrent.displayTitle,
          );
          n++;
        } catch (_) {}
      }
      if (context.mounted) {
        _snack(context,
            n > 0 ? 'Queued $n file(s) for download.' : 'Could not queue downloads.');
      }
      return;
    }
    if (r.playlist != null && r.playlist!.isNotEmpty) {
      // Single-entry playlist: queue it directly (no picker for one file).
      final url = await _resolveEntryUrl(r.playlist!.first);
      var queued = false;
      if (url != null && url.isNotEmpty) {
        try {
          await DownloadService.instance.enqueueDownload(
            url: url,
            fileName: r.playlist!.first.title,
            torrentName: torrent.displayTitle,
          );
          queued = true;
        } catch (_) {}
      }
      if (context.mounted) {
        _snack(context,
            queued ? 'Download queued.' : 'Could not queue download.');
      }
      return;
    }
    final url = r.downloadUrls.isNotEmpty ? r.downloadUrls.first : null;
    if (url == null) {
      _snack(context, 'Nothing to download for this source.');
      return;
    }
    try {
      await DownloadService.instance.enqueueDownload(
        url: url,
        fileName: r.fileName ?? torrent.displayTitle,
        torrentName: torrent.displayTitle,
      );
    } catch (_) {}
    if (context.mounted) _snack(context, 'Download queued.');
  }

  static Future<void> _addToPlaylist(BuildContext context, _Resolved r,
      Torrent torrent, String provider,
      {PlaybackMeta? meta}) async {
    final isPack = r.hasPlaylist;
    final rawTitle =
        (!isPack && r.fileName != null) ? r.fileName! : torrent.displayTitle;
    // Base fields shared by every provider. NOTE: no 'url' is stored — the
    // playlist player RE-RESOLVES a fresh link from the provider-native ids
    // below, so saved items keep working after the debrid direct link expires
    // (parity with the old per-provider playlist schema).
    final item = <String, dynamic>{
      'provider': provider == 'debrid' ? 'realdebrid' : provider,
      'title': FileUtils.cleanPlaylistTitle(rawTitle),
      'kind': isPack ? 'collection' : 'single',
      'torrent_hash': torrent.infohash,
      if (isPack) 'count': r.playlist!.length,
      if (torrent.sizeBytes > 0) 'sizeBytes': torrent.sizeBytes,
      // Catalog identity so the playlist shows poster art + links back (Home).
      if (meta?.imdbId != null && meta!.imdbId!.isNotEmpty)
        'imdbId': meta.imdbId,
      if (meta?.contentType != null) 'contentType': meta!.contentType,
      if (meta?.posterUrl != null && meta!.posterUrl!.isNotEmpty)
        'posterUrl': meta.posterUrl,
    };
    // Provider-native identifiers for re-resolution. For packs, per-file ids are
    // pulled from the resolved playlist entries; for single files they ride on
    // [_Resolved].
    switch (provider) {
      case 'debrid': // Real-Debrid
        if (r.rdTorrentId != null) item['rdTorrentId'] = r.rdTorrentId;
        if (!isPack) {
          item['url'] = ''; // force re-resolution from restrictedLink
          if (r.restrictedLink != null) {
            item['restrictedLink'] = r.restrictedLink;
          }
        }
        break;
      case 'torbox':
        item['torboxTorrentId'] = r.torboxTorrentId;
        if (isPack) {
          item['torboxFileIds'] = [
            for (final e in r.playlist!)
              if (e.torboxFileId != null) e.torboxFileId,
          ];
        } else if (r.torboxFileId != null) {
          item['torboxFileId'] = r.torboxFileId;
        }
        break;
      case 'premiumize':
        // Collections re-resolve from torrent_hash; singles from the file path.
        if (!isPack && r.premiumizePath != null) {
          item['premiumizePath'] = r.premiumizePath;
        }
        break;
      case 'alldebrid':
        // Collections re-resolve from torrent_hash; singles from the locked link.
        if (!isPack && r.allDebridLink != null) {
          item['allDebridLink'] = r.allDebridLink;
        }
        break;
      case 'pikpak':
        if (isPack) {
          // Pack: folder id + per-file video ids (player collection path).
          item['pikpakFileId'] = r.pikpakFileId;
          item['pikpakFileIds'] = [
            for (final e in r.playlist!)
              if (e.pikpakFileId != null) e.pikpakFileId,
          ];
        } else {
          // Single: the playable VIDEO-file id, NOT the folder id — else the
          // player can't get a streaming URL and the item won't play.
          item['pikpakFileId'] = r.pikpakVideoFileId ?? r.pikpakFileId;
        }
        break;
    }
    final ok = await StorageService.addPlaylistItemRaw(item);
    if (context.mounted) {
      _snack(context, ok ? 'Added to playlist.' : 'Already in playlist.');
    }
  }

  /// The app's real post-add chooser (glass card + styled tiles), with the full
  /// option set — Play / Download / Add to playlist / Add to channel / Open in
  /// provider tab — matching Home's per-provider sheets.
  static Future<void> _showChooser(
    BuildContext context,
    _Resolved r,
    Torrent torrent,
    String provider, {
    String? magnet,
    PlaybackMeta? meta,
    List<Torrent>? sources,
    int sourceIndex = 0,
    String searchKeyword = '',
  }) async {
    final hasVideo = r.playUrl != null && r.playUrl!.isNotEmpty;
    final name = torrent.displayTitle;
    await showDebridActionSheet(
      context,
      providerLabel: _label(provider),
      torrentName: name,
      gradient: _providerGradient(provider),
      providerIcon: _providerIcon(provider),
      subtitle: hasVideo
          ? 'Ready on ${_label(provider)}. Choose your next step.'
          : 'Added to ${_label(provider)}.',
      actions: [
        DebridActionItem(
          icon: Icons.play_circle_fill_rounded,
          color: const Color(0xFF10B981),
          title: 'Play now',
          subtitle: 'Stream it right away.',
          enabled: hasVideo,
          onTap: () => unawaited(_play(context, r, torrent,
              provider: provider,
              meta: meta,
              sources: sources,
              sourceIndex: sourceIndex)),
        ),
        DebridActionItem(
          icon: Icons.download_rounded,
          color: const Color(0xFF3B82F6),
          title: 'Download to device',
          subtitle: 'Grab the file(s) via ${_label(provider)}.',
          onTap: () => unawaited(_download(context, r, torrent)),
        ),
        DebridActionItem(
          icon: Icons.playlist_add_rounded,
          color: const Color(0xFF8B5CF6),
          title: 'Add to playlist',
          subtitle: 'Save it to your playlist for later.',
          enabled: hasVideo,
          onTap: () =>
              unawaited(_addToPlaylist(context, r, torrent, provider, meta: meta)),
        ),
        DebridActionItem(
          icon: Icons.connected_tv,
          color: const Color(0xFF14B8A6),
          title: 'Add to channel',
          subtitle: 'Cache this torrent in a Debrify TV channel.',
          onTap: () => unawaited(DebrifyTvChannelAddService.addTorrentsToChannel(
            context,
            torrents: [torrent],
            searchKeyword: searchKeyword,
          )),
        ),
        // TorBox power actions: download the whole-torrent ZIP to device, or
        // copy its permalink (parity with the old screen's TorBox download menu).
        if (provider == 'torbox' && r.torboxTorrentId != null) ...[
          DebridActionItem(
            icon: Icons.folder_zip_rounded,
            color: const Color(0xFFA78BFA),
            title: 'Download as ZIP',
            subtitle: 'Download all files as a ZIP to this device.',
            onTap: () =>
                unawaited(_downloadTorboxZip(context, r.torboxTorrentId!, name)),
          ),
          DebridActionItem(
            icon: Icons.link_rounded,
            color: const Color(0xFFEC4899),
            title: 'Copy Download Link (Zip)',
            subtitle: 'Copy ZIP download link to clipboard.',
            onTap: () =>
                unawaited(_copyTorboxZipLink(context, r.torboxTorrentId!)),
          ),
        ],
        // Premiumize power actions (need the magnet — cloud transfer + ZIP).
        if (provider == 'premiumize' && magnet != null) ...[
          DebridActionItem(
            icon: Icons.cloud_upload_rounded,
            color: const Color(0xFFF59E0B),
            title: 'Transfer to Premiumize',
            subtitle: 'Add this torrent to your Premiumize cloud.',
            onTap: () => unawaited(_premiumizeTransfer(context, magnet)),
          ),
          DebridActionItem(
            icon: Icons.folder_zip_rounded,
            color: const Color(0xFFA78BFA),
            title: 'Download as ZIP',
            subtitle: 'Transfer to cloud and download all files as a ZIP.',
            onTap: () =>
                unawaited(_premiumizeZip(context, magnet, name, copyOnly: false)),
          ),
          DebridActionItem(
            icon: Icons.link_rounded,
            color: const Color(0xFFEC4899),
            title: 'Copy ZIP Link',
            subtitle: 'Copy ZIP download link to clipboard.',
            onTap: () =>
                unawaited(_premiumizeZip(context, magnet, name, copyOnly: true)),
          ),
        ],
        if (r.openInTab != null)
          DebridActionItem(
            icon: Icons.open_in_new_rounded,
            color: const Color(0xFF6366F1),
            title: 'Open in provider tab',
            subtitle: r.isRarArchive
                ? 'Not available for RAR archives'
                : 'View it in ${_label(provider)}.',
            enabled: !r.isRarArchive,
            onTap: () => r.openInTab!.call(),
          ),
      ],
    );
  }

  // ── Provider-specific power actions (TorBox / Premiumize) ───────────────────

  static Future<void> _copyTorboxZipLink(
      BuildContext context, int torrentId) async {
    final apiKey = (await StorageService.getTorboxApiKey()) ?? '';
    if (apiKey.isEmpty) return;
    final zipLink = TorboxService.createZipPermalink(apiKey, torrentId);
    await Clipboard.setData(ClipboardData(text: zipLink));
    if (context.mounted) {
      _snack(context, 'ZIP download link copied to clipboard!');
    }
  }

  /// Queue the whole-torrent ZIP for download to this device (parity with the
  /// old TorBox "Download as ZIP to device" option). The `torboxZip` meta lets
  /// the download service key/retry it as a ZIP job.
  static Future<void> _downloadTorboxZip(
      BuildContext context, int torrentId, String torrentName) async {
    final apiKey = (await StorageService.getTorboxApiKey()) ?? '';
    if (apiKey.isEmpty) return;
    final zipLink = TorboxService.createZipPermalink(apiKey, torrentId);
    try {
      await DownloadService.instance.enqueueDownload(
        url: zipLink,
        fileName: '$torrentName.zip',
        torrentName: torrentName,
        meta: jsonEncode({
          'torboxDownload': true,
          'torboxZip': true,
          'torboxTorrentId': torrentId,
        }),
      );
      if (context.mounted) _snack(context, 'ZIP download queued.');
    } catch (_) {
      if (context.mounted) _snack(context, 'Failed to queue ZIP download.');
    }
  }

  static Future<void> _premiumizeTransfer(
      BuildContext context, String magnet) async {
    final apiKey = (await StorageService.getPremiumizeApiKey()) ?? '';
    if (apiKey.isEmpty) return;
    try {
      await PremiumizeService.createTransfer(apiKey, magnet);
      if (context.mounted) {
        _snack(context,
            'Added to Premiumize. It will be available once the download finishes.');
      }
    } catch (_) {
      if (context.mounted) _snack(context, 'Failed to transfer to Premiumize.');
    }
  }

  /// Generate the Premiumize ZIP (cloud transfer + zip), then either queue the
  /// download or copy the link — matching Home's "Download as ZIP" / "Copy ZIP
  /// Link" tiles. Shows the Premiumize loading overlay during the (slow) build.
  static Future<void> _premiumizeZip(
    BuildContext context,
    String magnet,
    String torrentName, {
    required bool copyOnly,
  }) async {
    final apiKey = (await StorageService.getPremiumizeApiKey()) ?? '';
    if (apiKey.isEmpty) return;
    if (!context.mounted) return;
    final rootNav = Navigator.of(context, rootNavigator: true);
    DebridLoadingOverlay.showPremiumize(context, torrentName);
    // Only the (slow) ZIP generation is covered by the overlay. Popping happens
    // exactly once — the post-success clipboard/download step runs in its own
    // guard so a failure there can NEVER pop a second (underlying) route.
    final String zipUrl;
    try {
      zipUrl = await PremiumizeService.createTransferAndGenerateZip(apiKey, magnet);
    } catch (_) {
      if (rootNav.canPop()) rootNav.pop();
      if (context.mounted) {
        _snack(context,
            copyOnly ? 'Failed to generate ZIP link.' : 'Failed to generate ZIP.');
      }
      return;
    }
    if (rootNav.canPop()) rootNav.pop(); // dismiss the overlay exactly once
    try {
      if (copyOnly) {
        await Clipboard.setData(ClipboardData(text: zipUrl));
        if (context.mounted) {
          _snack(context, 'ZIP download link copied to clipboard!');
        }
      } else {
        await DownloadService.instance.enqueueDownload(
          url: zipUrl,
          fileName: '$torrentName.zip',
          torrentName: torrentName,
        );
        if (context.mounted) _snack(context, 'ZIP download queued successfully.');
      }
    } catch (_) {
      if (context.mounted) {
        _snack(context,
            copyOnly ? 'Failed to generate ZIP link.' : 'Failed to generate ZIP.');
      }
    }
  }

  static List<Color> _providerGradient(String provider) {
    switch (provider) {
      case 'debrid':
        return const [Color(0xFF10B981), Color(0xFF059669)];
      case 'torbox':
        return const [Color(0xFF8B5CF6), Color(0xFF7C3AED)];
      case 'premiumize':
        return const [Color(0xFFF59E0B), Color(0xFFD97706)];
      case 'alldebrid':
        return const [Color(0xFF26A69A), Color(0xFF00796B)];
      case 'pikpak':
        return const [Color(0xFF6366F1), Color(0xFF4338CA)];
      default:
        return const [Color(0xFF6366F1), Color(0xFF4338CA)];
    }
  }

  static IconData _providerIcon(String provider) {
    switch (provider) {
      case 'debrid':
        return Icons.cloud_download_rounded;
      case 'torbox':
        return Icons.flash_on_rounded;
      case 'premiumize':
        return Icons.workspace_premium_rounded;
      case 'alldebrid':
        return Icons.all_inclusive_rounded;
      case 'pikpak':
        return Icons.cloud_circle_rounded;
      default:
        return Icons.cloud_download_rounded;
    }
  }

  // ── Not-cached handling (mirrors Home UX: warn, then keep-downloading) ──────

  static Future<void> _handleNotCached(
    BuildContext context,
    Object marker,
    String provider,
    String magnet,
  ) async {
    final keep = await _notCachedDialog(context, _label(provider));
    if (!context.mounted) return;
    if (!keep) {
      if (marker is TorrentNotCachedException) {
        try {
          await DebridService.deleteTorrent(marker.apiKey, marker.torrentId);
        } catch (_) {}
      } else if (marker is AllDebridTorrentNotReadyException) {
        try {
          await AllDebridService.deleteMagnet(marker.apiKey, marker.magnetId);
        } catch (_) {}
      }
      return;
    }
    // "Add anyway": queue the download on the provider.
    if (provider == 'torbox') {
      final apiKey = (await StorageService.getTorboxApiKey()) ?? '';
      try {
        await TorboxService.createTorrent(
            apiKey: apiKey, magnet: magnet, addOnlyIfCached: false);
      } catch (_) {}
    } else if (provider == 'premiumize') {
      final apiKey = (await StorageService.getPremiumizeApiKey()) ?? '';
      try {
        await PremiumizeService.createTransfer(apiKey, magnet);
      } catch (_) {}
    }
    // RD/AllDebrid already added the torrent while resolving; nothing more.
    if (context.mounted) {
      _snack(context,
          'Added — it will download on ${_label(provider)}. Play it once ready.');
    }
  }

  static Future<bool> _notCachedDialog(BuildContext context, String label) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.cloud_off_rounded,
                    color: Color(0xFFF59E0B),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Torrent Not Cached',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This torrent is not cached on $label. Would you like to add '
                  'it anyway?\n\nOnce downloaded, it will be available in the '
                  '$label page.',
                  style: Theme.of(ctx)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          DialogTapGuard.markKeyAction();
                          Navigator.of(ctx).pop(false);
                        },
                        style: ButtonStyle(
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(vertical: 12),
                          ),
                          shape: WidgetStateProperty.resolveWith((states) {
                            final focused = states.contains(WidgetState.focused);
                            return RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: focused ? Colors.white : Colors.white24,
                                width: focused ? 2 : 1,
                              ),
                            );
                          }),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        autofocus: true,
                        onPressed: () {
                          DialogTapGuard.markKeyAction();
                          Navigator.of(ctx).pop(true);
                        },
                        style: ButtonStyle(
                          backgroundColor: const WidgetStatePropertyAll(
                            Color(0xFF6366F1),
                          ),
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(vertical: 12),
                          ),
                          shape: WidgetStateProperty.resolveWith((states) {
                            final focused = states.contains(WidgetState.focused);
                            return RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: focused
                                  ? const BorderSide(color: Colors.white, width: 2)
                                  : BorderSide.none,
                            );
                          }),
                        ),
                        child: const Text(
                          'Add Anyway',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    return result == true;
  }

  // ── Provider resolution ────────────────────────────────────────────────────

  /// Resolves which provider to use. Honours the default; when none is set and
  /// more than one is configured, asks the user (mirrors Home's behaviour).
  static Future<String?> _pickProvider(BuildContext context) async {
    final (configured, def) = await _configuredProviders();
    if (configured.isEmpty) return null;
    if (def != null) return def;
    if (configured.length == 1) return configured.first;
    if (!context.mounted) return _cancelled;
    final result = await showProviderPickerDialog(
      context,
      [
        for (final p in configured)
          ProviderPickerOption(
            id: p,
            label: _label(p),
            gradient: _providerGradient(p),
            icon: _providerIcon(p),
          ),
      ],
    );
    if (result == null) return _cancelled; // dismissed
    // "Remember my choice" persists the default so we never ask again.
    if (result.remember) {
      await StorageService.setDefaultTorrentProvider(result.provider);
    }
    return result.provider;
  }

  static Future<bool> _isConfigured(String provider) async {
    switch (provider) {
      case 'debrid':
        return (await StorageService.getApiKey())?.isNotEmpty ?? false;
      case 'torbox':
        return (await StorageService.getTorboxApiKey())?.isNotEmpty ?? false;
      case 'premiumize':
        return (await StorageService.getPremiumizeApiKey())?.isNotEmpty ?? false;
      case 'alldebrid':
        return (await StorageService.getAllDebridApiKey())?.isNotEmpty ?? false;
      case 'pikpak':
        return StorageService.getPikPakEnabled();
      default:
        return false;
    }
  }

  static Future<String> _postAction(String provider) async {
    switch (provider) {
      case 'torbox':
        return StorageService.getTorboxPostTorrentAction();
      case 'premiumize':
        return StorageService.getPremiumizePostTorrentAction();
      case 'alldebrid':
        return StorageService.getAllDebridPostTorrentAction();
      case 'pikpak':
        return StorageService.getPikPakPostTorrentAction();
      default:
        return StorageService.getPostTorrentAction();
    }
  }

  static Future<List<Torrent>> _cacheFirst(
      String provider, List<Torrent> candidates) async {
    final hashes = candidates
        .map((t) => t.infohash.toLowerCase())
        .where((h) => h.isNotEmpty)
        .toList();
    final cached = <String>{};
    try {
      if (provider == 'torbox') {
        final key = (await StorageService.getTorboxApiKey()) ?? '';
        cached.addAll(
          await TorboxService.checkCachedTorrents(
              apiKey: key, infoHashes: hashes),
        );
      } else if (provider == 'premiumize') {
        final key = (await StorageService.getPremiumizeApiKey()) ?? '';
        final res = await PremiumizeService.checkCache(key, hashes);
        for (var i = 0; i < hashes.length && i < res.length; i++) {
          if (res[i]) cached.add(hashes[i]);
        }
      }
    } catch (_) {}
    if (cached.isEmpty) return candidates;
    final hit = candidates
        .where((t) => cached.contains(t.infohash.toLowerCase()))
        .toList();
    final miss = candidates
        .where((t) => !cached.contains(t.infohash.toLowerCase()))
        .toList();
    return [...hit, ...miss];
  }

  // ── File pickers: largest file that looks like video ───────────────────────

  static TorboxFile? _pickTorbox(List<TorboxFile> files) {
    final pool = _videoPool(files, (f) => f.name);
    pool.sort((a, b) => b.size.compareTo(a.size));
    return pool.isEmpty ? null : pool.first;
  }

  static PremiumizeFile? _pickPremiumize(List<PremiumizeFile> files) {
    final pool = _videoPool(files, (f) => f.path);
    pool.sort((a, b) => b.size.compareTo(a.size));
    return pool.isEmpty ? null : pool.first;
  }

  static AllDebridFile? _pickAllDebrid(List<AllDebridFile> files) {
    final pool = _videoPool(files, (f) => f.path);
    pool.sort((a, b) => b.size.compareTo(a.size));
    return pool.isEmpty ? null : pool.first;
  }

  static List<T> _videoPool<T>(List<T> files, String Function(T) nameOf) {
    final videos =
        files.where((f) => FileUtils.isVideoFile(nameOf(f))).toList();
    return videos.isNotEmpty ? videos : List<T>.from(files);
  }

  static String _fileName(String path) {
    final norm = path.replaceAll('\\', '/');
    final idx = norm.lastIndexOf('/');
    return idx >= 0 ? norm.substring(idx + 1) : norm;
  }

  /// True when a resolved playlist's file names look like a TV series (multiple
  /// files parseable as season/episode), so it should play in series view mode.
  static bool _isSeriesPlaylist(List<PlaylistEntry> entries) {
    if (entries.length <= 1) return false;
    final names = [for (final e in entries) _fileName(e.title)];
    return SeriesParser.isSeriesPlaylist(names);
  }

  /// Order video items by season/episode (falling back to filename) and return
  /// the sorted list plus the first-episode start index — matching Home's
  /// episode-aware playlist builders (so E2 plays before E10, starting at E1).
  static (List<T>, int) _orderBySeries<T>(
      List<T> items, String Function(T) nameOf) {
    final names = [for (final e in items) _fileName(nameOf(e))];
    final infos = [for (final n in names) SeriesParser.parseFilename(n)];
    final isSeries = items.length > 1 && SeriesParser.isSeriesPlaylist(names);
    final order = List<int>.generate(items.length, (i) => i);
    if (isSeries) {
      order.sort((a, b) {
        final sc = (infos[a].season ?? 0).compareTo(infos[b].season ?? 0);
        if (sc != 0) return sc;
        final ec = (infos[a].episode ?? 0).compareTo(infos[b].episode ?? 0);
        if (ec != 0) return ec;
        return names[a].toLowerCase().compareTo(names[b].toLowerCase());
      });
    } else {
      order.sort(
          (a, b) => names[a].toLowerCase().compareTo(names[b].toLowerCase()));
    }
    final sorted = [for (final i in order) items[i]];
    final sortedInfos = [for (final i in order) infos[i]];
    var start = isSeries ? _firstEpisodeIndex(sortedInfos) : 0;
    if (start < 0 || start >= sorted.length) start = 0;
    return (sorted, start);
  }

  /// Real-Debrid multi-file playlist — a verbatim port of Home's
  /// `_buildRdPlaylistEntries` (pure logic): video-file filtering aligned to the
  /// `links` array, archive guard, [SeriesParser] first-episode detection, start
  /// entry unrestricted, the rest carry `restrictedLink` for lazy resolution.
  static Future<List<PlaylistEntry>?> _buildRdPlaylist(
    List<dynamic> links,
    List<dynamic> files,
    String apiKey,
  ) async {
    final selectedFiles = files.where((file) => file['selected'] == 1).toList();
    final allFilesToUse = selectedFiles.isNotEmpty ? selectedFiles : files;

    final filesToUse = allFilesToUse.where((file) {
      String? filename = file['name']?.toString() ??
          file['filename']?.toString() ??
          file['path']?.toString();
      if (filename != null && filename.startsWith('/')) {
        filename = filename.split('/').last;
      }
      return filename != null && FileUtils.isVideoFile(filename);
    }).toList();

    // Archive check (multiple files but a single link) / no video.
    if (filesToUse.length > 1 && links.length == 1) return null;
    if (filesToUse.isEmpty) return null;

    final filenames = filesToUse.map((file) {
      String? name = file['name']?.toString() ??
          file['filename']?.toString() ??
          file['path']?.toString();
      if (name != null && name.startsWith('/')) name = name.split('/').last;
      return name ?? 'Unknown File';
    }).toList();

    final isSeries = SeriesParser.isSeriesPlaylist(filenames);
    final seriesInfos = isSeries ? SeriesParser.parsePlaylist(filenames) : null;

    int firstIndex = 0;
    if (isSeries && seriesInfos != null) {
      int lowestSeason = 999, lowestEpisode = 999;
      for (int i = 0; i < seriesInfos.length; i++) {
        final info = seriesInfos[i];
        if (info.isSeries && info.season != null && info.episode != null) {
          if (info.season! < lowestSeason ||
              (info.season! == lowestSeason && info.episode! < lowestEpisode)) {
            lowestSeason = info.season!;
            lowestEpisode = info.episode!;
            firstIndex = i;
          }
        }
      }
    }

    final entries = <PlaylistEntry>[];
    for (int i = 0; i < filesToUse.length; i++) {
      final file = filesToUse[i];
      String? filename = file['name']?.toString() ??
          file['filename']?.toString() ??
          file['path']?.toString();
      String? relativePath = filename;
      if (relativePath != null && relativePath.startsWith('/')) {
        relativePath = relativePath.substring(1);
      }
      if (filename != null && filename.startsWith('/')) {
        filename = filename.split('/').last;
      }
      final finalFilename = filename ?? 'Unknown File';
      final int? sizeBytes = (file is Map) ? (file['bytes'] as int?) : null;
      if (i >= links.length) continue;

      String url = '';
      if (i == firstIndex) {
        try {
          final unrestrictResult =
              await DebridService.unrestrictLink(apiKey, links[i]);
          url = unrestrictResult['download']?.toString() ?? '';
        } catch (_) {
          url = '';
        }
      }
      entries.add(
        PlaylistEntry(
          url: url,
          title: finalFilename,
          relativePath: relativePath,
          restrictedLink: url.isEmpty ? links[i].toString() : null,
          sizeBytes: sizeBytes,
        ),
      );
    }
    return entries.isEmpty ? null : entries;
  }

  // ── PikPak resolution + playlist (ported from Home's PikPak flow) ───────────

  /// Adds the magnet to PikPak, polls task + file until complete, lists the
  /// folder (season packs) and builds a playlist. A port of Home's
  /// `_resolveSourceViaPikPak` + `_buildPikPakPlaylistEntries` (downloads to the
  /// PikPak root rather than a dedicated subfolder, for simplicity).
  static Future<_Resolved> _addPikPak(String magnet, Torrent torrent) async {
    final title = torrent.displayTitle;
    final pikpak = PikPakApiService.instance;
    final add = await pikpak.addOfflineDownload(magnet);
    String? fileId;
    String? taskId;
    if (add['file'] != null) {
      fileId = add['file']['id']?.toString();
    } else if (add['task'] != null) {
      fileId = add['task']['file_id']?.toString();
      taskId = add['task']['id']?.toString();
    } else if (add['id'] != null) {
      fileId = add['id']?.toString();
    }
    if (fileId == null) throw Exception('PikPak: no file id returned');

    const pollInterval = Duration(seconds: 2);
    var phase1 = false;
    if (taskId != null) {
      for (var a = 0; a < 7; a++) {
        if (a > 0) await Future.delayed(pollInterval);
        try {
          final t = await pikpak.getTaskStatus(taskId);
          final phase = t['phase'];
          if (phase == 'PHASE_TYPE_COMPLETE') {
            phase1 = true;
            break;
          }
          if (phase == 'PHASE_TYPE_ERROR') {
            throw const _PikPakFailed();
          }
          final rp = t['progress'];
          if (rp != null) {
            final p = rp is int ? rp : int.tryParse(rp.toString()) ?? 0;
            if (p >= 90) {
              phase1 = true;
              break;
            }
          }
        } on _PikPakFailed {
          rethrow; // surface "Download failed on PikPak"
        } catch (_) {
          break;
        }
      }
    }

    List<Map<String, dynamic>> videoFiles = const [];
    for (var a = 0; a < 5; a++) {
      if (a > 0 || !phase1) await Future.delayed(pollInterval);
      try {
        final fd = await pikpak.getFileDetails(fileId);
        if (fd['phase'] == 'PHASE_TYPE_COMPLETE') {
          if (fd['kind'] == 'drive#folder') {
            videoFiles = await _extractPikPakVideos(pikpak, fileId);
          } else {
            final mt = (fd['mime_type'] ?? '').toString();
            if (mt.startsWith('video/')) videoFiles = [fd];
          }
          break;
        }
        if (fd['phase'] == 'PHASE_TYPE_ERROR') {
          throw const _PikPakFailed();
        }
      } on _PikPakFailed {
        rethrow; // surface "Download failed on PikPak"
      } catch (_) {}
    }
    if (videoFiles.isEmpty) {
      throw const _PikPakStillProcessing();
    }

    final playlist = await _buildPikPakPlaylist(torrent.name, videoFiles, pikpak);
    if (playlist == null || playlist.isEmpty) {
      throw Exception('PikPak: could not resolve a playable stream.');
    }
    var startIndex = playlist.indexWhere((e) => e.url.isNotEmpty);
    if (startIndex < 0) startIndex = 0;
    final capturedFileId = fileId;
    return _Resolved(
      title: title,
      playUrl: playlist[startIndex].url,
      downloadUrls: playlist[startIndex].url.isNotEmpty
          ? [playlist[startIndex].url]
          : const [],
      openInTab: () =>
          MainPageBridge.openPikPakFolder?.call(capturedFileId, title),
      playlist: playlist.length > 1 ? playlist : null,
      startIndex: startIndex,
      // Single video file: expose its real name so the bound-source episode
      // check can judge it instead of passing vacuously.
      fileName: playlist.length == 1 ? playlist.first.title : null,
      pikpakFileId: capturedFileId,
      // The playable video-file id (folder id is capturedFileId) so a single
      // saved to a playlist re-resolves its stream instead of failing on the
      // folder.
      pikpakVideoFileId:
          playlist.length == 1 ? playlist.first.pikpakFileId : null,
    );
  }

  static Future<List<Map<String, dynamic>>> _extractPikPakVideos(
    PikPakApiService pikpak,
    String folderId, {
    int maxDepth = 5,
    int currentDepth = 0,
    String currentPath = '',
  }) async {
    if (currentDepth >= maxDepth) return [];
    final videos = <Map<String, dynamic>>[];
    try {
      final result = await pikpak.listFiles(parentId: folderId);
      for (final file in result.files) {
        final kind = file['kind'] ?? '';
        final mimeType = (file['mime_type'] ?? '').toString();
        final itemName = (file['name'] ?? 'unknown').toString();
        if (kind == 'drive#folder') {
          final subPath =
              currentPath.isEmpty ? itemName : '$currentPath/$itemName';
          videos.addAll(await _extractPikPakVideos(
            pikpak,
            file['id'].toString(),
            maxDepth: maxDepth,
            currentDepth: currentDepth + 1,
            currentPath: subPath,
          ));
        } else if (mimeType.startsWith('video/')) {
          final videoWithPath = Map<String, dynamic>.from(file);
          if (currentPath.isNotEmpty) {
            videoWithPath['name'] = '$currentPath/$itemName';
          }
          videos.add(videoWithPath);
        }
      }
    } catch (_) {}
    videos.sort((a, b) => (a['name'] ?? '')
        .toString()
        .toLowerCase()
        .compareTo((b['name'] ?? '').toString().toLowerCase()));
    return videos;
  }

  static Future<List<PlaylistEntry>?> _buildPikPakPlaylist(
    String torrentName,
    List<Map<String, dynamic>> videoFiles,
    PikPakApiService pikpak,
  ) async {
    if (videoFiles.isEmpty) return null;
    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      try {
        final fullData = await pikpak.getFileDetails(file['id'].toString());
        final url = pikpak.getStreamingUrl(fullData);
        if (url == null) return null;
        return [
          PlaylistEntry(
            url: url,
            title: (file['name'] ?? torrentName).toString(),
            relativePath: file['_fullPath'] as String?,
            provider: 'pikpak',
            pikpakFileId: file['id']?.toString(),
            sizeBytes: int.tryParse(file['size']?.toString() ?? '0') ?? 0,
          ),
        ];
      } catch (_) {
        return null;
      }
    }

    final items = <_PikPakItem>[
      for (final file in videoFiles)
        _PikPakItem(
          file: file,
          seriesInfo: SeriesParser.parseFilename(_pikpakDisplayName(file)),
          displayName: _pikpakDisplayName(file),
        ),
    ];
    final fnames = items.map((e) => e.displayName).toList();
    final isSeriesCollection =
        items.length > 1 && SeriesParser.isSeriesPlaylist(fnames);

    final sorted = [...items];
    if (isSeriesCollection) {
      sorted.sort((a, b) {
        final sc =
            (a.seriesInfo.season ?? 0).compareTo(b.seriesInfo.season ?? 0);
        if (sc != 0) return sc;
        final ec =
            (a.seriesInfo.episode ?? 0).compareTo(b.seriesInfo.episode ?? 0);
        if (ec != 0) return ec;
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });
    } else {
      sorted.sort((a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    }

    final seriesInfos = sorted.map((e) => e.seriesInfo).toList();
    var startIndex = isSeriesCollection ? _firstEpisodeIndex(seriesInfos) : 0;
    if (startIndex < 0 || startIndex >= sorted.length) startIndex = 0;

    String initialUrl = '';
    try {
      final fullData =
          await pikpak.getFileDetails(sorted[startIndex].file['id'].toString());
      initialUrl = pikpak.getStreamingUrl(fullData) ?? '';
    } catch (_) {
      return null;
    }
    if (initialUrl.isEmpty) return null;

    final entries = <PlaylistEntry>[];
    for (var i = 0; i < sorted.length; i++) {
      final entry = sorted[i];
      final episodeLabel = _formatPikPakTitle(
        info: entry.seriesInfo,
        fallback: entry.displayName,
        isSeriesCollection: isSeriesCollection,
      );
      final combinedTitle = _combineTitle(
        seriesTitle: entry.seriesInfo.title,
        episodeLabel: episodeLabel,
        isSeriesCollection: isSeriesCollection,
        fallback: entry.displayName,
      );
      entries.add(PlaylistEntry(
        url: i == startIndex ? initialUrl : '',
        title: combinedTitle,
        relativePath: entry.file['_fullPath'] as String?,
        provider: 'pikpak',
        pikpakFileId: entry.file['id']?.toString(),
        sizeBytes: int.tryParse(entry.file['size']?.toString() ?? '0'),
      ));
    }
    return entries.isEmpty ? null : entries;
  }

  static String _pikpakDisplayName(Map<String, dynamic> file) {
    final name = file['name']?.toString() ?? '';
    if (name.isNotEmpty) return FileUtils.getFileName(name);
    return 'File ${file['id']}';
  }

  static String _formatPikPakTitle({
    required SeriesInfo info,
    required String fallback,
    required bool isSeriesCollection,
  }) {
    if (!isSeriesCollection) return fallback;
    final season = info.season;
    final episode = info.episode;
    if (info.isSeries && season != null && episode != null) {
      final s = season.toString().padLeft(2, '0');
      final e = episode.toString().padLeft(2, '0');
      final desc = info.episodeTitle?.trim().isNotEmpty == true
          ? info.episodeTitle!.trim()
          : (info.title?.trim().isNotEmpty == true
              ? info.title!.trim()
              : fallback);
      return 'S${s}E$e · $desc';
    }
    return fallback;
  }

  static String _combineTitle({
    required String? seriesTitle,
    required String episodeLabel,
    required bool isSeriesCollection,
    required String fallback,
  }) {
    if (!isSeriesCollection) return fallback;
    final clean = seriesTitle?.replaceAll(RegExp(r'[._\-]+$'), '').trim();
    if (clean != null && clean.isNotEmpty) return '$clean $episodeLabel';
    return fallback;
  }

  static int _firstEpisodeIndex(List<SeriesInfo> infos) {
    var startIndex = 0;
    int? bestSeason;
    int? bestEpisode;
    for (var i = 0; i < infos.length; i++) {
      final info = infos[i];
      final season = info.season;
      final episode = info.episode;
      if (!info.isSeries || season == null || episode == null) continue;
      final betterSeason = bestSeason == null || season < bestSeason;
      final betterEpisode = bestSeason != null &&
          season == bestSeason &&
          (bestEpisode == null || episode < bestEpisode);
      if (betterSeason || betterEpisode) {
        bestSeason = season;
        bestEpisode = episode;
        startIndex = i;
      }
    }
    return startIndex;
  }

  // ── Acquisition URL ────────────────────────────────────────────────────────

  /// True when [t] carries something we can turn into a magnet (real magnet,
  /// infohash, or a .torrent URL). Sync, for filtering candidate lists.
  static bool _hasAcquisition(Torrent t) =>
      (t.magnetUrl?.startsWith('magnet:') ?? false) ||
      (t.hasRealInfoHash && t.infohash.isNotEmpty) ||
      (t.torrentUrl?.isNotEmpty ?? false);

  /// Prefer a real magnet; else synthesize from the infohash (works across
  /// every provider); else convert a .torrent URL to a real magnet
  /// (magnet-only APIs — PikPak/TorBox/Premiumize/AllDebrid — can't accept a
  /// protected .torrent URL, matching Home's `_pikPakMagnetForTorrent`).
  static Future<String?> _magnetFor(Torrent t) async {
    final magnet = t.magnetUrl;
    if (magnet != null && magnet.startsWith('magnet:')) return magnet;
    if (t.hasRealInfoHash && t.infohash.isNotEmpty) {
      return 'magnet:?xt=urn:btih:${t.infohash}&dn=${Uri.encodeComponent(t.name)}';
    }
    final torrentUrl = t.torrentUrl;
    if (torrentUrl != null && torrentUrl.isNotEmpty) {
      try {
        return await TorrentFileService.magnetFromTorrentUrl(torrentUrl,
            fallbackName: t.name);
      } catch (_) {
        return torrentUrl; // last resort (RD can still consume an http .torrent)
      }
    }
    return null;
  }

  static String _label(String provider) {
    switch (provider) {
      case 'debrid':
        return 'Real-Debrid';
      case 'torbox':
        return 'TorBox';
      case 'premiumize':
        return 'Premiumize';
      case 'alldebrid':
        return 'AllDebrid';
      case 'pikpak':
        return 'PikPak';
      case SeriesSource.localService:
        return 'On-device';
      default:
        return provider;
    }
  }

  // ── Minimal UI feedback ────────────────────────────────────────────────────

  /// The app's shared cinematic add-loading overlay (not a plain spinner box).
  static void _showLoading(BuildContext context, String provider, String name) {
    switch (provider) {
      case 'debrid':
        DebridLoadingOverlay.showRealDebrid(context, name);
        break;
      case 'torbox':
        DebridLoadingOverlay.showTorbox(context, name);
        break;
      case 'premiumize':
        DebridLoadingOverlay.showPremiumize(context, name);
        break;
      case 'alldebrid':
        DebridLoadingOverlay.showAllDebrid(context, name);
        break;
      case 'pikpak':
        DebridLoadingOverlay.show(context,
            provider: 'PikPak',
            torrentName: name,
            accentColor: const Color(0xFF6366F1),
            icon: Icons.cloud_circle_rounded);
        break;
      default:
        DebridLoadingOverlay.show(context,
            provider: _label(provider), torrentName: name);
    }
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }
}

/// Resolved add result carrying what each post-action branch needs.
class _Resolved {
  final String title;
  final String? playUrl;
  final List<String> downloadUrls;
  final VoidCallback? openInTab;

  /// Multi-file playlist (season packs); the launcher lazily resolves each
  /// entry's URL from its provider metadata (torboxFileId / allDebridLink /
  /// restrictedLink / premiumizePath / pikpakFileId). [startIndex] is the
  /// first-episode entry to begin playback at.
  final List<PlaylistEntry>? playlist;
  final int startIndex;

  /// The single resolved file's name (with extension) for download naming.
  final String? fileName;

  /// RD only: an unextracted RAR archive (multiple files, one link). The
  /// provider "open" view isn't useful for these, so it's disabled.
  final bool isRarArchive;

  /// TorBox only: the torrent id, for the "Copy Download Link (Zip)" action.
  final int? torboxTorrentId;

  /// RD only: the account entry this add created (RD's addMagnet always makes
  /// a fresh entry), so a rejected bound-source attempt can delete it again.
  final String? rdTorrentId;

  /// PikPak only: the drive entry (file/folder) this add created (PikPak's
  /// addOfflineDownload always makes a fresh entry), so a rejected
  /// bound-source attempt can delete it again.
  final String? pikpakFileId;

  // Single-file provider-native identifiers, captured so an "Add to playlist"
  // item can be RE-RESOLVED after the direct URL expires (the playlist player
  // re-derives a fresh link from these) — parity with the old per-provider
  // playlist schema. Only the field for the resolved provider is set.
  final String? restrictedLink; // RD: raw restricted link to re-unrestrict
  final int? torboxFileId; // TorBox: file id to re-request a download link
  final String? premiumizePath; // Premiumize: file path (matched on re-resolve)
  final String? allDebridLink; // AllDebrid: locked link to re-unlock
  // PikPak: the playable VIDEO-file id for a single (distinct from
  // [pikpakFileId], which is the offline-download FOLDER id used for
  // bound-source deletes). A playlist item must store the video-file id or the
  // player can't get a streaming URL from a folder.
  final String? pikpakVideoFileId;

  const _Resolved({
    required this.title,
    this.playUrl,
    this.downloadUrls = const [],
    this.openInTab,
    this.playlist,
    this.startIndex = 0,
    this.fileName,
    this.isRarArchive = false,
    this.torboxTorrentId,
    this.rdTorrentId,
    this.pikpakFileId,
    this.restrictedLink,
    this.torboxFileId,
    this.premiumizePath,
    this.allDebridLink,
    this.pikpakVideoFileId,
  });

  bool get hasPlaylist => playlist != null && playlist!.length > 1;
}

/// Mutable flag the catalog-play flow polls to abort when the user taps Cancel
/// on the poster loading mask (the mask dismisses itself; the flow just stops).
class _PlaybackCancelToken {
  bool cancelled = false;
}

/// PikPak is still downloading — surfaced as a friendly, actionable message
/// (not a raw "Could not resolve source: Exception" error), matching Home.
class _PikPakStillProcessing implements Exception {
  const _PikPakStillProcessing();
}

/// PikPak reported a hard failure (PHASE_TYPE_ERROR) — "Download failed".
class _PikPakFailed implements Exception {
  const _PikPakFailed();
}

/// One PikPak video file + its parsed series metadata, for playlist ordering.
class _PikPakItem {
  final Map<String, dynamic> file;
  final SeriesInfo seriesInfo;
  final String displayName;
  const _PikPakItem({
    required this.file,
    required this.seriesInfo,
    required this.displayName,
  });
}

class _TorboxNotCached implements Exception {
  const _TorboxNotCached();
}

class _PremiumizeNotCached implements Exception {
  const _PremiumizeNotCached();
}
