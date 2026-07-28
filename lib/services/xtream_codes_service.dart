import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/iptv_playlist.dart';

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

  // Stream lists from large providers can be tens of MB; decode those off the
  // UI isolate so the app doesn't freeze.
  static const _computeDecodeThreshold = 100 * 1024;

  /// Safely decode a JSON response body as a List, returning a user-friendly error
  /// if the server returns non-JSON or non-array data.
  Future<(List<dynamic>?, String?)> _decodeJsonList(
    String body,
    String label,
  ) async {
    dynamic decoded;
    try {
      decoded = body.length > _computeDecodeThreshold
          ? await compute(jsonDecode, body)
          : jsonDecode(body);
    } catch (_) {
      // Server returned non-JSON (e.g. plain-text error message)
      final preview = body.length > 200 ? body.substring(0, 200) : body;
      return (null, 'Server returned invalid response for $label: $preview');
    }

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

    // Check cache
    if (_cache.containsKey(cacheKey)) {
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
      final streamsResponse = await http
          .get(Uri.parse('$base&action=$streamsAction'), headers: _headers)
          .timeout(const Duration(seconds: 60));
      final categoriesResponse = await categoriesFuture;

      if (streamsResponse.statusCode != 200) {
        return IptvParseResult(
          channels: [],
          categories: [],
          error:
              'Failed to fetch $label streams: HTTP ${streamsResponse.statusCode}',
        );
      }

      final (streamsData, streamsError) = await _decodeJsonList(
        streamsResponse.body,
        'streams',
      );
      if (streamsError != null) {
        return IptvParseResult(
          channels: [],
          categories: [],
          error: streamsError,
        );
      }

      // Build category ID -> name map; degrade to ungrouped channels (with a
      // user-visible warning) when categories are unavailable.
      String? warning;
      final categoryMap = <String, String>{};
      final categoryNames = <String>[];
      if (categoriesResponse == null || categoriesResponse.statusCode != 200) {
        warning =
            'Could not load $label categories — showing channels ungrouped';
      } else {
        final (categoriesData, catError) = await _decodeJsonList(
          categoriesResponse.body,
          'categories',
        );
        if (categoriesData == null) {
          warning =
              'Could not load $label categories — showing channels ungrouped';
          debugPrint(
            'XtreamCodesService: Ignoring $label categories: $catError',
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

      final encodedUser = Uri.encodeComponent(username);
      final encodedPass = Uri.encodeComponent(password);

      // Standard live URLs use the /live/ prefix, preferring raw MPEG-TS
      // (see _liveUrlFormCache for why TS beats HLS); some panels only route
      // the legacy un-prefixed form or only one output format — probe once
      // per server and remember.
      var liveUrlForm = _LiveUrlForm.standardTs;
      if (isLive && streamsData!.isNotEmpty) {
        final sampleId = streamsData
            .map((s) => s['stream_id']?.toString() ?? '')
            .firstWhere((id) => id.isNotEmpty, orElse: () => '');
        if (sampleId.isNotEmpty) {
          liveUrlForm = await _detectLiveUrlForm(
            serverUrl,
            encodedUser,
            encodedPass,
            sampleId,
          );
        }
      }

      // Convert streams to IptvChannel
      final channels = <IptvChannel>[];
      for (final stream in streamsData!) {
        final name = stream['name']?.toString() ?? '';
        if (name.isEmpty) continue;

        final categoryId = stream['category_id']?.toString() ?? '';
        final group = categoryMap[categoryId];

        // Series entries are shows, not streams: keyed by series_id, no
        // playable URL (episodes come from get_series_info on drill-in).
        // The sentinel URL keeps every URL-keyed pathway (focus maps, search,
        // dedupe) working; play/tap handlers branch on contentType before it
        // could ever reach a player.
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
              logoUrl:
                  (stream['cover'] ?? stream['stream_icon'])?.toString(),
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
                if (backdrop != null && backdrop.isNotEmpty)
                  'backdrop': backdrop,
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
              url: _liveUrl(
                serverUrl,
                encodedUser,
                encodedPass,
                streamId,
                liveUrlForm,
              ),
              logoUrl: stream['stream_icon']?.toString(),
              group: group,
              duration: -1, // live
              contentType: 'live',
              attributes: {
                if (stream['epg_channel_id'] != null)
                  'tvg-id': stream['epg_channel_id'].toString(),
                'stream_id': streamId,
                // Catchup: whether the panel records this channel, and for
                // how many days back the archive reaches.
                if (stream['tv_archive'] != null)
                  'tv_archive': stream['tv_archive'].toString(),
                if (stream['tv_archive_duration'] != null)
                  'tv_archive_duration':
                      stream['tv_archive_duration'].toString(),
              },
            ),
          );
        } else {
          final extension = stream['container_extension']?.toString() ?? 'mp4';
          channels.add(
            IptvChannel(
              name: name,
              url:
                  '$serverUrl/movie/$encodedUser/$encodedPass/$streamId.$extension',
              logoUrl: stream['stream_icon']?.toString(),
              group: group,
              duration: null, // not live
              contentType: 'vod',
              attributes: {
                if (stream['rating'] != null)
                  'rating': stream['rating'].toString(),
                'stream_id': streamId,
              },
            ),
          );
        }
      }

      debugPrint(
        'XtreamCodesService: Fetched ${channels.length} $label channels, ${categoryNames.length} categories',
      );

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
  String _liveUrl(
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

    // Every form got a definitive non-2xx answer — nothing works. Cache the
    // standard form so we don't re-probe all four on every fetch.
    _liveUrlFormCache[cacheKey] = _LiveUrlForm.standardTs;
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
      final response = await http
          .get(
            Uri.parse(
              '$base&action=get_series_info&series_id='
              '${Uri.encodeQueryComponent(seriesId)}',
            ),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;

      final body = response.body;
      dynamic decoded;
      try {
        decoded = body.length > _computeDecodeThreshold
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
