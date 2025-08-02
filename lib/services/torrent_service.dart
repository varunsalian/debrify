import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/torrent.dart';

class TorrentService {
  static const String _baseUrl = 'https://torrents-csv.com/service/search';

  static Future<List<Torrent>> searchTorrents(String query) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl?q=${Uri.encodeComponent(query)}'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final torrentsList = data['torrents'] as List;
        return torrentsList.map((json) => Torrent.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load torrents. Please try again.');
      }
    } catch (e) {
      throw Exception('Network error. Please check your connection.');
    }
  }
} 