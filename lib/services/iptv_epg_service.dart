import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/iptv_playlist.dart';
import 'xmltv_epg_source.dart';

/// One programme in a channel's guide.
class EpgProgramme {
  final String title;
  final String description;
  final DateTime start;
  final DateTime stop;

  /// Xtream: the panel recorded this programme (catchup/timeshift replay).
  final bool hasArchive;

  /// Xtream: the listing's raw `start` string, verbatim — panel-LOCAL time
  /// ("2026-07-26 20:00:00"). The timeshift endpoint wants its start in
  /// panel-local time too, so replay URLs are built from this string rather
  /// than converting our epoch back through timezone guesswork. Null for
  /// XMLTV programmes (no catchup there).
  final String? rawStart;

  const EpgProgramme({
    required this.title,
    required this.description,
    required this.start,
    required this.stop,
    this.hasArchive = false,
    this.rawStart,
  });

  bool airsAt(DateTime t) => !t.isBefore(start) && t.isBefore(stop);

  /// 0-1 elapsed fraction at [t], clamped.
  double progressAt(DateTime t) {
    final total = stop.difference(start).inSeconds;
    if (total <= 0) return 0;
    return (t.difference(start).inSeconds / total).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toBridgeMap() => {
        'title': title,
        'description': description,
        'startMs': start.millisecondsSinceEpoch,
        'stopMs': stop.millisecondsSinceEpoch,
      };
}

/// The focused channel's current and upcoming programme. Either side can be
/// null — panels routinely have gaps in their guide data.
class EpgNowNext {
  final EpgProgramme? now;
  final EpgProgramme? next;
  const EpgNowNext({this.now, this.next});

  bool get isEmpty => now == null && next == null;
}

/// Outcome of activating a playlist's XMLTV guide. The page uses this to
/// explain the silent-failure cases ("guide loaded, nothing matched") that
/// non-technical users otherwise report as "EPG doesn't work".
enum M3uEpgStatus {
  /// No guide URL, nothing to match, or superseded by a newer load.
  inactive,

  /// Guide active: at least one channel got programmes.
  matched,

  /// Guide downloaded and parsed, but not one channel matched by id or name.
  noMatch,

  /// Channels DID pair up (by id or name), but no programmes survived the
  /// time window — the guide is stale/empty, not mismatched.
  noProgrammes,

  /// Download/parse failed and no snapshot could stand in.
  failed,
}

/// Xtream credentials recovered from a live-stream URL.
class _XtreamRef {
  final String server;
  final String username;
  final String password;
  final String streamId;
  const _XtreamRef(this.server, this.username, this.password, this.streamId);
}

/// Per-channel EPG via the Xtream Codes per-stream endpoints
/// (`get_short_epg` / `get_simple_data_table`) — no database, no XMLTV
/// download, no bulk ingest.
///
/// Credentials are recovered from the channel's own stream URL
/// (`server/live/user/pass/id.m3u8`), so any caller holding a channel URL can
/// ask for guide data with no playlist plumbing — including the native TV
/// player over the platform channel. Failures and channels without guide data
/// both come back as empty results, never as errors: EPG is decoration, and
/// nothing should break when a panel has none.
class IptvEpgService {
  static final IptvEpgService instance = IptvEpgService._();
  IptvEpgService._();

  /// A known-player UA for panel API calls: Xtream panels behind WAFs
  /// (Cloudflare et al) routinely challenge generic/unknown User-Agents
  /// while allowlisting recognizable IPTV players — the same reason
  /// IPTVnator sends exactly this string on player_api requests.
  static const _headers = {'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18'};
  static const _timeout = Duration(seconds: 10);

  /// At most this many per-stream EPG fetches in flight. Panels rate-limit
  /// (or ban) clients that fire one request per row while a user scrolls a
  /// big guide — production clients throttle here (IPTVnator caps at 2).
  static const _maxConcurrentFetches = 3;

  /// Ceiling on time spent QUEUED for a slot. Without it a burst of row
  /// fetches gives the queue tail unbounded latency (N/3 × the 10s request
  /// timeout) — worse than the pre-throttle world. A caller that can't get
  /// a slot promptly answers empty and lets the row's normal retry re-ask.
  static const _slotWaitTimeout = Duration(seconds: 15);
  int _activeFetches = 0;
  final List<Completer<void>> _fetchWaiters = [];

