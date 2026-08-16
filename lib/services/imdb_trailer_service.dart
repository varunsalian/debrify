import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'youtube_service.dart';

/// Backup trailer source: IMDb hosts its own trailer video (their player never
/// touches YouTube) and hands back direct signed CloudFront MP4s through the
/// same graphql.imdb.com endpoint [ImdbEnrichmentService] already rides.
///
/// This exists because YouTube trailer resolution can be regionally blocked
/// (see the client ladder in [YoutubeService]) and every other trailer
/// "source" surveyed — TMDB, Trakt, Stremio/Cinemeta, kinocheck — is just a
/// YouTube key in a different envelope. IMDb is the only second host.
///
/// Results are shaped as [YoutubeResolvedStreams] so every consumer (hero
/// backdrop, detail autoplay, trailer button, discover rail) plays them
/// through the exact pipeline it already has. The streams are MUXED — audio
/// included, [YoutubeResolvedStreams.audioUrl] stays null — which is the
/// simplest thing the players eat (no merge, plain progressive MP4, H.264).
class ImdbTrailerService {
  static const String _endpoint = 'https://graphql.imdb.com/';
  static const Duration _httpTimeout = Duration(seconds: 12);

  static const String _query = r'''
    query Trailer($id: ID!) {
      title(id: $id) {
        primaryVideos(first: 1) {
          edges {
            node {
              name { value }
              runtime { value }
              playbackURLs { url displayName { value } videoMimeType }
            }
          }
        }
      }
    }
  ''';

  /// The playback URLs are CloudFront-signed with a ~24h expiry; cache well
  /// under that so a held entry is never handed out stale, but long enough
  /// that hero focus-dwell and a follow-up detail open share one fetch.
  static const Duration _cacheTtl = Duration(hours: 3);
  static final Map<String, _CacheEntry> _cache = {};
  static final Map<String, Future<YoutubeResolvedStreams?>> _inFlight = {};

  /// Resolve the primary IMDb trailer for [imdbId] (a `tt...` id) into a
  /// direct MP4, highest quality at or below [maxHeight] (uncapped when null
  /// — IMDb tops out at 1080p). Returns null when the title has no video or
  /// the API/shape fails; never throws.
  static Future<YoutubeResolvedStreams?> resolveTrailer(
    String imdbId, {
    int? maxHeight,
  }) {
    final key = maxHeight == null ? imdbId : '$imdbId#h$maxHeight';
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.at) < _cacheTtl) {
      return Future.value(cached.streams);
    }
    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;
    final future = _resolveUncached(imdbId, maxHeight).then((streams) {
      // Failures are NOT cached: the next surface to want this trailer should
      // retry (a transient IMDb hiccup must not blank a title for 3 hours).
      if (streams != null) {
        _cache.removeWhere(
            (_, e) => DateTime.now().difference(e.at) >= _cacheTtl);
        _cache[key] = _CacheEntry(streams, DateTime.now());
      }
      return streams;
    });
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  static Future<YoutubeResolvedStreams?> _resolveUncached(
    String imdbId,
    int? maxHeight,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': 'Mozilla/5.0',
              // Same edge requirement as ImdbEnrichmentService: without a
              // request that looks like it came from imdb.com, 403.
              'Referer': 'https://www.imdb.com/',
            },
            body: json.encode({
              'query': _query,
              'variables': {'id': imdbId},
            }),
          )
          .timeout(_httpTimeout);
      if (response.statusCode != 200) {
        debugPrint('ImdbTrailer: HTTP ${response.statusCode} for $imdbId');
        return null;
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      final edges = (((data['data'] as Map?)?['title'] as Map?)?['primaryVideos']
          as Map?)?['edges'] as List?;
      if (edges == null || edges.isEmpty) return null;
      final node = (edges.first as Map?)?['node'] as Map?;
      if (node == null) return null;

      // Collect the MP4 rungs (skip the HLS "AUTO" entry — progressive MP4 is
      // seekable and plays identically across media_kit, Exo and tvOS).
      final candidates = <({int height, String url})>[];
      final urls = node['playbackURLs'] as List?;
      for (final raw in urls ?? const []) {
        final entry = raw as Map?;
        if (entry == null) continue;
        if ((entry['videoMimeType'] as String?) != 'MP4') continue;
        final url = entry['url'] as String?;
        if (url == null || url.isEmpty) continue;
        final label =
            ((entry['displayName'] as Map?)?['value'] as String?) ?? '';
        // Labels are "1080p"/"720p"/"480p"/"SD"; SD ranks below every
        // numbered rung.
        final height =
            int.tryParse(RegExp(r'^(\d+)').firstMatch(label)?.group(1) ?? '') ??
                360;
        candidates.add((height: height, url: url));
      }
      if (candidates.isEmpty) return null;
      candidates.sort((a, b) => b.height.compareTo(a.height));
      final atOrBelow = maxHeight == null
          ? candidates
          : candidates.where((c) => c.height <= maxHeight).toList();
      final chosen = atOrBelow.isNotEmpty ? atOrBelow.first : candidates.last;

      return YoutubeResolvedStreams(
        playUrl: chosen.url,
        // Muxed — audio is in the file; consumers must not merge anything.
        audioUrl: null,
        downloadUrl: chosen.url,
        downloadHeight: chosen.height,
        downloadHasAudio: true,
        title: ((node['name'] as Map?)?['value'] as String?),
        durationSeconds: ((node['runtime'] as Map?)?['value'] as num?)?.toInt(),
      );
    } catch (e) {
      debugPrint('ImdbTrailer: resolve failed for $imdbId — $e');
      return null;
    }
  }
}

class _CacheEntry {
  final YoutubeResolvedStreams streams;
  final DateTime at;
  const _CacheEntry(this.streams, this.at);
}
