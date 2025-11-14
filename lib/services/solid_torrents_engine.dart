import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/torrent.dart';
import 'search_engine.dart';
import 'storage_service.dart';

class SolidTorrentsSearchResult {
  final List<Torrent> torrents;
  final int pagesPulled;

  const SolidTorrentsSearchResult({
    required this.torrents,
    required this.pagesPulled,
  });
}

class SolidTorrentsEngine extends SearchEngine {
  const SolidTorrentsEngine()
      : super(
          name: 'solid_torrents',
          displayName: 'SolidTorrents',
          baseUrl: 'https://r.jina.ai/https://solidtorrents.to/api/v1/search',
        );

  @override
  String getSearchUrl(String query) {
    return '$baseUrl?q=${Uri.encodeComponent(query)}&limit=100&sort=seeders';
  }

  String getSearchUrlWithPagination(String query, int page) {
    return '$baseUrl?q=${Uri.encodeComponent(query)}&limit=100&page=$page&sort=seeders';
  }

  @override
  Future<List<Torrent>> search(String query) async {
    final maxResults = await StorageService.getMaxSolidTorrentsResults();
    final result = await searchWithConfig(
      query,
      maxResults: maxResults,
      betweenPageRequests: Duration.zero,
    );
    return result.torrents;
  }

  Future<SolidTorrentsSearchResult> searchWithConfig(
    String query, {
    required int maxResults,
    Duration betweenPageRequests = Duration.zero,
  }) async {
    final List<Torrent> allTorrents = [];
    int pageCount = 0;
    int currentPage = 1;
    bool hasMorePages = true;

    final int clampedMax = maxResults.clamp(1, 500);
    final int maxPages = (clampedMax / 100).ceil().clamp(1, 5);

    try {
      while (pageCount < maxPages && hasMorePages) {
        final url = getSearchUrlWithPagination(query, currentPage);
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 15));

        if (response.statusCode != 200) {
          throw Exception('Failed to load torrents from SolidTorrents. HTTP ${response.statusCode}');
        }

        // Extract JSON from Jina.ai response (similar to YTS)
        String body = response.body.trim();
        final int jsonStart = body.indexOf('{');
        final int jsonEnd = body.lastIndexOf('}');
        if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) {
          final int previewLength = body.length > 120 ? 120 : body.length;
          throw Exception('Unexpected SolidTorrents response: ${body.substring(0, previewLength)}');
        }
        if (jsonStart > 0 || jsonEnd < body.length - 1) {
          body = body.substring(jsonStart, jsonEnd + 1);
        }

        final Map<String, dynamic> data = json.decode(body);

        if (data['success'] != true) {
          throw Exception('SolidTorrents API returned error');
        }

        final List<dynamic>? results = data['results'] as List<dynamic>?;
        if (results == null || results.isEmpty) {
          break;
        }

        final int nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        for (final result in results) {
          final Map<String, dynamic>? item = result as Map<String, dynamic>?;
          if (item == null) continue;

          final String? infohash = item['infohash']?.toString().trim().toUpperCase();
          if (infohash == null || infohash.isEmpty) continue;

          final String title = item['title']?.toString() ?? 'Unknown';
          final int sizeBytes = item['size'] is int
              ? item['size'] as int
              : int.tryParse(item['size']?.toString() ?? '') ?? 0;
          final int seeders = item['seeders'] is int
              ? item['seeders'] as int
              : int.tryParse(item['seeders']?.toString() ?? '') ?? 0;
          final int leechers = item['leechers'] is int
              ? item['leechers'] as int
              : int.tryParse(item['leechers']?.toString() ?? '') ?? 0;

          // Combine category and subcategory if available
          String? category;
          final cat = item['category'];
          final subCat = item['subCategory'];
          if (cat != null || subCat != null) {
            category = [cat, subCat]
                .where((c) => c != null)
                .map((c) => c.toString())
                .join(' > ');
          }

          // Generate a unique rowid from the infohash
          final int rowid = infohash.hashCode.abs();

          allTorrents.add(
            Torrent(
              rowid: rowid,
              infohash: infohash,
              name: title,
              sizeBytes: sizeBytes,
              createdUnix: nowUnix,
              seeders: seeders,
              leechers: leechers,
              completed: 0,
              scrapedDate: nowUnix,
              category: category,
              source: 'solid_torrents',
            ),
          );
        }

        // Check pagination info
        final pagination = data['pagination'] as Map<String, dynamic>?;
        if (pagination != null) {
          hasMorePages = pagination['hasNext'] == true;
        } else {
          hasMorePages = false;
        }

        pageCount++;
        currentPage++;

        if (!hasMorePages) {
          break;
        }

        if (betweenPageRequests > Duration.zero) {
          await Future.delayed(betweenPageRequests);
        }
      }

      return SolidTorrentsSearchResult(
        torrents: allTorrents,
        pagesPulled: pageCount,
      );
    } on TimeoutException {
      throw Exception('SolidTorrents search timed out. Please try again.');
    } catch (error, stack) {
      // ignore: avoid_print
      print('SolidTorrents search failed: $error\n$stack');
      if (allTorrents.isNotEmpty) {
        return SolidTorrentsSearchResult(
          torrents: allTorrents,
          pagesPulled: pageCount,
        );
      }
      throw Exception('Failed to load torrents from SolidTorrents. ${error.toString().replaceFirst('Exception: ', '')}');
    }
  }
}