  Future<T> _withFetchSlot<T>(Future<T> Function() run) async {
    while (_activeFetches >= _maxConcurrentFetches) {
      final waiter = Completer<void>();
      _fetchWaiters.add(waiter);
      try {
        await waiter.future.timeout(_slotWaitTimeout);
      } on TimeoutException {
        // Leave the queue. If the wake raced the timeout (we were already
        // dequeued and completed), pass the wake on so it isn't lost.
        final wasQueued = _fetchWaiters.remove(waiter);
        if (!wasQueued &&
            _activeFetches < _maxConcurrentFetches &&
            _fetchWaiters.isNotEmpty) {
          _fetchWaiters.removeAt(0).complete();
        }
        rethrow;
      }
    }
    _activeFetches++;
    try {
      return await run();
    } finally {
      _activeFetches--;
      if (_fetchWaiters.isNotEmpty) {
        _fetchWaiters.removeAt(0).complete();
      }
    }
  }

  /// Now/next per channel URL. An entry with a running `now` programme stays
  /// valid until that programme ends; empty answers are held briefly so
  /// arrowing over a guideless panel doesn't hammer it.
  final LinkedHashMap<String, _CachedNowNext> _nowNextCache = LinkedHashMap();
  static const _emptyNowNextTtl = Duration(minutes: 5);
  static const _maxNowNextEntries = 400;

  final LinkedHashMap<String, _CachedSchedule> _scheduleCache = LinkedHashMap();
  static const _scheduleTtl = Duration(minutes: 30);
  static const _maxScheduleEntries = 24;

  // In-flight coalescing: the rail, the row, and the player can all ask for
  // the same channel at once.
  final Map<String, Future<EpgNowNext>> _nowNextInFlight = {};
  final Map<String, Future<List<EpgProgramme>>> _scheduleInFlight = {};

  // ── XMLTV context (plain M3U playlists) ──────────────────────────────────
  //
  // One playlist's guide is active at a time — the page loads playlists one
  // at a time, and a player session carries that playlist's channels. The
  // index is the already-windowed programme list per tvg-id, held in memory
  // (a few MB after filtering); lookups compute now/next fresh on every ask,
  // which is what lets the rail roll programmes with no re-fetch at all.
  Map<String, String> _m3uUrlToTvgId = const {};

  /// Name-fallback candidates per channel URL, normalized, in Kodi's pass
  /// order: tvg-name first, then the channel's display name.
  Map<String, List<String>> _m3uUrlToNames = const {};

  /// Normalized name → XMLTV channel id, resolved by the parser against the
  /// guide's `<display-name>`s.
  Map<String, String> _xmltvNameToId = const {};
  Map<String, List<EpgProgramme>>? _xmltvIndex;

  /// Guards the claim-then-await in [setM3uEpgContext]. A playlist-key
  /// comparison couldn't: two overlapping loads of the SAME playlist
  /// (refresh) would pass a key-equality check, letting the older download
  /// finish last and pair current rows with an outdated URL→id map.
  int _m3uContextGeneration = 0;

  /// Bumped whenever the XMLTV context changes. Guide data arrives long
  /// after rows and the rail painted (a first download can take minutes);
  /// listeners re-check capability instead of waiting for a focus move.
  final ValueNotifier<int> contextVersion = ValueNotifier<int>(0);

