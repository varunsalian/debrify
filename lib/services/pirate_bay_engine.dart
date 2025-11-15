import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/torrent.dart';
import 'search_engine.dart';

class PirateBayEngine extends SearchEngine {
  const PirateBayEngine() : super(
    name: 'pirate_bay',
    displayName: 'The Pirate Bay',
    baseUrl: 'https://apibay.org/q.php',
  );

  @override
  String getSearchUrl(String query) {
    return '$baseUrl?q=${Uri.encodeComponent(query)}';
  }

  @override
  Future<List<Torrent>> search(String query) async {
    try {
      final response = await http
          .get(Uri.parse(getSearchUrl(query)))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        
        // Handle empty results
        if (data.isEmpty || (data.length == 1 && data[0]['name'] == 'No results returned')) {
          return [];
        }

        return data.map((json) => _convertPirateBayToTorrent(json)).toList();
      } else {
        throw Exception('Failed to load torrents from The Pirate Bay. Please try again.');
      }
    } on TimeoutException {
      throw Exception('Pirate Bay search timed out. Please try again.');
    } catch (e) {
      throw Exception('Network error while searching The Pirate Bay. Please check your connection.');
    }
  }

  Torrent _convertPirateBayToTorrent(Map<String, dynamic> json) {
    return Torrent(
      rowid: int.tryParse(json['id'] ?? '0') ?? 0,
      infohash: json['info_hash'] ?? '',
      name: json['name'] ?? '',
      sizeBytes: int.tryParse(json['size'] ?? '0') ?? 0,
      createdUnix: int.tryParse(json['added'] ?? '0') ?? 0,
      seeders: int.tryParse(json['seeders'] ?? '0') ?? 0,
      leechers: int.tryParse(json['leechers'] ?? '0') ?? 0,
      completed: 0, // Pirate Bay doesn't provide completed count
      scrapedDate: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      category: json['category']?.toString(), // Capture category (5xx = NSFW)
      source: 'pirate_bay',
    );
  }
}
