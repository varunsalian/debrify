import 'package:flutter/material.dart';

import '../../models/iptv_playlist.dart';
import '../../models/playlist_view_mode.dart';
import '../../models/stremio_addon.dart';
import '../../services/storage_service.dart';
import '../../services/trakt/trakt_episode_model.dart';
import '../../services/video_player_launcher.dart';
import '../../services/xtream_codes_service.dart';
import '../episodes_screen.dart' show kCatalogDetailRouteName;
import '../merged_series_detail_screen.dart';

/// Decodes the provider identity embedded in an Xtream series watchlist item.
/// Split on the final colon so playlist ids remain free to contain colons.
({String playlistId, String seriesId})? parseXtreamSeriesMetaId(String id) {
  const prefix = 'xtream-series:';
  if (!id.startsWith(prefix)) return null;
  final value = id.substring(prefix.length);
  final separator = value.lastIndexOf(':');
  if (separator <= 0 || separator == value.length - 1) return null;
  return (
    playlistId: value.substring(0, separator),
    seriesId: value.substring(separator + 1),
  );
}

/// Opens the merged series page (hero + two-pane episode list) for an Xtream
/// IPTV series, wired in direct-source mode: seasons come straight from the
/// panel's `get_series_info`, episode taps play their `/series/...` URL
/// outright (no torrent search), and resume/progress ride the same URL-keyed
/// `video_resume_v1` positions every other IPTV on-demand play uses.
///
/// These shows have no IMDb identity, so all the page's IMDb-keyed loaders
/// (Trakt/Simkl, enrichment, recommendations, trailer) are simply not wired —
/// the page already degrades cleanly without them.
///
/// Returns when the page pops, so the caller can refresh its own progress/
/// continue-watching state.
Future<void> openXtreamSeries(
  BuildContext context, {
  required IptvPlaylist playlist,
  required IptvChannel series,
  required bool isTelevision,
}) async {
  final serverUrl = playlist.serverUrl;
  final username = playlist.username;
  final password = playlist.password;
  final seriesId = _seriesIdOf(series);
  if (serverUrl == null ||
      username == null ||
      password == null ||
      seriesId.isEmpty) {
    return;
  }

  // One shared info fetch per page visit — the page's consumers (episode
  // list, resume state, progress map, Play) all coalesce onto it. A null OR
  // episode-less answer clears the memo (and the service declines to cache
  // it), so the episode panel's Retry and the next Play press genuinely
  // re-fetch instead of replaying a transient failure.
  Future<XtreamSeriesInfo?>? infoFuture;
  Future<XtreamSeriesInfo?> info() {
    return infoFuture ??= XtreamCodesService.instance
        .fetchSeriesInfo(
          serverUrl,
          username,
          password,
          seriesId,
          connectionResourceId: playlist.connectionResourceId,
          connectionResourceRevision: playlist.connectionResourceRevision,
        )
        .then((result) {
          if (result == null || result.episodes.isEmpty) infoFuture = null;
          return result;
        });
  }

  // Shared per-refresh progress read: `'<S>-<E>'` → percent (0-100), with
  // finished plays clamped to exactly 100. The clamp is what makes the tiles'
  // watched tick (>= 100), the panel's landing rule and the hero Resume agree
  // — finished IPTV plays park a few percent shy of 1.0 and would otherwise
  // never tick. The short-lived memo exists because resumeInfoLoader and the
  // panel's watchProgressLoader fire together on open AND on every return
  // from playback, and each read decodes the (potentially large) shared
  // resume map — pay that once per refresh, not twice back-to-back.
  Future<Map<String, double>>? progressFuture;
  DateTime? progressAt;
  Future<Map<String, double>> progress() {
    final now = DateTime.now();
    final inFlight = progressFuture;
    if (inFlight != null &&
        progressAt != null &&
        now.difference(progressAt!) < const Duration(seconds: 2)) {
      return inFlight;
    }
    progressAt = now;
    return progressFuture = () async {
      final eps = (await info())?.episodes ?? const <XtreamSeriesEpisode>[];
      if (eps.isEmpty) return <String, double>{};
      final byUrl = await StorageService.getIptvProgressForUrls([
        for (final e in eps) e.url,
      ]);
      final map = <String, double>{};
      for (final e in eps) {
        final fraction = byUrl[e.url];
        if (fraction == null) continue;
        final percent = fraction >= StorageService.iptvWatchFinishedFraction
            ? 100.0
            : fraction * 100;
        final key = '${e.season}-${e.episode}';
        // Duplicate S-E entries (multi-part / SD+4K listings) share a key —
        // keep the furthest position.
        if (percent > (map[key] ?? 0)) map[key] = percent;
      }
      return map;
    }();
  }

  /// The resume target: last started episode in display order (Specials
  /// last), advanced past a finished one — or the first episode when nothing
  /// has been started. Same percent scale and thresholds as the episode
  /// panel's landing (values jump from <95 straight to the clamped 100, so
  /// the two can't disagree).
  Future<({bool started, XtreamSeriesEpisode? target})> resumeState() async {
    final eps = (await info())?.episodes ?? const <XtreamSeriesEpisode>[];
    if (eps.isEmpty) return (started: false, target: null);
    final ordered = [...eps]..sort(_episodesSpecialsLast);
    final percentByKey = await progress();
    int lastStarted = -1;
    for (var i = 0; i < ordered.length; i++) {
      final p = percentByKey['${ordered[i].season}-${ordered[i].episode}'] ?? 0;
      if (p > 0) lastStarted = i;
    }
    if (lastStarted < 0) return (started: false, target: ordered.first);
    final last = ordered[lastStarted];
    final p = percentByKey['${last.season}-${last.episode}'] ?? 0;
    final target = (p >= 95 && lastStarted + 1 < ordered.length)
        ? ordered[lastStarted + 1]
        : last;
    return (started: true, target: target);
  }

  // Launch latch — the page has no equivalent of the IPTV list's
  // _launchingChannel guard, and the async gap before the player starts
  // (info refetch + shelf write + activity launch) is long enough for a
  // second OK press to stack a second player instance.
  var launching = false;
  Future<void> guardedLaunch(Future<void> Function() body) async {
    if (launching) return;
    launching = true;
    try {
      await body();
    } finally {
      launching = false;
    }
  }

  Future<void> playEpisode(TraktEpisode episode) => guardedLaunch(() async {
    final eps = (await info())?.episodes ?? const <XtreamSeriesEpisode>[];
    XtreamSeriesEpisode? target;
    // The tapped tile's own URL is authoritative: panels routinely list
    // one episode number twice in a season (multi-part, SD+4K), and an
    // S-E lookup would always land on the first of the pair.
    final url = episode.playbackUrl;
    if (url != null && url.isNotEmpty) {
      for (final e in eps) {
        if (e.url == url) {
          target = e;
          break;
        }
      }
    }
    // S-E fallback for a URL that vanished from a refreshed episode list
    // (panels renumber episode ids).
    if (target == null) {
      for (final e in eps) {
        if (e.season == episode.season && e.episode == episode.number) {
          target = e;
          break;
        }
      }
    }
    if (target == null || !context.mounted) return;
    await _launchEpisode(context, playlist, series, eps, target);
  });

  Future<void> resumeAndPlay() => guardedLaunch(() async {
    final state = await resumeState();
    final target = state.target;
    if (!context.mounted) return;
    if (target == null) {
      // The page's primary CTA must never fail silently — on the phone
      // stacked layout the episode pane's retry state can be off-screen.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't load episodes from the provider — try again"),
        ),
      );
      return;
    }
    final eps = (await info())?.episodes ?? const <XtreamSeriesEpisode>[];
    if (!context.mounted) return;
    await _launchEpisode(context, playlist, series, eps, target);
  });

  final releaseDate = series.attributes['releaseDate'];
  final rating = double.tryParse(series.attributes['rating'] ?? '');
  final genres = series.attributes['genre']
      ?.split(RegExp(r'[,/]'))
      .map((g) => g.trim())
      .where((g) => g.isNotEmpty)
      .toList();

  final meta = StremioMeta(
    // Distinct namespace — never mistakable for an IMDb id, so every
    // effectiveImdbId guard on the page stays null and quietly no-ops.
    id: 'xtream-series:${playlist.id}:$seriesId',
    type: 'series',
    name: series.name,
    poster: series.logoUrl,
    background: series.attributes['backdrop'] ?? series.logoUrl,
    description: series.attributes['plot'],
    year: (releaseDate != null && releaseDate.length >= 4)
        ? releaseDate.substring(0, 4)
        : null,
    imdbRating: (rating != null && rating > 0) ? rating : null,
    genres: (genres == null || genres.isEmpty) ? null : genres,
  );

  // Stub addon (no base/manifest URL) — same shape Trakt-sourced items carry.
  // Irrelevant in direct-source mode (the seasonsLoader is the sole episode
  // source), but the page requires one.
  final addon = StremioAddon(
    id: 'xtream-iptv',
    name: playlist.name,
    manifestUrl: '',
    baseUrl: '',
    types: const ['series'],
    resources: const [],
  );

  Future<List<TraktSeason>> seasonsLoader() async {
    final eps = (await info())?.episodes ?? const <XtreamSeriesEpisode>[];
    // Throwing (not returning []) keeps the distinction the panel draws
    // between "loaded, zero seasons" and "couldn't load" honest — both land
    // on the retry panel, and Retry re-fetches because the memo was cleared.
    if (eps.isEmpty) throw Exception('Series info unavailable');
    final bySeason = <int, List<TraktEpisode>>{};
    for (final e in eps) {
      bySeason
          .putIfAbsent(e.season, () => [])
          .add(
            TraktEpisode(
              season: e.season,
              number: e.episode,
              title: e.title,
              overview: e.plot,
              firstAired: e.airDate,
              runtime: e.durationSecs != null
                  ? (e.durationSecs! / 60).round()
                  : null,
              thumbnailUrl: e.thumbnailUrl,
              rating: e.rating,
              playbackUrl: e.url,
            ),
          );
    }
    return [
      for (final entry in bySeason.entries)
        TraktSeason(
          number: entry.key,
          episodeCount: entry.value.length,
          episodes: entry.value..sort((a, b) => a.number.compareTo(b.number)),
        ),
    ]..sort(seasonsSpecialsLast);
  }

  await Navigator.of(context).push(
    MaterialPageRoute(
      settings: const RouteSettings(name: kCatalogDetailRouteName),
      builder: (_) => MergedDetailScreen(
        item: meta,
        addon: addon,
        isTelevision: isTelevision,
        showQuickPlay: true,
        onResume: resumeAndPlay,
        resumeInfoLoader: () async {
          final state = await resumeState();
          return (
            started: state.started,
            season: state.target?.season,
            episode: state.target?.episode,
          );
        },
        seasonsLoader: seasonsLoader,
        onPlayEpisode: playEpisode,
        watchProgressLoader: progress,
      ),
    ),
  );
}

