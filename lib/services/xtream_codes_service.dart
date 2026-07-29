import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/iptv_playlist.dart';
import 'iptv_catalog_cache.dart';
import 'iptv_catalog_db.dart';
import 'storage_service.dart';

/// Result of Xtream Codes authentication
class XcAuthResult {
  final bool success;
  final String? error;
  final String? status;
  final DateTime? expDate;
  final int? maxConnections;
  final int? activeConnections;

  const XcAuthResult({
    required this.success,
    this.error,
    this.status,
    this.expDate,
    this.maxConnections,
    this.activeConnections,
  });
}

/// Service for fetching IPTV content via Xtream Codes API
class XtreamCodesService {
  static final XtreamCodesService instance = XtreamCodesService._();
  XtreamCodesService._();

  /// Known-player UA for player_api calls — panels behind WAFs challenge
  /// generic User-Agents but allowlist recognizable IPTV players (same
  /// string IPTVnator ships for the same reason). Stream probes/playback
  /// use the playback UA instead (see _probeStatusCode).
  static const _headers = {'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18'};

  // Cache for parsed results (key -> result)
  final Map<String, _CachedResult> _cache = {};
  static const _cacheDuration = Duration(minutes: 30);

  // Parsed panel lists are large (tens of thousands of channels); keep only a
  // few resident — the TTL alone never frees memory for distinct keys.
  static const _maxCachedResults = 3;

  // Per-server probe result: which live URL form this panel actually serves
  // (standard /live/ vs legacy un-prefixed, raw .ts vs HLS .m3u8 — panels
  // with HLS output disabled only route the .ts forms, and vice versa).
  //
  // Raw MPEG-TS is preferred over HLS on purpose (TiviMate's default for the
  // same reason): the .ts output is the original broadcast stream, while a
  // panel's .m3u8 output can be a multi-variant ladder — adaptive players
  // then start low and often SIT low on TV boxes with pessimistic bandwidth
  // estimates, which users report as "my 4K channels play at 720p".
  final Map<String, _LiveUrlForm> _liveUrlFormCache = {};

  String _baseUrl(String serverUrl, String username, String password) {
    final user = Uri.encodeQueryComponent(username);
    final pass = Uri.encodeQueryComponent(password);
    return '$serverUrl/player_api.php?username=$user&password=$pass';
  }

  /// GET that reports failure as null instead of throwing, for requests whose
  /// results are optional.
  Future<http.Response?> _tryGet(String url, Duration timeout) async {
    try {
      return await http.get(Uri.parse(url), headers: _headers).timeout(timeout);
    } catch (e) {
      debugPrint('XtreamCodesService: Optional request failed ($url): $e');
      return null;
    }
  }

