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

  const EpgProgramme({
    required this.title,
    required this.description,
    required this.start,
    required this.stop,
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

  static const _headers = {'User-Agent': 'Debrify/1.0'};
  static const _timeout = Duration(seconds: 10);

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
  /// playlist's tvg-ids. Returns true when any channel got programmes — the
  /// caller re-renders its rows then, since capability changed.
  Future<bool> setM3uEpgContext({
    required String playlistKey,
    required String? epgUrl,
    required List<IptvChannel> channels,
  }) async {
    clearM3uEpgContext();
    final url = epgUrl?.trim();
    if (url == null || url.isEmpty) return false;

    final urlToId = <String, String>{};
    final ids = <String>{};
    for (final channel in channels) {
      if (!channel.isLive) continue;
      final id = channel.tvgId?.trim();
      if (id == null || id.isEmpty) continue;
      urlToId[channel.url] = id;
      ids.add(id);
      // iptv-org-style playlists suffix a feed onto the id (BBCOne.uk@SD)
      // while guides typically publish the bare id (BBCOne.uk). Admit both
      // forms into the parser's filter; lookup tries exact first.
      final bare = stripFeedSuffix(id);
      if (bare != id) ids.add(bare);
    }
    if (ids.isEmpty) return false;

    // Claim the context before the (potentially long) load so any newer
    // claim — a playlist switch OR a reload of this same playlist — wins
    // and this result gets dropped.
    final generation = ++_m3uContextGeneration;
    final raw = await XmltvEpgSource.load(epgUrl: url, tvgIds: ids);
    if (generation != _m3uContextGeneration) return false;
    if (raw == null || raw.isEmpty) return false;

    _m3uUrlToTvgId = urlToId;
    _xmltvIndex = {
      for (final entry in raw.entries)
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
    return true;
  }

  /// Drop the active XMLTV context (playlist switched away).
  void clearM3uEpgContext() {
    final hadIndex = _xmltvIndex != null;
    _m3uContextGeneration++;
    _m3uUrlToTvgId = const {};
    _xmltvIndex = null;
    if (hadIndex) contextVersion.value++;
  }

  /// The active XMLTV programme list for a channel URL, or null when the
  /// channel isn't covered by the loaded guide. Exact tvg-id match wins;
  /// the feed-suffix-stripped form is only a fallback, so a guide that
  /// really does publish per-feed ids can never be shadowed by the bare one.
  List<EpgProgramme>? _xmltvProgrammesFor(String channelUrl) {
    final index = _xmltvIndex;
    if (index == null) return null;
    final tvgId = _m3uUrlToTvgId[channelUrl];
    if (tvgId == null) return null;
    var programmes = index[tvgId];
    if (programmes == null || programmes.isEmpty) {
      final bare = stripFeedSuffix(tvgId);
      if (bare != tvgId) programmes = index[bare];
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

  /// Cached now/next if fresh — synchronous, for paint-before-fetch UIs.
  /// XMLTV answers are computed live from the local index, so they are
  /// always "fresh" and roll programme boundaries by themselves.
  EpgNowNext? peekNowNext(String channelUrl) {
    final xmltv = _xmltvProgrammesFor(channelUrl);
    if (xmltv != null) return _pickNowNext(xmltv, DateTime.now());
    final cached = _nowNextCache[channelUrl];
    if (cached == null || cached.isStale) return null;
    return cached.value;
  }

  /// Fetch (or serve cached) now/next for a channel. Returns an empty
  /// [EpgNowNext] when the panel has no data or the request fails.
  Future<EpgNowNext> nowNext(String channelUrl) {
    final xmltv = _xmltvProgrammesFor(channelUrl);
    if (xmltv != null) {
      return Future.value(_pickNowNext(xmltv, DateTime.now()));
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
  Future<List<EpgProgramme>> schedule(String channelUrl) {
    final xmltv = _xmltvProgrammesFor(channelUrl);
    if (xmltv != null) return Future.value(xmltv);

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
    if (listings.isEmpty) return const [];

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
      final response =
          await http.get(Uri.parse(url), headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) return const [];

      final decoded = jsonDecode(response.body);
      final listings = decoded is Map<String, dynamic>
          ? decoded['epg_listings']
          : decoded; // some panels answer with a bare array
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
    return EpgProgramme(
      title: title,
      description: _decodeXtreamText(item['description']),
      start: start,
      stop: stop,
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
  static String _decodeXtreamText(dynamic value) {
    if (value is! String || value.isEmpty) return '';
    final raw = value.trim();
    try {
      final normalized = base64.normalize(raw.replaceAll(RegExp(r'\s'), ''));
      return utf8.decode(base64Decode(normalized), allowMalformed: true).trim();
    } catch (_) {
      return raw;
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

class _CachedSchedule {
  final List<EpgProgramme> value;
  final DateTime fetchedAt;
  _CachedSchedule(this.value) : fetchedAt = DateTime.now();

  bool get isStale =>
      DateTime.now().difference(fetchedAt) >= IptvEpgService._scheduleTtl;
}
