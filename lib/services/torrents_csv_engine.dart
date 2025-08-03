import 'dart:convert';
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

  @override
  Future<List<Torrent>> search(String query) async {
    try {
      final response = await http.get(Uri.parse(getSearchUrl(query)));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final torrentsList = data['torrents'] as List;
        return torrentsList.map((json) => Torrent.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load torrents from Torrents CSV. Please try again.');
      }
    } catch (e) {
      throw Exception('Network error while searching Torrents CSV. Please check your connection.');
    }
  }
} 