  /// GET with retry on transient network failures. Stream lists — VOD
  /// especially — can run to tens of MB, and some panels/CDNs drop the
  /// connection mid-transfer or stall under load; a plain http.get throws away
  /// the whole download on the first hiccup ("Connection closed while
  /// receiving data"). Retrying with exponential backoff recovers the common
  /// transient case. A non-2xx status is the server's real answer, so it
  /// returns immediately without burning a retry.
  Future<http.Response> _getWithRetry(
    String url, {
    required Duration timeout,
    int attempts = 3,
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await http
            .get(Uri.parse(url), headers: _headers)
            .timeout(timeout);
      } catch (e) {
        final transient = e is TimeoutException ||
            e is SocketException ||
            e is http.ClientException;
        if (!transient || attempt >= attempts) rethrow;
        final backoff = Duration(milliseconds: 500 * (1 << (attempt - 1)));
        debugPrint(
          'XtreamCodesService: transient fetch failure '
          '(attempt $attempt/$attempts) for $url: $e — '
          'retrying in ${backoff.inMilliseconds}ms',
        );
        await Future<void>.delayed(backoff);
      }
    }
  }

  // Stream lists from large providers can be tens of MB; decode AND build
  // those off the UI isolate so the app doesn't freeze.
  @visibleForTesting
  static const computeDecodeThreshold = 100 * 1024;

  /// Number of fetches that took the isolate path. Test seam: which side of
  /// [computeDecodeThreshold] a payload landed on is otherwise invisible, and
  /// "the isolate is exercised" is exactly what a big-payload test must prove.
  @visibleForTesting
  static int isolateBuilds = 0;

  /// Builds that ran on THIS isolate. Statics aren't shared across isolates,
  /// so after a hop the caller's copy stays put while the worker's own copy
  /// is incremented and discarded — which makes "the work really happened
  /// somewhere else" observable without timing anything.
  @visibleForTesting
  static int buildsOnThisIsolate = 0;

  /// How many panels have a remembered live-URL dialect. Test seam: "a
  /// non-answer must not be cached" is otherwise unobservable, and it is a
  /// bug that has already been introduced once.
  @visibleForTesting
  int get cachedLiveUrlFormCount => _liveUrlFormCache.length;

  /// First `"stream_id": 123` or `"stream_id": "123"` in a raw panel
  /// response — enough to seed the live-URL-form probe without decoding the
  /// payload first. Both alternatives are fully anchored so a non-numeric id
  /// (`"12ab"`) doesn't match a truncated prefix and send the probe after a
  /// stream that doesn't exist.
  static final RegExp _sampleStreamIdExp =
      RegExp(r'"stream_id"\s*:\s*(?:"(\d+)"|(\d+))');

  /// How much of a raw streams payload the id probe scans.
  ///
  /// Bounded so a body with no id at all can't drag tens of MB through a
  /// regex on this thread — but generously, because the failure mode on the
  /// other side is far worse than a millisecond: no id means no probe, no
  /// probe means the default dialect, and a legacy panel handed the default
  /// serves every one of its channels under a URL that 404s. 8KB (one screen
  /// of records) was too tight — a single fat first record, which panels do
  /// emit, pushed the id out of range.
  @visibleForTesting
  static const streamIdProbeWindow = 1024 * 1024;

  /// The charset a response declared, or null when it declared none.
  /// Extracted here (a header, not a payload — costs nothing) so the isolate
  /// can reproduce `Response.body`'s decoding without carrying the headers.
  @visibleForTesting
  static String? charsetOf(http.Response response) {
    final contentType = response.headers['content-type'];
    if (contentType == null) return null;
    return _charsetExp.firstMatch(contentType)?.group(1);
  }

  static final RegExp _charsetExp =
      RegExp(r'charset\s*=\s*"?([^\s";]+)"?', caseSensitive: false);

  /// Resolve a declared charset the way package:http does: unknown or absent
  /// falls back to latin1.
  static Encoding encodingForCharset(String? charset) {
    if (charset == null) return latin1;
    return Encoding.getByName(charset) ?? latin1;
  }

  /// Decode a panel response as a JSON list, synchronously. Used inside the
  /// channel-building isolate, where the decode is already off the UI thread
  /// and [compute] would be a pointless second hop.
  @visibleForTesting
  static (List<dynamic>?, String?) decodeJsonListSync(
    String body,
    String label,
  ) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      final preview = body.length > 200 ? body.substring(0, 200) : body;
      return (null, 'Server returned invalid response for $label: $preview');
    }
    return _asJsonList(decoded, label);
  }

  /// Shape check shared by every decode entry point, so callers can never
  /// disagree about what counts as a usable answer.
  static (List<dynamic>?, String?) _asJsonList(dynamic decoded, String label) {
    if (decoded is List<dynamic>) {
      return (decoded, null);
    }

    // Some XC servers return a map with an error message instead of an array
    if (decoded is Map<String, dynamic>) {
      final errorMsg = decoded['error'] ?? decoded['message'];
      if (errorMsg != null) {
        return (null, 'Server error: $errorMsg');
      }
      return (null, 'Server returned unexpected format for $label');
    }

    return (null, 'Server returned unexpected format for $label');
  }

  /// Authenticate and return account info
  Future<XcAuthResult> authenticate(
    String serverUrl,
    String username,
    String password,
  ) async {
    try {
      final url = _baseUrl(serverUrl, username, password);
      debugPrint('XtreamCodesService: Authenticating with $serverUrl');

      final response = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return XcAuthResult(
          success: false,
          error: 'Server returned HTTP ${response.statusCode}',
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final userInfo = data['user_info'] as Map<String, dynamic>?;

      if (userInfo == null) {
        return const XcAuthResult(
          success: false,
          error: 'Invalid response from server',
        );
      }

      final status = userInfo['status']?.toString();
      if (status?.toLowerCase() != 'active') {
        return XcAuthResult(
          success: false,
          error: 'Account status: ${status ?? 'Unknown'}',
          status: status,
        );
      }

      DateTime? expDate;
      final expStr = userInfo['exp_date']?.toString();
      if (expStr != null && expStr.isNotEmpty) {
        final expTimestamp = int.tryParse(expStr);
        if (expTimestamp != null) {
          expDate = DateTime.fromMillisecondsSinceEpoch(expTimestamp * 1000);
        }
      }

      return XcAuthResult(
        success: true,
        status: status,
        expDate: expDate,
        maxConnections: int.tryParse(
          userInfo['max_connections']?.toString() ?? '',
        ),
        activeConnections: int.tryParse(
          userInfo['active_cons']?.toString() ?? '',
        ),
      );
    } catch (e) {
      debugPrint('XtreamCodesService: Auth error: $e');
      return XcAuthResult(success: false, error: 'Connection failed: $e');
    }
  }

  /// Fetch live channels, converted to IptvChannel list + categories
  Future<IptvParseResult> fetchLiveStreams(
    String serverUrl,
    String username,
    String password,
  ) {
    return _fetchStreams(serverUrl, username, password, contentType: 'live');
  }

  /// Fetch VOD items, converted to IptvChannel list + categories
  Future<IptvParseResult> fetchVodStreams(
    String serverUrl,
    String username,
    String password,
  ) {
    return _fetchStreams(serverUrl, username, password, contentType: 'vod');
  }

  /// Fetch series (the browse list, one entry per show), converted to
  /// IptvChannel list + categories. A series has no playable URL of its own —
  /// each channel carries an `xtream-series://<id>` sentinel and its episodes
  /// are fetched on drill-in via [fetchSeriesInfo].
  Future<IptvParseResult> fetchSeriesStreams(
    String serverUrl,
    String username,
    String password,
  ) {
    return _fetchStreams(serverUrl, username, password, contentType: 'series');
  }

  /// Shared fetch pipeline for live and VOD content.
  Future<IptvParseResult> _fetchStreams(
    String serverUrl,
    String username,
    String password, {
    required String contentType,
  }) async {
    final isLive = contentType == 'live';
    final isSeries = contentType == 'series';
    final label = isLive ? 'live' : (isSeries ? 'series' : 'VOD');
    final cacheKey = '$serverUrl:$username:$contentType';

    // DB-catalog mode: the worker ingests straight into iptv_catalog.db and
    // the service's in-memory result cache is bypassed entirely — holding
    // three 55k-object catalogs on the heap is exactly what this mode
    // removes. Freshness policy moves to the caller (snapshot.ingestedAt).
    final ingestToDb =
        IptvCatalogDb.isOpen && await StorageService.getIptvDbCatalogEnabled();

    // Check cache
    if (!ingestToDb && _cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      if (DateTime.now().difference(cached.fetchedAt) < _cacheDuration) {
        debugPrint(
          'XtreamCodesService: Using cached $label streams for $serverUrl',
        );
        return cached.result;
      }
    }

    try {
      final base = _baseUrl(serverUrl, username, password);
      final categoriesAction = isLive
          ? 'get_live_categories'
          : isSeries
              ? 'get_series_categories'
              : 'get_vod_categories';
      final streamsAction = isLive
          ? 'get_live_streams'
          : isSeries
              ? 'get_series'
              : 'get_vod_streams';

      // Kick off both requests in parallel, but only the stream list is
      // required: a category failure (network or malformed body) must not
      // take down the whole fetch.
      final categoriesFuture = _tryGet(
        '$base&action=$categoriesAction',
        const Duration(seconds: 30),
      );
      final streamsResponse = await _getWithRetry(
        '$base&action=$streamsAction',
        timeout: const Duration(seconds: 90),
      );
      final categoriesResponse = await categoriesFuture;

      if (streamsResponse.statusCode != 200) {
        return IptvParseResult(
          channels: [],
          categories: [],
          error:
              'Failed to fetch $label streams: HTTP ${streamsResponse.statusCode}',
        );
      }

      // `Response.body` is never read here: it is a getter that UTF-8 decodes
      // bodyBytes on the calling thread, and for a tens-of-MB panel that
      // decode is itself hundreds of milliseconds of the freeze this function
      // exists to remove. Only the raw bytes are touched; the decode rides
      // along to the worker inside the job.
      final streamsBytes = streamsResponse.bodyBytes;
      // One local for "the categories response we can actually use", so the
      // bytes and the charset can never be derived from disagreeing
      // conditions.
      final usableCategories =
          (categoriesResponse == null || categoriesResponse.statusCode != 200)
              ? null
              : categoriesResponse;
      final categoriesBytes = usableCategories?.bodyBytes;

      final encodedUser = Uri.encodeComponent(username);
      final encodedPass = Uri.encodeComponent(password);

      // Standard live URLs use the /live/ prefix, preferring raw MPEG-TS
      // (see _liveUrlFormCache for why TS beats HLS); some panels only route
      // the legacy un-prefixed form or only one output format — probe once
      // per server and remember.
      //
      // The probe needs one stream id, and the decode that would yield it is
      // exactly the work being moved off this thread — so read a sample
      // straight out of the raw body instead, over a bounded window (see
      // [streamIdProbeWindow]).
      var liveUrlForm = _LiveUrlForm.standardTs;
      if (isLive) {
        // latin1 regardless of the declared charset: every byte the pattern
        // can match (`"stream_id"`, digits, punctuation) is ASCII, latin1 maps
        // all 256 byte values so it can never throw on a truncated multi-byte
        // sequence, and 8KB is far too small to matter either way.
        final head = latin1.decode(
          streamsBytes.length > streamIdProbeWindow
              ? Uint8List.sublistView(streamsBytes, 0, streamIdProbeWindow)
              : streamsBytes,
        );
        final match = _sampleStreamIdExp.firstMatch(head);
        final sampleId = match?.group(1) ?? match?.group(2);
        if (sampleId != null && sampleId.isNotEmpty) {
          liveUrlForm = await _detectLiveUrlForm(
            serverUrl,
            encodedUser,
            encodedPass,
            sampleId,
          );
        }
      }

      // Decode AND build in one isolate hop (see [_buildXtreamStreams]).
      // Small panels skip the isolate: spawning one costs more than the work.
      final job = _StreamsJob(
        // fromList copies once (a memcpy — cheap next to a UTF-8 decode) and
        // the transfer to the worker is then zero-copy. The source lists are
        // not neutered, so the small-payload path below can materialize the
        // very same job on this isolate.
        streamsBytes: TransferableTypedData.fromList([streamsBytes]),
        categoriesBytes: categoriesBytes == null
            ? null
            : TransferableTypedData.fromList([categoriesBytes]),
        streamsCharset: charsetOf(streamsResponse),
        categoriesCharset:
            usableCategories == null ? null : charsetOf(usableCategories),
        serverUrl: serverUrl,
        encodedUser: encodedUser,
        encodedPass: encodedPass,
        contentType: contentType,
        label: label,
        liveUrlForm: liveUrlForm,
        ingestDbPath: ingestToDb ? IptvCatalogDb.path : null,
        ingestCatalogKey: ingestToDb
            ? IptvCatalogCache.keyForXtream(serverUrl, username, contentType)
            : null,
      );
      // Both bodies are decoded by the job, so both count toward the
      // threshold — a small channel list with a huge category list is still
      // real work to keep off this thread.
      final useIsolate =
          streamsBytes.length + (categoriesBytes?.length ?? 0) >
              computeDecodeThreshold;
      if (useIsolate) isolateBuilds++;
      final built = useIsolate
          ? await compute(_buildXtreamStreams, job)
          : _buildXtreamStreams(job);

      if (built.hasError) return built;
      final channels = built.channels;
      final categoryNames = built.categories;
      final warning = built.warning;

      debugPrint(
        'XtreamCodesService: Fetched '
        '${built.ingest?.channelCount ?? channels.length} $label channels, '
        '${categoryNames.length} categories'
        '${built.ingest != null ? ' (ingested to catalog DB)' : ''}',
      );

      // An ingested result IS the cache — rows are on disk, the receipt is
      // all the caller needs, and nothing big should linger on this heap.
      if (built.ingest != null) return built;

      // Cache without the warning so it surfaces once per fresh fetch rather
      // than on every cached load for the next 30 minutes.
      _cache[cacheKey] = _CachedResult(
        result: IptvParseResult(channels: channels, categories: categoryNames),
        fetchedAt: DateTime.now(),
      );
      _evictCache();
      return IptvParseResult(
        channels: channels,
        categories: categoryNames,
        warning: warning,
      );
    } catch (e) {
      debugPrint('XtreamCodesService: Error fetching $label streams: $e');
      return IptvParseResult(
        channels: [],
        categories: [],
        error: 'Failed to fetch $label streams: $e',
      );
    }
  }

  /// Build a live stream URL in the given panel-specific form.
  ///
  /// Delegates to the top-level [_liveUrlFor] so the isolate that builds
  /// channels can use the exact same construction — a second copy of this
  /// would be a URL-format bug waiting to happen.
  String _liveUrl(
    String serverUrl,
    String encodedUser,
    String encodedPass,
    String streamId,
    _LiveUrlForm form,
  ) =>
      _liveUrlFor(serverUrl, encodedUser, encodedPass, streamId, form);

  /// Probe which live URL form this panel serves, in order of preference:
  /// standard /live/ raw TS, standard /live/ HLS (TS-off panels), then the
  /// two legacy un-prefixed forms. First 2xx wins.
  Future<_LiveUrlForm> _detectLiveUrlForm(
    String serverUrl,
    String encodedUser,
    String encodedPass,
    String sampleStreamId,
  ) async {
    final cacheKey = '$serverUrl:$encodedUser';
    final cached = _liveUrlFormCache[cacheKey];
    if (cached != null) return cached;

    for (final form in _LiveUrlForm.values) {
      final status = await _probeStatusCode(
        _liveUrl(serverUrl, encodedUser, encodedPass, sampleStreamId, form),
      );
      if (status == null) {
        // Network failure — the panel is likely unreachable, so probing the
        // remaining forms would just stack timeouts. Keep the standard form
        // and don't cache an undetermined verdict; the next fetch re-probes.
        return _LiveUrlForm.standardTs;
      }
      if (status >= 200 && status < 300) {
        _liveUrlFormCache[cacheKey] = form;
        if (form != _LiveUrlForm.standardTs) {
          debugPrint(
            'XtreamCodesService: Panel $serverUrl uses ${form.name} live URLs',
          );
        }
        return form;
      }
    }

    // Every form got a definitive non-2xx answer — which teaches us nothing
    // about the panel's dialect, and can equally mean the sampled stream id
    // was bad (a truncated or malformed payload can still yield a plausible
    // id). Caching "standard" here would freeze that non-answer in for the
    // session and hand a later, healthy fetch the wrong URL form, so take the
    // re-probe cost instead.
    return _LiveUrlForm.standardTs;
  }

  /// Fetch only the status code of a URL without downloading the body: some
  /// panels answer stream URLs with the live stream itself, which a plain
  /// http.get would buffer without bound.
  ///
  /// Probes with the PLAYBACK User-Agent, not the API one: the probe's whole
  /// job is predicting what the players will get, and a panel that blocks
  /// unknown UAs on stream URLs would otherwise 4xx every form and leave the
  /// verdict wrong for a URL shape that plays fine.
  Future<int?> _probeStatusCode(String url) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] = kIptvDefaultUserAgent;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 10));
      // Cancel the body stream immediately; only the status matters.
      await response.stream.listen((_) {}).cancel();
      return response.statusCode;
    } catch (e) {
      debugPrint('XtreamCodesService: Probe failed for $url: $e');
      return null;
    } finally {
      client.close();
    }
  }

  // Per-series episode lists (get_series_info). Small entries, but keep a cap
  // anyway — a browse session can drill into dozens of shows.
  final Map<String, _CachedSeriesInfo> _seriesInfoCache = {};
  static const _maxCachedSeriesInfo = 12;

  /// Fetch one series' seasons + episodes (`get_series_info`). Returns null on
  /// any failure — the caller shows its retry state. Cached for the standard
  /// TTL so the detail page's parallel consumers (episode list, resume state,
  /// Play) share one panel round-trip.
  Future<XtreamSeriesInfo?> fetchSeriesInfo(
    String serverUrl,
    String username,
    String password,
    String seriesId,
  ) async {
    final cacheKey = '$serverUrl:$username:$seriesId';
    final cached = _seriesInfoCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheDuration) {
      return cached.info;
    }

    try {
      final base = _baseUrl(serverUrl, username, password);
      final response = await _getWithRetry(
        '$base&action=get_series_info&series_id='
        '${Uri.encodeQueryComponent(seriesId)}',
        timeout: const Duration(seconds: 30),
      );
      if (response.statusCode != 200) return null;

      final body = response.body;
      dynamic decoded;
      try {
        decoded = body.length > computeDecodeThreshold
            ? await compute(jsonDecode, body)
            : jsonDecode(body);
      } catch (_) {
        return null;
      }
      if (decoded is! Map) return null;

      final info = decoded['info'] is Map
          ? Map<String, dynamic>.from(decoded['info'] as Map)
          : const <String, dynamic>{};

      // `episodes` is normally a map of season-number → episode list, but some
      // panels serve a bare list of lists. Normalize to one iterable of
      // (seasonHint, episodeJson) pairs.
      final episodesRaw = decoded['episodes'];
      final entries = <(int?, Map<String, dynamic>)>[];
      if (episodesRaw is Map) {
        episodesRaw.forEach((key, value) {
          final seasonHint = int.tryParse(key.toString());
          if (value is List) {
            for (final e in value) {
              if (e is Map) {
                entries.add((seasonHint, Map<String, dynamic>.from(e)));
              }
            }
          }
        });
      } else if (episodesRaw is List) {
        for (final seasonList in episodesRaw) {
          if (seasonList is List) {
            for (final e in seasonList) {
              if (e is Map) entries.add((null, Map<String, dynamic>.from(e)));
            }
          }
        }
      }

      final encodedUser = Uri.encodeComponent(username);
      final encodedPass = Uri.encodeComponent(password);
      final episodes = <XtreamSeriesEpisode>[];
      for (final (seasonHint, e) in entries) {
        final id = e['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final seasonRaw = e['season'];
        // Episode's own season field wins; the map key is the fallback; a
        // panel that supplies neither still keeps its episodes (bucketed
        // into season 1) rather than losing them.
        final season = (seasonRaw is num
                ? seasonRaw.toInt()
                : int.tryParse(seasonRaw?.toString() ?? '') ?? seasonHint) ??
            1;
        final numRaw = e['episode_num'];
        final number = numRaw is num
            ? numRaw.toInt()
            : int.tryParse(numRaw?.toString() ?? '');
        if (season < 0 || number == null) continue;
        final ext = e['container_extension']?.toString() ?? 'mp4';
        final epInfo = e['info'] is Map
            ? Map<String, dynamic>.from(e['info'] as Map)
            : const <String, dynamic>{};
        final ratingRaw = epInfo['rating'] ?? e['rating'];
        final rating = ratingRaw is num
            ? ratingRaw.toDouble()
            : double.tryParse(ratingRaw?.toString() ?? '');
        episodes.add(
          XtreamSeriesEpisode(
            season: season,
            episode: number,
            title: e['title']?.toString() ?? '',
            plot: epInfo['plot']?.toString(),
            // Real panels use lowercase `releasedate` at episode level (vs
            // camelCase at series level) — try every known spelling.
            airDate: (epInfo['releasedate'] ??
                    epInfo['release_date'] ??
                    epInfo['releaseDate'] ??
                    epInfo['air_date'])
                ?.toString(),
            durationSecs: _durationSecs(
              epInfo['duration_secs'],
              epInfo['duration'],
            ),
            thumbnailUrl: epInfo['movie_image']?.toString(),
            rating: rating != null && rating > 0 ? rating : null,
            url: '$serverUrl/series/$encodedUser/$encodedPass/$id.$ext',
          ),
        );
      }
      episodes.sort((a, b) {
        if (a.season != b.season) return a.season.compareTo(b.season);
        return a.episode.compareTo(b.episode);
      });

      final backdrops = info['backdrop_path'];
      final result = XtreamSeriesInfo(
        plot: info['plot']?.toString(),
        cast: info['cast']?.toString(),
        genre: info['genre']?.toString(),
        releaseDate: (info['releaseDate'] ??
                info['release_date'] ??
                info['releasedate'])
            ?.toString(),
        rating: double.tryParse(info['rating']?.toString() ?? ''),
        poster: info['cover']?.toString(),
        backdrop: backdrops is List && backdrops.isNotEmpty
            ? backdrops.first?.toString()
            : null,
        episodes: episodes,
      );

      // Never cache an episode-less answer: it's indistinguishable from a
      // transient panel hiccup, and pinning it for the TTL would leave the
      // page's Retry re-serving the same emptiness for 30 minutes.
      if (episodes.isEmpty) return result;

      _seriesInfoCache[cacheKey] =
          _CachedSeriesInfo(info: result, fetchedAt: DateTime.now());
      while (_seriesInfoCache.length > _maxCachedSeriesInfo) {
        String? oldestKey;
        DateTime? oldestAt;
        _seriesInfoCache.forEach((key, cached) {
          if (oldestAt == null || cached.fetchedAt.isBefore(oldestAt!)) {
            oldestAt = cached.fetchedAt;
            oldestKey = key;
          }
        });
        _seriesInfoCache.remove(oldestKey);
      }
      return result;
    } catch (e) {
      debugPrint('XtreamCodesService: Error fetching series info: $e');
      return null;
    }
  }

  /// Episode duration in seconds: `duration_secs` (number or numeric string)
  /// when present AND positive, else the `duration` "HH:MM:SS"/"MM:SS" string
  /// some panels send instead. A zero `duration_secs` means "unset" on panels
  /// that only fill the display string, so it falls through rather than
  /// short-circuiting the fallback. Null when neither parses.
  static int? _durationSecs(dynamic secsRaw, dynamic hmsRaw) {
    final secs = secsRaw is num
        ? secsRaw.toInt()
        : int.tryParse(secsRaw?.toString() ?? '');
    if (secs != null && secs > 0) return secs;

    final hms = hmsRaw?.toString().trim() ?? '';
    if (hms.isEmpty) return null;
    final parts = hms.split(':');
    if (parts.isEmpty || parts.length > 3) return null;
    var total = 0;
    for (final part in parts) {
      final v = int.tryParse(part.trim());
      if (v == null) return null;
      total = total * 60 + v;
    }
    return total > 0 ? total : null;
  }

  /// Peek the in-memory cache: the fresh (within-TTL) result for this
  /// account + content type, or null. Lets callers skip both the network AND
  /// a disk-snapshot read for same-session revisits.
  IptvParseResult? cachedResult(
    String serverUrl,
    String username,
    String contentType,
  ) {
    final cached = _cache['$serverUrl:$username:$contentType'];
    if (cached == null) return null;
    if (DateTime.now().difference(cached.fetchedAt) >= _cacheDuration) {
      return null;
    }
    return cached.result;
  }

  /// Clear cache for a specific server or all
  void clearCache([String? serverUrl]) {
    if (serverUrl != null) {
      _cache.removeWhere((key, _) => key.startsWith(serverUrl));
      _liveUrlFormCache.removeWhere((key, _) => key.startsWith(serverUrl));
      _seriesInfoCache.removeWhere((key, _) => key.startsWith(serverUrl));
    } else {
      _cache.clear();
      _liveUrlFormCache.clear();
      _seriesInfoCache.clear();
    }
  }

  /// Drop expired entries, then the oldest beyond the cap.
  void _evictCache() {
    final now = DateTime.now();
    _cache.removeWhere((_, c) => now.difference(c.fetchedAt) >= _cacheDuration);
    while (_cache.length > _maxCachedResults) {
      String? oldestKey;
      DateTime? oldestAt;
      _cache.forEach((key, cached) {
        if (oldestAt == null || cached.fetchedAt.isBefore(oldestAt!)) {
          oldestAt = cached.fetchedAt;
          oldestKey = key;
        }
      });
      _cache.remove(oldestKey);
    }
  }
}