  /// Activate XMLTV guide data for a just-loaded M3U playlist. Downloads (or
  /// reads the disk snapshot of) the guide at [epgUrl], filtered to the
  /// playlist's tvg-ids AND its channel names — the Kodi-style fallback so
  /// playlists and guides from different providers still pair up. Returns
  /// [M3uEpgStatus.matched] when any channel got programmes — the caller
  /// re-renders its rows then, since capability changed — and the failure
  /// flavors otherwise so the page can say WHY there's no guide.
  Future<M3uEpgStatus> setM3uEpgContext({
    required String playlistKey,
    required String? epgUrl,
    required List<IptvChannel> channels,
  }) async {
    clearM3uEpgContext();
    final url = epgUrl?.trim();
    if (url == null || url.isEmpty) return M3uEpgStatus.inactive;

    final urlToId = <String, String>{};
    final ids = <String>{};
    final urlToNames = <String, List<String>>{};
    final wantedNames = <String>{};
    for (final channel in channels) {
      if (!channel.isLive) continue;
      final id = channel.tvgId?.trim();
      if (id != null && id.isNotEmpty) {
        urlToId[channel.url] = id;
        ids.add(id);
        // iptv-org-style playlists suffix a feed onto the id (BBCOne.uk@SD)
        // while guides typically publish the bare id (BBCOne.uk). Admit both
        // forms into the parser's filter; lookup tries exact first.
        final bare = stripFeedSuffix(id);
        if (bare != id) ids.add(bare);
      }
      // Name candidates for every channel — ids stay authoritative, names
      // only ever fill gaps (no tvg-id, or ids the guide doesn't use).
      final candidates = <String>[];
      for (final raw in [channel.tvgName, channel.name]) {
        final norm = XmltvEpgSource.normalizeChannelName(raw ?? '');
        if (norm.isNotEmpty && !candidates.contains(norm)) {
          candidates.add(norm);
        }
      }
      if (candidates.isNotEmpty) {
        urlToNames[channel.url] = candidates;
        wantedNames.addAll(candidates);
      }
    }
    if (ids.isEmpty && wantedNames.isEmpty) return M3uEpgStatus.inactive;

    // Claim the context before the (potentially long) load so any newer
    // claim — a playlist switch OR a reload of this same playlist — wins
    // and this result gets dropped.
    final generation = ++_m3uContextGeneration;
    final guide = await XmltvEpgSource.load(
      epgUrl: url,
      tvgIds: ids,
      channelNames: wantedNames,
    );
    if (generation != _m3uContextGeneration) return M3uEpgStatus.inactive;
    if (guide == null) return M3uEpgStatus.failed;
    if (guide.byId.isEmpty) {
      // Blame accurately: if <channel> elements did pair with the playlist,
      // the problem is the guide's programme data, not the ids/names.
      return guide.sawWantedChannel
          ? M3uEpgStatus.noProgrammes
          : M3uEpgStatus.noMatch;
    }

    _m3uUrlToTvgId = urlToId;
    _m3uUrlToNames = urlToNames;
    _xmltvNameToId = guide.nameToId;
    _xmltvIndex = {
      for (final entry in guide.byId.entries)
        entry.key: [
          for (final row in entry.value)
            EpgProgramme(
              title: row[2] as String,
              description: row[3] as String,
              start: DateTime.fromMillisecondsSinceEpoch(row[0] as int),
              stop: DateTime.fromMillisecondsSinceEpoch(row[1] as int),
            ),
        ],
    };
    contextVersion.value++;
    return M3uEpgStatus.matched;
  }

  /// Drop the active XMLTV context (playlist switched away).
  void clearM3uEpgContext() {
    final hadIndex = _xmltvIndex != null;
    _m3uContextGeneration++;
    _m3uUrlToTvgId = const {};
    _m3uUrlToNames = const {};
    _xmltvNameToId = const {};
    _xmltvIndex = null;
    if (hadIndex) contextVersion.value++;
  }

  /// The active XMLTV programme list for a channel URL, or null when the
  /// channel isn't covered by the loaded guide. Kodi's pass order: exact
  /// tvg-id first (a guide that really does publish per-feed ids can never
  /// be shadowed), then the feed-suffix-stripped id, then the normalized
  /// tvg-name, then the normalized channel name. Id lookups are lowercased —
  /// the parser canonicalizes the index's keys the same way, giving the
  /// case-insensitive matching Kodi defaults to.
  List<EpgProgramme>? _xmltvProgrammesFor(String channelUrl) {
    final index = _xmltvIndex;
    if (index == null) return null;
    List<EpgProgramme>? programmes;
    final tvgId = _m3uUrlToTvgId[channelUrl]?.toLowerCase();
    if (tvgId != null) {
      programmes = index[tvgId];
      if (programmes == null || programmes.isEmpty) {
        final bare = stripFeedSuffix(tvgId);
        if (bare != tvgId) programmes = index[bare];
      }
    }
    if (programmes == null || programmes.isEmpty) {
      for (final name in _m3uUrlToNames[channelUrl] ?? const <String>[]) {
        final id = _xmltvNameToId[name];
        if (id == null) continue;
        programmes = index[id];
        if (programmes != null && programmes.isNotEmpty) break;
      }
    }
    return (programmes == null || programmes.isEmpty) ? null : programmes;
  }

