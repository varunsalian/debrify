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