class _CachedResult {
  final IptvParseResult result;
  final DateTime fetchedAt;

  _CachedResult({required this.result, required this.fetchedAt});
}

class _CachedSeriesInfo {
  final XtreamSeriesInfo info;
  final DateTime fetchedAt;

  _CachedSeriesInfo({required this.info, required this.fetchedAt});
}

/// One playable episode from `get_series_info` — carries its ready-built
/// `/series/user/pass/id.ext` URL, so downstream consumers never touch panel
/// credentials.
class XtreamSeriesEpisode {
  final int season;
  final int episode;
  final String title;
  final String? plot;
  final String? airDate;
  final int? durationSecs;
  final String? thumbnailUrl;
  final double? rating;
  final String url;

  const XtreamSeriesEpisode({
    required this.season,
    required this.episode,
    required this.title,
    this.plot,
    this.airDate,
    this.durationSecs,
    this.thumbnailUrl,
    this.rating,
    required this.url,
  });
}

/// A series' detail metadata + flat episode list (sorted season, then episode)
/// from `get_series_info`.
class XtreamSeriesInfo {
  final String? plot;
  final String? cast;
  final String? genre;
  final String? releaseDate;
  final double? rating;
  final String? poster;
  final String? backdrop;
  final List<XtreamSeriesEpisode> episodes;

