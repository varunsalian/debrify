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
  pirateBay('pirate_bay', 'The Pirate Bay', 'https://apibay.org/q.php'),
  yts('yts', 'YTS', 'https://yts.mx/api/v2/list_movies.json'),
  solidTorrents('solid_torrents', 'SolidTorrents', 'https://solidtorrents.to/api/v1/search');

  const SearchEngineType(this.name, this.displayName, this.baseUrl);

  final String name;
  final String displayName;
  final String baseUrl;
} 