  /// `BBCOne.uk@SD` → `BBCOne.uk`. iptv-org playlists append the feed
  /// (`@SD`/`@HD`/…) to the channel id; guide files usually don't. Ids
  /// without an `@` (or with a leading one) pass through unchanged.
  @visibleForTesting
  static String stripFeedSuffix(String tvgId) {
    final at = tvgId.indexOf('@');
    return at > 0 ? tvgId.substring(0, at) : tvgId;
  }

  // ── Catchup (Xtream timeshift) ───────────────────────────────────────────

  /// Which timeshift URL form this panel serves — probed once per server,
  /// like XtreamCodesService does for live URL forms.
  final Map<String, _CatchupForm> _catchupFormCache = {};

  /// Whether [programme] on [channel] can be replayed from the panel's
  /// archive: the panel recorded it (`has_archive`), it has finished airing,
  /// the channel isn't explicitly archive-off, it still sits inside the
  /// channel's archive window, and the URL carries Xtream credentials.
  /// XMLTV programmes never qualify (hasArchive is always false there).
  static bool isCatchupAvailable(IptvChannel channel, EpgProgramme programme) {
    if (!programme.hasArchive) return false;
    final now = DateTime.now();
    if (!programme.stop.isBefore(now)) return false; // airing or future
    // Explicit deny only — favorites-rebuilt channels carry no attributes,
    // and the per-programme flag is the more precise signal anyway.
    if (channel.attributes['tv_archive'] == '0') return false;
    final days =
        int.tryParse(channel.attributes['tv_archive_duration'] ?? '') ?? 0;
    if (days > 0 &&
        programme.start.isBefore(now.subtract(Duration(days: days)))) {
      return false;
    }
    return _parseXtreamUrl(channel.url) != null;
  }

  /// The timeshift `start` parameter: `YYYY-MM-DD:HH-MM` in PANEL-local
  /// time. Prefer the listing's own raw start string (already panel-local);
  /// fall back to our local clock rendering of the parsed start — right
  /// whenever panel and device share a timezone.
  @visibleForTesting
  static String catchupStart(EpgProgramme programme) {
    final raw = programme.rawStart?.trim();
    if (raw != null) {
      final match = RegExp(r'^(\d{4}-\d{2}-\d{2})[ T](\d{2}):(\d{2})')
          .firstMatch(raw);
      if (match != null) {
        return '${match.group(1)}:${match.group(2)}-${match.group(3)}';
      }
    }
    final s = programme.start;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${s.year}-${two(s.month)}-${two(s.day)}:${two(s.hour)}-${two(s.minute)}';
  }

  /// Resolve a playable replay URL for [programme] on the channel behind
  /// [channelUrl], probing the panel's timeshift dialects on first use
  /// (modern `/timeshift/user/pass/min/start/id.ts|.m3u8` path forms, then
  /// the legacy `streaming/timeshift.php` query form). Null when the panel
  /// answers none of them — the caller shows "replay not available".
  Future<String?> catchupUrl(String channelUrl, EpgProgramme programme) async {
    final ref = _parseXtreamUrl(channelUrl);
    if (ref == null) return null;

    final start = catchupStart(programme);
    // Round the duration UP — inMinutes truncation would shave up to 59s
    // off the end of the replay.
    final minutes =
        ((programme.stop.difference(programme.start).inSeconds + 59) ~/ 60)
            .clamp(1, 24 * 60);
    final user = Uri.encodeComponent(ref.username);
    final pass = Uri.encodeComponent(ref.password);

    String urlFor(_CatchupForm form) => switch (form) {
          _CatchupForm.pathTs =>
            '${ref.server}/timeshift/$user/$pass/$minutes/$start/${ref.streamId}.ts',
          _CatchupForm.pathM3u8 =>
            '${ref.server}/timeshift/$user/$pass/$minutes/$start/${ref.streamId}.m3u8',
          _CatchupForm.php =>
            '${ref.server}/streaming/timeshift.php?username=$user&password=$pass'
                '&stream=${ref.streamId}&start=$start&duration=$minutes',
        };

    final cached = _catchupFormCache[ref.server];
    if (cached != null) return urlFor(cached);

    for (final form in _CatchupForm.values) {
      final status = await _probeStatus(urlFor(form));
      if (status == _probeUnreachable) {
        // Connection-level failure — the panel itself is down; probing the
        // remaining forms would just stack failures. Don't cache a verdict.
        return null;
      }
      // A TIMEOUT (as opposed to refused/DNS-dead) keeps probing: some
      // panels hang on the unsupported dialect's path instead of 404ing,
      // and the next form may answer instantly.
      if (status != null && status >= 200 && status < 300) {
        _catchupFormCache[ref.server] = form;
        return urlFor(form);
      }
    }
    return null;
  }