  const XtreamSeriesInfo({
    this.plot,
    this.cast,
    this.genre,
    this.releaseDate,
    this.rating,
    this.poster,
    this.backdrop,
    required this.episodes,
  });
}

/// Live stream URL forms panels serve, in probe order — raw TS first (the
/// full-quality original stream; a panel's HLS output can be a capped or
/// multi-variant ladder), then HLS for TS-off panels, then the legacy
/// un-prefixed forms some old panels only route.
enum _LiveUrlForm { standardTs, standardHls, legacyTs, legacyHls }

/// Build a live stream URL in the given panel-specific form. Top-level so
/// both the service and the channel-building isolate share one definition.
String _liveUrlFor(
  String serverUrl,
  String encodedUser,
  String encodedPass,
  String streamId,
  _LiveUrlForm form,
) {
  final creds = '$encodedUser/$encodedPass/$streamId';
  return switch (form) {
    _LiveUrlForm.standardTs => '$serverUrl/live/$creds.ts',
    _LiveUrlForm.standardHls => '$serverUrl/live/$creds.m3u8',
    _LiveUrlForm.legacyTs => '$serverUrl/$creds.ts',
    _LiveUrlForm.legacyHls => '$serverUrl/$creds.m3u8',
  };
}

/// Everything [_buildXtreamStreams] needs to turn raw panel responses into
/// channels. Deliberately all plain values: this crosses an isolate boundary.
///
/// The bodies travel as RAW BYTES, not strings. `Response.body` UTF-8 decodes
/// tens of MB on whichever thread reads it, and that decode has to happen
/// before a string could be handed over — so passing strings left the single
/// largest remaining block on the UI thread even though the parse itself had
/// already moved off it. [TransferableTypedData] hands the buffer over
/// (one memcpy on send, zero copy on receive) and the decode happens on the
/// worker, where it belongs.
class _StreamsJob {
  final TransferableTypedData streamsBytes;

