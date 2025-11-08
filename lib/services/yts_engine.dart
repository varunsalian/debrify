import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/torrent.dart';
import 'search_engine.dart';

class YtsEngine extends SearchEngine {
  const YtsEngine()
      : super(
          name: 'yts',
          displayName: 'YTS',
          baseUrl: 'https://r.jina.ai/http://yts.mx/api/v2/list_movies.json',
        );

  @override
  String getSearchUrl(String query) {
    return '$baseUrl?query_term=${Uri.encodeComponent(query)}&limit=50';
  }

  @override
  Future<List<Torrent>> search(String query) async {
    try {
      final String trimmed = query.trim();
      final bool isImdbQuery = RegExp(r'^tt\d{7,}$', caseSensitive: false)
          .hasMatch(trimmed);
      final String url = isImdbQuery
          ? 'https://r.jina.ai/http://yts.mx/api/v2/movie_details.json?imdb_id=${Uri.encodeComponent(trimmed)}'
          : '$baseUrl?query_term=${Uri.encodeComponent(trimmed)}&limit=50';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Failed to load torrents from YTS. HTTP ${response.statusCode}');
      }

      String body = response.body.trim();
      final int jsonStart = body.indexOf('{');
      final int jsonEnd = body.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) {
        final int previewLength = body.length > 120 ? 120 : body.length;
        throw Exception('Unexpected YTS response: ${body.substring(0, previewLength)}');
      }
      if (jsonStart > 0 || jsonEnd < body.length - 1) {
        body = body.substring(jsonStart, jsonEnd + 1);
      }
      final Map<String, dynamic> payload = json.decode(body);
      if (payload['status'] != 'ok') {
        final message = payload['status_message']?.toString() ?? 'Unknown error';
        throw Exception('Failed to load torrents from YTS. $message');
      }

      final data = payload['data'] as Map<String, dynamic>?;
      final List<dynamic>? movies = isImdbQuery
          ? (data?['movie'] == null ? null : [data!['movie']])
          : data?['movies'] as List<dynamic>?;
      if (movies == null || movies.isEmpty) {
        return const [];
      }

      final int nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final List<Torrent> torrents = [];
      for (final movieRaw in movies) {
        final Map<String, dynamic>? movie = movieRaw as Map<String, dynamic>?;
        if (movie == null) continue;
        final List<dynamic>? movieTorrents = movie['torrents'] as List<dynamic>?;
        if (movieTorrents == null || movieTorrents.isEmpty) continue;

        final int movieId = movie['id'] is int
            ? movie['id'] as int
            : int.tryParse(movie['id']?.toString() ?? '') ?? 0;
        final String movieTitle = (movie['title_long']?.toString().trim().isNotEmpty ?? false)
            ? movie['title_long'].toString()
            : (movie['title']?.toString() ?? 'YTS Movie');
        final String? genreLabel = (movie['genres'] is List && (movie['genres'] as List).isNotEmpty)
            ? (movie['genres'] as List).join(', ')
            : null;

        for (int i = 0; i < movieTorrents.length; i++) {
          final Map<String, dynamic>? t = movieTorrents[i] as Map<String, dynamic>?;
          if (t == null) continue;
          final String hash = (t['hash']?.toString() ?? '').trim().toLowerCase();
          if (hash.isEmpty) continue;

          final int sizeBytes = t['size_bytes'] is int
              ? t['size_bytes'] as int
              : int.tryParse(t['size_bytes']?.toString() ?? '') ?? 0;
          final int uploadedUnix = t['date_uploaded_unix'] is int
              ? t['date_uploaded_unix'] as int
              : int.tryParse(t['date_uploaded_unix']?.toString() ?? '') ?? nowUnix;
          final int seeds = t['seeds'] is int
              ? t['seeds'] as int
              : int.tryParse(t['seeds']?.toString() ?? '') ?? 0;
          final int peers = t['peers'] is int
              ? t['peers'] as int
              : int.tryParse(t['peers']?.toString() ?? '') ?? 0;
          final String quality = t['quality']?.toString() ?? '';
          final String type = t['type']?.toString() ?? '';

          final String titleSuffix = [quality, type.toUpperCase()]
              .where((part) => part.trim().isNotEmpty)
              .join(' ');
          final String torrentName = titleSuffix.isNotEmpty
              ? '$movieTitle [$titleSuffix]'
              : movieTitle;

          torrents.add(
            Torrent(
              rowid: movieId * 10 + i,
              infohash: hash,
              name: torrentName,
              sizeBytes: sizeBytes,
              createdUnix: uploadedUnix,
              seeders: seeds,
              leechers: peers,
              completed: 0,
              scrapedDate: nowUnix,
              category: genreLabel,
            ),
          );
        }
      }

      return torrents;
    } catch (error, stack) {
      // Surface the root cause in logs while returning a user-friendly message
      // ignore: avoid_print
      print('YTS search failed: $error\n$stack');
      throw Exception('Failed to load torrents from YTS. ${error.toString().replaceFirst('Exception: ', '')}');
    }
  }
}