  static const int _probeUnreachable = -1;

  /// Status-only GET (the body may be the stream itself — never buffer it).
  /// Returns the status code, null on timeout, or [_probeUnreachable] on a
  /// connection-level failure (refused, DNS) — callers treat those
  /// differently: a hang is per-URL, a dead socket is per-server.
  Future<int?> _probeStatus(String url) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] = kIptvDefaultUserAgent;
      final response =
          await client.send(request).timeout(const Duration(seconds: 10));
      await response.stream.listen((_) {}).cancel();
      return response.statusCode;
    } on TimeoutException {
      debugPrint('IptvEpgService: catchup probe timed out for $url');
      return null;
    } catch (e) {
      debugPrint('IptvEpgService: catchup probe failed for $url: $e');
      return _probeUnreachable;
    } finally {
      client.close();
    }
  }

  // ── Capability + lookups ──────────────────────────────────────────────────

  /// Whether [channel] can have guide data at all: a live channel whose URL
  /// carries recoverable Xtream credentials, or one covered by the loaded
  /// XMLTV guide.
  static bool isEpgCapable(IptvChannel channel) =>
      channel.isLive &&
      (_parseXtreamUrl(channel.url) != null ||
          instance._xmltvProgrammesFor(channel.url) != null);

  /// URL-only variant for callers without an [IptvChannel] (the native
  /// player's bridge sends bare URLs).
  static bool isEpgCapableUrl(String url) =>
      _parseXtreamUrl(url) != null ||
      instance._xmltvProgrammesFor(url) != null;

  /// The panel's whole-account XMLTV guide URL (`xmltv.php`) recovered from a
  /// live-stream URL, or null when [channelUrl] doesn't carry Xtream
  /// credentials. Lets a plain-M3U playlist that is really an Xtream `get.php`
  /// export get its guide with zero configuration — the same source TiviMate
  /// uses for Xtream playlists.
  static String? xmltvUrlForChannelUrl(String channelUrl) {
    final ref = _parseXtreamUrl(channelUrl);
    if (ref == null) return null;
    return xmltvUrlFor(ref.server, ref.username, ref.password);
  }

  /// The `xmltv.php` guide URL for explicit Xtream credentials.
  static String xmltvUrlFor(String server, String username, String password) {
    final user = Uri.encodeQueryComponent(username);
    final pass = Uri.encodeQueryComponent(password);
    return '$server/xmltv.php?username=$user&password=$pass';
  }

  /// Cached now/next if fresh — synchronous, for paint-before-fetch UIs.
  /// XMLTV answers are computed live from the local index, so they are
  /// always "fresh" and roll programme boundaries by themselves. An EMPTY
  /// XMLTV pick on an Xtream channel falls through to the endpoint cache —
  /// a guide gap must not silence a per-stream answer that exists (thin
  /// xmltv.php files with live get_short_epg are a real panel shape).
  EpgNowNext? peekNowNext(String channelUrl) {
    final xmltv = _xmltvProgrammesFor(channelUrl);
    if (xmltv != null) {
      final pick = _pickNowNext(xmltv, DateTime.now());
      if (!pick.isEmpty || _parseXtreamUrl(channelUrl) == null) return pick;
    }
    final cached = _nowNextCache[channelUrl];
    if (cached == null || cached.isStale) return null;
    return cached.value;
  }

  /// Fetch (or serve cached) now/next for a channel. Returns an empty
  /// [EpgNowNext] when the panel has no data or the request fails.
  Future<EpgNowNext> nowNext(String channelUrl) {
    final xmltv = _xmltvProgrammesFor(channelUrl);
    if (xmltv != null) {
      final pick = _pickNowNext(xmltv, DateTime.now());
      // Same fallthrough rule as peekNowNext: an Xtream channel in a guide
      // gap still gets to ask its per-stream endpoint.
      if (!pick.isEmpty || _parseXtreamUrl(channelUrl) == null) {
        return Future.value(pick);
      }
    }

    final cached = _nowNextCache[channelUrl];
    if (cached != null && !cached.isStale) return Future.value(cached.value);

    final inFlight = _nowNextInFlight[channelUrl];
    if (inFlight != null) return inFlight;

    final future = _fetchNowNext(channelUrl).whenComplete(() {
      _nowNextInFlight.remove(channelUrl);
    });
    _nowNextInFlight[channelUrl] = future;
    return future;
  }

  /// Fetch (or serve cached) the day schedule for a channel, sorted by start
  /// time and trimmed to yesterday-late-night through the guide's horizon.
  ///
  /// Source order differs from now/next on purpose: for Xtream channels the
  /// per-stream data table comes FIRST — its listings carry the has_archive
  /// flags catchup replay needs (XMLTV rows never do) and are the panel's
  /// freshest data — with the XMLTV index as the fallback for panels whose
  /// data-table endpoints are broken or empty. Pure-M3U channels only ever
  /// have the XMLTV index.
  Future<List<EpgProgramme>> schedule(String channelUrl) {
    final xmltv = _xmltvProgrammesFor(channelUrl);
    if (xmltv != null && _parseXtreamUrl(channelUrl) == null) {
      return Future.value(xmltv);
    }

    final cached = _scheduleCache[channelUrl];
    if (cached != null && !cached.isStale) return Future.value(cached.value);

    final inFlight = _scheduleInFlight[channelUrl];
    if (inFlight != null) return inFlight;

    final future = _fetchSchedule(channelUrl).whenComplete(() {
      _scheduleInFlight.remove(channelUrl);
    });
    _scheduleInFlight[channelUrl] = future;
    return future;
  }

  Future<EpgNowNext> _fetchNowNext(String channelUrl) async {
    const empty = EpgNowNext();
    final ref = _parseXtreamUrl(channelUrl);
    if (ref == null) return empty;

    final listings = await _fetchListings(ref, 'get_short_epg', '&limit=8');
    final result = _pickNowNext(listings, DateTime.now());
    _storeNowNext(channelUrl, result);
    return result;
  }

  Future<List<EpgProgramme>> _fetchSchedule(String channelUrl) async {
    final ref = _parseXtreamUrl(channelUrl);
    if (ref == null) return const [];

    var listings = await _fetchListings(ref, 'get_simple_data_table', '');
    if (listings.isEmpty) {
      // Old panels shipped this endpoint under a typo'd action name;
      // production clients fall back to it when the real one is empty.
      listings = await _fetchListings(ref, 'get_simple_date_table', '');
    }
    // Panels differ wildly in horizon; some return a week of history. Keep
    // from a couple of hours back (context for "what did I just miss") to
    // whatever future the panel serves, capped so the UI stays bounded.
    final now = DateTime.now();
    final floor = now.subtract(const Duration(hours: 3));
    listings = [
      for (final p in listings)
        if (p.stop.isAfter(floor)) p,
    ];
    listings.sort((a, b) => a.start.compareTo(b.start));
    if (listings.length > 250) listings = listings.sublist(0, 250);

    // An empty answer here is as likely a timeout as a truly guideless
    // channel. Don't cache it (a schedule open is an explicit action — let
    // the next one retry), and above all don't let it clobber a fresh,
    // correct now/next that get_short_epg already delivered to the rail.
    // When an XMLTV guide covers the channel, its rows stand in — the
    // no-catchup trade only applies to panels whose data table failed.
    if (listings.isEmpty) {
      return _xmltvProgrammesFor(channelUrl) ?? const [];
    }

    _scheduleCache.remove(channelUrl);
    _scheduleCache[channelUrl] = _CachedSchedule(listings);
    while (_scheduleCache.length > _maxScheduleEntries) {
      _scheduleCache.remove(_scheduleCache.keys.first);
    }

    // The schedule is a superset of now/next — reuse it so opening a
    // schedule also freshens the rail card for free.
    _storeNowNext(channelUrl, _pickNowNext(listings, now));
    return listings;
  }

  void _storeNowNext(String channelUrl, EpgNowNext value) {
    _nowNextCache.remove(channelUrl); // re-insert to refresh LRU order
    _nowNextCache[channelUrl] = _CachedNowNext(value);
    while (_nowNextCache.length > _maxNowNextEntries) {
      _nowNextCache.remove(_nowNextCache.keys.first);
    }
  }

  /// GET one of the per-stream EPG actions and decode its `epg_listings`.
  Future<List<EpgProgramme>> _fetchListings(
    _XtreamRef ref,
    String action,
    String extraQuery,
  ) async {
    final user = Uri.encodeQueryComponent(ref.username);
    final pass = Uri.encodeQueryComponent(ref.password);
    final url = '${ref.server}/player_api.php?username=$user&password=$pass'
        '&action=$action&stream_id=${ref.streamId}$extraQuery';
    try {
      final response = await _withFetchSlot(() async {
        // A dedicated client, closed on the way out: `.timeout` abandons the
        // future but NOT the socket, so a shared client would keep zombie
        // connections open past the slot release — the real concurrency the
        // gate exists to bound. close() tears the connection down with it.
        final client = http.Client();
        try {
          return await client
              .get(Uri.parse(url), headers: _headers)
              .timeout(_timeout);
        } finally {
          client.close();
        }
      });
      if (response.statusCode != 200) return const [];

      final decoded = jsonDecode(response.body);
      var listings = decoded is Map<String, dynamic>
          ? decoded['epg_listings']
          : decoded; // some panels answer with a bare array
      // PHP panels that build the listings as an associative array serve a
      // JSON *object* keyed by index instead of a list. Same rows, different
      // container — flatten it rather than reading it as "no guide".
      if (listings is Map) listings = listings.values.toList();
      if (listings is! List) return const [];

      final programmes = <EpgProgramme>[];
      for (final item in listings) {
        if (item is! Map) continue;
        final programme = _parseProgramme(item);
        if (programme != null) programmes.add(programme);
      }
      return programmes;
    } catch (e) {
      debugPrint('IptvEpgService: $action failed for ${ref.server}: $e');
      return const [];
    }
  }

  static EpgProgramme? _parseProgramme(Map<dynamic, dynamic> item) {
    final start = _parseTime(item['start_timestamp'], item['start']);
    final stop = _parseTime(item['stop_timestamp'], item['end'] ?? item['stop']);
    if (start == null || stop == null || !stop.isAfter(start)) return null;

    final title = _decodeXtreamText(item['title']);
    if (title.isEmpty) return null;
    final archive = item['has_archive'];
    return EpgProgramme(
      title: title,
      description: _decodeXtreamText(item['description']),
      start: start,
      stop: stop,
      hasArchive: archive == 1 || archive == '1' || archive == true,
      rawStart: item['start'] is String ? item['start'] as String : null,
    );
  }

  /// Prefer the unix timestamp (unambiguous UTC); fall back to the
  /// `yyyy-MM-dd HH:mm:ss` string, which panels serve in their local time —
  /// close enough when it's all we have.
  static DateTime? _parseTime(dynamic timestamp, dynamic text) {
    final seconds = switch (timestamp) {
      num n => n.toInt(),
      String s => int.tryParse(s),
      _ => null,
    };
    if (seconds != null && seconds > 0) {
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    }
    if (text is String && text.isNotEmpty) {
      return DateTime.tryParse(text.replaceFirst(' ', 'T'));
    }
    return null;
  }

  /// Xtream serves EPG text base64-encoded; some panels don't. Decode when it
  /// decodes cleanly, otherwise take the text as-is.
  ///
  /// The discriminator is the decoded BYTES, not the input shape: any short
  /// alphanumeric title ("NCIS", "Live") is also syntactically valid base64,
  /// but its decode lands on control characters — real encoded text doesn't.
  /// Accepted input covers what real panels emit: standard and url-safe
  /// alphabets, padded or not (base64.normalize repairs both), UTF-8 payloads
  /// first and Latin-1 as the fallback (legacy panels base64-encode
  /// ISO-8859-1 titles — 'Fußball' must not render as a base64 blob).
  static String _decodeXtreamText(dynamic value) {
    if (value is! String || value.isEmpty) return '';
    final raw = value.trim();
    final compact = raw.replaceAll(RegExp(r'\s'), '');
    if (compact.length < 4 ||
        !RegExp(r'^[A-Za-z0-9+/_-]+={0,2}$').hasMatch(compact)) {
      return raw;
    }
    final List<int> bytes;
    try {
      bytes = base64Decode(base64.normalize(compact));
    } catch (_) {
      return raw;
    }
    // C0 controls (except the newlines multiline descriptions carry) and the
    // C1 range mean this was readable text that merely looked like base64.
    bool looksBinary(Iterable<int> runes) => runes.any(
          (r) => (r < 0x20 && r != 0x0a && r != 0x0d) || (r >= 0x7f && r <= 0x9f),
        );
    try {
      final decoded = utf8.decode(bytes).trim();
      if (decoded.isEmpty || looksBinary(decoded.runes)) return raw;
      return decoded;
    } catch (_) {
      final decoded = latin1.decode(bytes).trim();
      if (decoded.isEmpty || looksBinary(decoded.runes)) return raw;
      return decoded;
    }
  }

  static EpgNowNext _pickNowNext(List<EpgProgramme> listings, DateTime at) {
    EpgProgramme? now;
    EpgProgramme? next;
    for (final p in listings) {
      if (p.airsAt(at)) {
        // Overlapping data: keep the tightest-fitting programme.
        if (now == null || p.start.isAfter(now.start)) now = p;
      } else if (p.start.isAfter(at)) {
        if (next == null || p.start.isBefore(next.start)) next = p;
      }
    }
    return EpgNowNext(now: now, next: next);
  }

  /// Recover Xtream credentials from a live URL. Two panel URL shapes exist
  /// (see XtreamCodesService._LiveUrlForm): `server/live/user/pass/id.ext`
  /// and the legacy un-prefixed `server/user/pass/id.ext`, with `ext` one of
  /// m3u8/ts. Anything else — plain M3U entries, Stremio keys, VOD movie
  /// URLs — is not EPG-capable. A same-shaped non-Xtream URL merely yields an
  /// empty fetch, which the negative cache absorbs.
  static _XtreamRef? _parseXtreamUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return null;
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    final String user, pass, last;
    if (segments.length == 4 && segments[0] == 'live') {
      user = segments[1];
      pass = segments[2];
      last = segments[3];
    } else if (segments.length == 3) {
      user = segments[0];
      pass = segments[1];
      last = segments[2];
    } else {
      return null;
    }

    final dot = last.lastIndexOf('.');
    if (dot <= 0) return null;
    final streamId = last.substring(0, dot);
    final ext = last.substring(dot + 1).toLowerCase();
    if (ext != 'm3u8' && ext != 'ts') return null;
    if (int.tryParse(streamId) == null) return null;
    if (user.isEmpty || pass.isEmpty) return null;

    final server = uri.hasPort
        ? '${uri.scheme}://${uri.host}:${uri.port}'
        : '${uri.scheme}://${uri.host}';
    return _XtreamRef(server, user, pass, streamId);
  }
}

class _CachedNowNext {
  final EpgNowNext value;
  final DateTime fetchedAt;
  _CachedNowNext(this.value) : fetchedAt = DateTime.now();

  bool get isStale {
    final now = DateTime.now();
    final current = value.now;
    // A known-running programme is truth until it ends.
    if (current != null) return !now.isBefore(current.stop);
    // Nothing airing (or no data): retry after a while.
    final upcoming = value.next;
    if (upcoming != null && upcoming.start.isBefore(now)) return true;
    return now.difference(fetchedAt) >= IptvEpgService._emptyNowNextTtl;
  }
}

/// Timeshift URL dialects panels serve, in probe order.
enum _CatchupForm { pathTs, pathM3u8, php }

class _CachedSchedule {
  final List<EpgProgramme> value;
  final DateTime fetchedAt;
  _CachedSchedule(this.value) : fetchedAt = DateTime.now();

  bool get isStale =>
      DateTime.now().difference(fetchedAt) >= IptvEpgService._scheduleTtl;
}