  /// Null when the categories request itself failed — the build then reports
  /// the "ungrouped" warning without needing to know why.
  final TransferableTypedData? categoriesBytes;
  final String serverUrl;
  final String encodedUser;
  final String encodedPass;
  final String contentType;
  final String label;
  final _LiveUrlForm liveUrlForm;

  /// The charset each body declared, so the worker decodes byte-for-byte
  /// identically to what `Response.body` would have produced on this thread.
  /// Null means "not declared", which package:http resolves to latin1 — the
  /// fallback is replicated rather than corrected, because silently switching
  /// a panel's channel names to a different encoding is a separate change
  /// from moving the decode off the UI thread.
  final String? streamsCharset;
  final String? categoriesCharset;

  /// When set, the worker writes the finished channel list into the catalog
  /// DB at this path under [ingestCatalogKey] and returns a receipt instead
  /// of the list — the 55k-object graph then never crosses back to the UI
  /// isolate at all.
  final String? ingestDbPath;
  final String? ingestCatalogKey;

  const _StreamsJob({
    required this.streamsBytes,
    required this.categoriesBytes,
    required this.serverUrl,
    required this.encodedUser,
    required this.encodedPass,
    required this.contentType,
    required this.label,
    required this.liveUrlForm,
    required this.streamsCharset,
    required this.categoriesCharset,
    this.ingestDbPath,
    this.ingestCatalogKey,
  });
}

