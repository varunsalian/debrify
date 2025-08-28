import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/torrent.dart';
import 'search_engine.dart';

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
    final List<Torrent> allTorrents = [];
    String? nextId;
    int pageCount = 0;
    const int maxPages = 4; // Initial call + 3 additional pages
    const int delayMs = 100; // 100ms delay between calls

    try {
      while (pageCount < maxPages) {
        // Make API call
        final url = getSearchUrlWithPagination(query, nextId);
        final response = await http.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final torrentsList = data['torrents'] as List;
          final torrents = torrentsList.map((json) => Torrent.fromJson(json)).toList();
          
          // Add torrents from this page
          allTorrents.addAll(torrents);
          
          // Check if there are more pages - handle both string and number types
          final nextValue = data['next'];
          if (nextValue != null) {
            nextId = nextValue.toString();
          } else {
            nextId = null;
          }
          
          pageCount++;
          
          // If no more pages or reached max, break
          if (nextId == null) {
            break;
          }
          
          // Add delay before next call (except for the last iteration)
          if (pageCount < maxPages) {
            await Future.delayed(Duration(milliseconds: delayMs));
          }
        } else {
          // If API call fails, break and return what we have
          break;
        }
      }
      
      return allTorrents;
    } catch (e) {
      // If any error occurs, return whatever results we have
      if (allTorrents.isNotEmpty) {
        return allTorrents;
      }
      throw Exception('Network error while searching Torrents CSV. Please check your connection.');
    }
  }
} 