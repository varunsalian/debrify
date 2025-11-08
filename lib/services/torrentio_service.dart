import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/advanced_search_selection.dart';
import '../models/torrent.dart';

class TorrentioService {
  static const String _baseUrl = 'https://torrentio.strem.fun';

  static Future<List<Torrent>> fetchStreams(
    AdvancedSearchSelection selection,
  ) async {
    if (selection.isSeries &&
        (selection.season == null || selection.episode == null)) {
      throw Exception('Season and episode required for series search.');
    }
    final endpoint = selection.isSeries
        ? '/stream/series/${selection.imdbId}:${selection.season}:${selection.episode}.json'
        : '/stream/movie/${selection.imdbId}.json';
    final uri = Uri.parse('$_baseUrl$endpoint');
    debugPrint('TorrentioService: Fetching ${selection.imdbId} -> $uri');
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      debugPrint('TorrentioService: HTTP ${response.statusCode} body=${response.body}');
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

    final nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final List<Torrent> torrents = [];
    int counter = 0;

    for (final stream in streams) {
      if (stream is! Map<String, dynamic>) continue;
      final infoHash = (stream['infoHash'] ?? '').toString().trim();
      if (infoHash.isEmpty) {
        continue;
      }

      final behaviorHints = stream['behaviorHints'];
      final filename = behaviorHints is Map<String, dynamic>
          ? (behaviorHints['filename']?.toString() ?? '')
          : '';

      final title = (stream['title'] ?? '').toString();
      final displayName = filename.isNotEmpty
          ? filename
          : title.isNotEmpty
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
