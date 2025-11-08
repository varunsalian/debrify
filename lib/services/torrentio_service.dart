import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/advanced_search_selection.dart';
import '../models/torrent.dart';

class TorrentioService {
  static const String _baseUrl = 'https://torrentio.strem.fun';
  static const int _maxSeasonProbes = 5;

  static Future<List<Torrent>> fetchStreams(
    AdvancedSearchSelection selection,
  ) async {
    final nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final List<Torrent> torrents = [];
    int counter = 0;

    Future<List<dynamic>> _loadStreams(String endpoint) async {
      final uri = Uri.parse('$_baseUrl$endpoint');
      debugPrint('TorrentioService: Fetching ${selection.imdbId} -> $uri');
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        debugPrint(
            'TorrentioService: HTTP ${response.statusCode} body=${response.body}');
        throw Exception('Torrentio responded with HTTP ${response.statusCode}');
      }

      final dynamic payload = json.decode(response.body);
      if (payload is! Map<String, dynamic>) {
        throw Exception('Unexpected Torrentio response');
      }

      final streams = payload['streams'];
      if (streams is! List) {
        return const [];
      }
      return streams;
    }

    void _appendStreams(List<dynamic> streams) {
      for (final stream in streams) {
        if (stream is! Map<String, dynamic>) continue;
        final infoHash = (stream['infoHash'] ?? '').toString().trim();
        if (infoHash.isEmpty) {
          continue;
        }

        final title = (stream['title'] ?? '').toString();
        final displayName = title.isNotEmpty
            ? title.replaceAll('\n', ' ')
            : selection.title;

        final seeders = _parseWatchersCount(title);
        final sizeBytes = _parseSizeBytes(title);

        torrents.add(
          Torrent(
            rowid: -(++counter),
            infohash: infoHash.toLowerCase(),
            name: displayName,
            sizeBytes: sizeBytes,
            createdUnix: nowUnix,
            seeders: seeders,
            leechers: 0,
            completed: 0,
            scrapedDate: nowUnix,
            category: selection.isSeries ? 'series' : 'movie',
            source: 'torrentio',
          ),
        );
      }
    }

    if (!selection.isSeries) {
      final movieEndpoint = '/stream/movie/${selection.imdbId}.json';
      final streams = await _loadStreams(movieEndpoint);
      _appendStreams(streams);
      debugPrint('TorrentioService: Parsed ${torrents.length} stream(s)');
      return torrents;
    }

    final bool hasSeason = selection.season != null;
    final int targetEpisode = hasSeason ? (selection.episode ?? 1) : 1;

    if (hasSeason) {
      final seriesEndpoint =
          '/stream/series/${selection.imdbId}:${selection.season}:$targetEpisode.json';
      final streams = await _loadStreams(seriesEndpoint);
      _appendStreams(streams);
      debugPrint('TorrentioService: Parsed ${torrents.length} stream(s)');
      return torrents;
    }

    for (var seasonProbe = 1; seasonProbe <= _maxSeasonProbes; seasonProbe++) {
      final endpoint =
          '/stream/series/${selection.imdbId}:$seasonProbe:$targetEpisode.json';
      final streams = await _loadStreams(endpoint);
      if (streams.isEmpty) {
        debugPrint(
            'TorrentioService: Probe season $seasonProbe returned 0 streams, stopping.');
        break;
      }
      debugPrint(
          'TorrentioService: Probe season $seasonProbe returned ${streams.length} stream(s)');
      _appendStreams(streams);
    }

    debugPrint('TorrentioService: Parsed ${torrents.length} stream(s)');
    return torrents;
  }

  static int _parseWatchersCount(String title) {
    final match = RegExp(r'👤\s*(\d+)').firstMatch(title);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '') ?? 0;
    }
    return 0;
  }

  static int _parseSizeBytes(String title) {
    final regex = RegExp(r'💾\s*([\d\.]+)\s*(KB|MB|GB|TB)', caseSensitive: false);
    final match = regex.firstMatch(title);
    if (match == null) {
      return 0;
    }
    final amount = double.tryParse(match.group(1) ?? '') ?? 0;
    final unit = (match.group(2) ?? '').toUpperCase();
    final multiplier = switch (unit) {
      'KB' => pow(1024, 1) as num,
      'MB' => pow(1024, 2) as num,
      'GB' => pow(1024, 3) as num,
      'TB' => pow(1024, 4) as num,
      _ => 1,
    };
    return (amount * multiplier).round();
  }
}