/// The Xtream series id for a series channel: the stamped attribute, else the
/// `xtream-series://<id>` grid-sentinel's id. NOT parsed from the Continue
/// Watching sentinel (`xtream-series://<origin>/<id>`) — those rows always
/// carry the `series_id` attribute, so the attribute branch wins first.
String _seriesIdOf(IptvChannel series) =>
    series.attributes['series_id'] ??
    (series.url.startsWith('xtream-series://')
        ? series.url.substring('xtream-series://'.length)
        : '');

/// Display order for episodes: season ascending with Specials (season 0)
/// last, then episode number — the flat-episode counterpart of
/// [seasonsSpecialsLast].
int _episodesSpecialsLast(XtreamSeriesEpisode a, XtreamSeriesEpisode b) {
  final aSpecial = a.season == 0, bSpecial = b.season == 0;
  if (aSpecial != bSpecial) return aSpecial ? 1 : -1;
  if (a.season != b.season) return a.season.compareTo(b.season);
  return a.episode.compareTo(b.episode);
}

/// Launch an episode in the regular IPTV on-demand pipeline: recorded to the
/// continue-watching shelf before launch (the player process can be killed
/// outright on TV), played with the WHOLE series as the in-player list so
/// next/previous/auto-advance walk across seasons, resumed by URL like any
/// IPTV VOD item.
Future<void> _launchEpisode(
  BuildContext context,
  IptvPlaylist playlist,
  IptvChannel series,
  List<XtreamSeriesEpisode> all,
  XtreamSeriesEpisode target,
) async {
  final seriesId = _seriesIdOf(series);
  // The in-player list is the WHOLE series (Specials-last, matching the resume/
  // landing order), NOT just the target's season — so Next / auto-advance
  // cross season boundaries (S1 finale → S2E1) instead of dead-ending.
  final ordered = [...all]..sort(_episodesSpecialsLast);
  final channels = ordered.asMap().entries.map((entry) {
    final index = entry.key;
    final e = entry.value;
    return IptvChannel(
      name: _episodeDisplayName(series.name, e),
      url: e.url,
      logoUrl: (e.thumbnailUrl?.isNotEmpty ?? false)
          ? e.thumbnailUrl
          : series.logoUrl,
      group: series.name,
      contentType: 'vod',
      // Series identity so the player can key per-series audio memory the
      // same way Continue Watching does (<playlistId>::<seriesId>), instead
      // of the collision-prone display name.
      attributes: {
        if (seriesId.isNotEmpty) 'series_id': seriesId,
        'series_playlist_id': playlist.id,
        'series_name': series.name,
        'season': e.season.toString(),
        'episode': e.episode.toString(),
        'has_next_episode': ordered
            .skip(index + 1)
            .any((episode) => episode.season != 0)
            .toString(),
      },
    );
  }).toList();
  var index = ordered.indexWhere((e) => e.url == target.url);
  if (index < 0) index = 0;

  // Series marker for the Continue Watching "keep after finish" rule. hasNext =
  // there is a later REAL (non-special) episode after this one. A trailing
  // season-0 special must NOT count, or a completed show that has specials
  // would register hasNext=true on its finale and never age out of the shelf.
  final hasNext = ordered.skip(index + 1).any((e) => e.season != 0);

  await StorageService.recordIptvWatch(
    target.url,
    channelName: _episodeDisplayName(series.name, target),
    logoUrl: series.logoUrl,
    group: series.name,
    playlistId: playlist.id,
    seriesId: seriesId.isEmpty ? null : seriesId,
    seriesName: series.name,
    season: target.season,
    episode: target.episode,
    hasNextEpisode: hasNext,
  );
  if (!context.mounted) return;

  await VideoPlayerLauncher.push(
    context,
    VideoPlayerLaunchArgs(
      videoUrl: target.url,
      title: _episodeDisplayName(series.name, target),
      subtitle: series.name,
      viewMode: PlaylistViewMode.sorted,
      iptvChannels: channels,
      iptvStartIndex: index,
      httpHeaders: channels[index].playbackHeaders,
    ),
  );
}

String _episodeDisplayName(String seriesName, XtreamSeriesEpisode e) {
  final code =
      'S${e.season.toString().padLeft(2, '0')}'
      'E${e.episode.toString().padLeft(2, '0')}';
  final title = e.title.trim();
  if (title.isEmpty) return '$seriesName · $code';
  // Panels routinely bake "Show Name S01 E01" into episode titles — don't
  // double the show name around those.
  if (title.toLowerCase().contains(seriesName.trim().toLowerCase())) {
    return title;
  }
  return '$seriesName · $code · $title';
}