/// Decode both panel responses AND build every [IptvChannel] in one pass.
///
/// This is the whole point of the isolate: decoding alone off the UI thread
/// still handed back tens of thousands of decoded maps (a copy the receiving
/// thread pays for) and then built the channels on the UI thread anyway. A
/// 55k-channel panel spent seconds of that on the main isolate — long enough
/// for Android to declare the app unresponsive and offer to kill it. Doing
/// both here means only the finished (and more compact) channel list crosses
/// back, once.
IptvParseResult _buildXtreamStreams(_StreamsJob job) {
  XtreamCodesService.buildsOnThisIsolate++;
  final isLive = job.contentType == 'live';
  final isSeries = job.contentType == 'series';

  // The expensive UTF-8 pass now happens HERE, on the worker.
  final streamsBody = XtreamCodesService.encodingForCharset(job.streamsCharset)
      .decode(job.streamsBytes.materialize().asUint8List());

  final (streamsData, streamsError) =
      XtreamCodesService.decodeJsonListSync(streamsBody, 'streams');
  if (streamsError != null) {
    return IptvParseResult(channels: [], categories: [], error: streamsError);
  }

  // Category id → name; channels degrade to ungrouped (with a user-visible
  // warning) when the panel couldn't serve them.
  String? warning;
  final categoryMap = <String, String>{};
  final categoryNames = <String>[];
  final categoriesBytes = job.categoriesBytes;
  if (categoriesBytes == null) {
    warning =
        'Could not load ${job.label} categories — showing channels ungrouped';
  } else {
    final categoriesBody =
        XtreamCodesService.encodingForCharset(job.categoriesCharset)
            .decode(categoriesBytes.materialize().asUint8List());
    final (categoriesData, catError) =
        XtreamCodesService.decodeJsonListSync(categoriesBody, 'categories');
    if (categoriesData == null) {
      warning =
          'Could not load ${job.label} categories — showing channels ungrouped';
      debugPrint(
        'XtreamCodesService: Ignoring ${job.label} categories: $catError',
      );
    } else {
      for (final cat in categoriesData) {
        final id = cat['category_id']?.toString() ?? '';
        final name = cat['category_name']?.toString() ?? '';
        if (id.isNotEmpty && name.isNotEmpty) {
          categoryMap[id] = name;
          categoryNames.add(name);
        }
      }
    }
  }

  final channels = <IptvChannel>[];
  for (final stream in streamsData!) {
    final name = stream['name']?.toString() ?? '';
    if (name.isEmpty) continue;

    final categoryId = stream['category_id']?.toString() ?? '';
    final group = categoryMap[categoryId];

    // Series entries are shows, not streams: keyed by series_id, no playable
    // URL (episodes come from get_series_info on drill-in). The sentinel URL
    // keeps every URL-keyed pathway (focus maps, search, dedupe) working;
    // play/tap handlers branch on contentType before it could ever reach a
    // player.
    if (isSeries) {
      final seriesId = stream['series_id']?.toString() ?? '';
      if (seriesId.isEmpty) continue;
      final backdrops = stream['backdrop_path'];
      final backdrop = backdrops is List && backdrops.isNotEmpty
          ? backdrops.first?.toString()
          : null;
      // Panels disagree on the release-date key — resolve the known
      // spellings in order (same alias set other mature clients use).
      final releaseDate = (stream['releaseDate'] ??
              stream['release_date'] ??
              stream['releasedate'])
          ?.toString();
      channels.add(
        IptvChannel(
          name: name,
          url: 'xtream-series://$seriesId',
          // `cover` is the canonical series art; some panels send
          // `stream_icon` instead (the live/VOD field).
          logoUrl: (stream['cover'] ?? stream['stream_icon'])?.toString(),
          group: group,
          duration: null, // not live
          contentType: 'series',
          attributes: {
            'series_id': seriesId,
            if ((stream['plot']?.toString() ?? '').isNotEmpty)
              'plot': stream['plot'].toString(),
            if ((stream['genre']?.toString() ?? '').isNotEmpty)
              'genre': stream['genre'].toString(),
            if (releaseDate != null && releaseDate.isNotEmpty)
              'releaseDate': releaseDate,
            if ((stream['rating']?.toString() ?? '').isNotEmpty)
              'rating': stream['rating'].toString(),
            if (backdrop != null && backdrop.isNotEmpty) 'backdrop': backdrop,
          },
        ),
      );
      continue;
    }

    final streamId = stream['stream_id']?.toString() ?? '';
    if (streamId.isEmpty) continue;

    if (isLive) {
      channels.add(
        IptvChannel(
          name: name,
          url: _liveUrlFor(
            job.serverUrl,
            job.encodedUser,
            job.encodedPass,
            streamId,
            job.liveUrlForm,
          ),
          logoUrl: stream['stream_icon']?.toString(),
          group: group,
          duration: -1, // live
          contentType: 'live',
          attributes: {
            if (stream['epg_channel_id'] != null)
              'tvg-id': stream['epg_channel_id'].toString(),
            'stream_id': streamId,
            // Catchup: whether the panel records this channel, and for how
            // many days back the archive reaches.
            if (stream['tv_archive'] != null)
              'tv_archive': stream['tv_archive'].toString(),
            if (stream['tv_archive_duration'] != null)
              'tv_archive_duration': stream['tv_archive_duration'].toString(),
          },
        ),
      );
    } else {
      final extension = stream['container_extension']?.toString() ?? 'mp4';
      channels.add(
        IptvChannel(
          name: name,
          url: '${job.serverUrl}/movie/${job.encodedUser}/${job.encodedPass}/'
              '$streamId.$extension',
          logoUrl: stream['stream_icon']?.toString(),
          group: group,
          duration: null, // not live
          contentType: 'vod',
          attributes: {
            if (stream['rating'] != null) 'rating': stream['rating'].toString(),
            'stream_id': streamId,
          },
        ),
      );
    }
  }

  // DB-catalog mode: write the rows here on the worker and hand back only a
  // receipt. An EMPTY list is deliberately NOT ingested — a flaky panel
  // returning nothing must not wipe a previously good stored catalog (the
  // same rule the snapshot cache's "never cache an empty catalog" enforces);
  // the empty result flows back as-is and reads as empty, exactly like today.
  final ingestDbPath = job.ingestDbPath;
  final ingestCatalogKey = job.ingestCatalogKey;
  if (ingestDbPath != null && ingestCatalogKey != null && channels.isNotEmpty) {
    final digest = IptvCatalogDb.ingest(
      dbPath: ingestDbPath,
      catalogKey: ingestCatalogKey,
      channels: channels,
      categories: categoryNames,
    );
    return IptvParseResult(
      channels: const [],
      categories: categoryNames,
      warning: warning,
      ingest: CatalogIngestReceipt(
        catalogKey: ingestCatalogKey,
        channelCount: channels.length,
        contentDigest: digest,
      ),
    );
  }

  return IptvParseResult(
    channels: channels,
    categories: categoryNames,
    warning: warning,
  );
}
