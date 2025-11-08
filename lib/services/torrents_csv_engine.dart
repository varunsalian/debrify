import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/torrent.dart';
import 'search_engine.dart';
import 'storage_service.dart';

class TorrentsCsvSearchResult {
  final List<Torrent> torrents;
  final int pagesPulled;

  const TorrentsCsvSearchResult({
    required this.torrents,
    required this.pagesPulled,
  });
}

class TorrentsCsvEngine extends SearchEngine {
  const TorrentsCsvEngine() : super(
    name: 'torrents_csv',
    displayName: 'Torrents CSV',
    baseUrl: 'https://torrents-csv.com/service/search',
  );

  @override
  String getSearchUrl(String query) {
    return '$baseUrl?q=${Uri.encodeComponent(query)}';
  }

  String getSearchUrlWithPagination(String query, String? afterId) {
    final baseUrl = getSearchUrl(query);
    if (afterId != null) {
      return '$baseUrl&after=$afterId';
    }
    return baseUrl;
  }

  @override
  Future<List<Torrent>> search(String query) async {
    final maxResults = await StorageService.getMaxTorrentsCsvResults();
    final result = await searchWithConfig(
      query,
      maxResults: maxResults,
      betweenPageRequests: Duration.zero,
    );
    return result.torrents;
  }

  Future<TorrentsCsvSearchResult> searchWithConfig(
    String query, {
    required int maxResults,
    Duration betweenPageRequests = Duration.zero,
  }) async {
    final List<Torrent> allTorrents = [];
    String? nextId;
    int pageCount = 0;

    final int clampedMax = maxResults.clamp(1, 500);
    final requestsNeeded = (clampedMax / 25).ceil().clamp(1, 20);

    try {
      while (pageCount < requestsNeeded) {
        final url = getSearchUrlWithPagination(query, nextId);
        final response = await http.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final torrentsList = data['torrents'] as List;
          final torrents =
              torrentsList
                  .map(
                    (json) => Torrent.fromJson(
                      (json as Map<String, dynamic>),
                      source: 'torrents_csv',
                    ),
                  )
                  .toList();

          allTorrents.addAll(torrents);

          final nextValue = data['next'];
          if (nextValue != null) {
            nextId = nextValue.toString();
          } else {
            nextId = null;
          }

          pageCount++;

          if (nextId == null) {
            break;
          }

          if (betweenPageRequests > Duration.zero) {
            await Future.delayed(betweenPageRequests);
          }
        } else {
          break;
        }
      }

      return TorrentsCsvSearchResult(
        torrents: allTorrents,
        pagesPulled: pageCount,
      );
    } catch (e) {
      if (allTorrents.isNotEmpty) {
        return TorrentsCsvSearchResult(
          torrents: allTorrents,
          pagesPulled: pageCount,
        );
      }
      throw Exception(
        'Network error while searching Torrents CSV. Please check your connection.',
      );
    }
  }
}
