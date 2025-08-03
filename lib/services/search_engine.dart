import '../models/torrent.dart';

abstract class SearchEngine {
  final String name;
  final String displayName;
  final String baseUrl;

  const SearchEngine({
    required this.name,
    required this.displayName,
    required this.baseUrl,
  });

  Future<List<Torrent>> search(String query);
  String getSearchUrl(String query);
}

enum SearchEngineType {
  torrentsCsv('torrents_csv', 'Torrents CSV', 'https://torrents-csv.com/service/search'),
  pirateBay('pirate_bay', 'The Pirate Bay', 'https://apibay.org/q.php');

  const SearchEngineType(this.name, this.displayName, this.baseUrl);

  final String name;
  final String displayName;
  final String baseUrl;
} 