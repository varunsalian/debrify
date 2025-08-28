import '../models/torrent.dart';
import 'search_engine_factory.dart';
import 'search_engine.dart';

class TorrentService {
  static Future<List<Torrent>> searchTorrents(String query, {String? engineName}) async {
    final engine = engineName != null 
        ? SearchEngineFactory.getEngine(engineName)
        : SearchEngineFactory.getDefaultEngine();
    
    return await engine.search(query);
  }

  static Future<Map<String, dynamic>> searchAllEngines(String query, {
    bool useTorrentsCsv = true,
    bool usePirateBay = true,
  }) async {
    final engines = SearchEngineFactory.getAllEngines();
    final engineNames = SearchEngineFactory.getAllEngineNames();
    final List<List<Torrent>> allResults = [];
    final Map<String, int> engineCounts = {};
    
    // Filter engines based on user selection
    final List<SearchEngine> selectedEngines = [];
    final List<String> selectedEngineNames = [];
    
    for (int i = 0; i < engines.length; i++) {
      final engine = engines[i];
      final engineName = engineNames[i];
      
      if ((engineName == 'torrents_csv' && useTorrentsCsv) ||
          (engineName == 'pirate_bay' && usePirateBay)) {
        selectedEngines.add(engine);
        selectedEngineNames.add(engineName);
      }
    }
    
    // If no engines selected, return empty results
    if (selectedEngines.isEmpty) {
      return {
        'torrents': <Torrent>[],
        'engineCounts': <String, int>{},
      };
    }
    
    // Search selected engines concurrently
    final futures = selectedEngines.map((engine) => engine.search(query));
    final results = await Future.wait(futures);
    
    // Combine all results and track counts
    for (int i = 0; i < results.length; i++) {
      final result = results[i];
      final engineName = selectedEngineNames[i];
      allResults.add(result);
      engineCounts[engineName] = result.length;
    }
    
    // Deduplicate based on infohash
    final Map<String, Torrent> uniqueTorrents = {};
    for (final torrentList in allResults) {
      for (final torrent in torrentList) {
        if (!uniqueTorrents.containsKey(torrent.infohash)) {
          uniqueTorrents[torrent.infohash] = torrent;
        }
      }
    }
    
    // Convert back to list and sort by seeders (descending)
    final deduplicatedResults = uniqueTorrents.values.toList();
    deduplicatedResults.sort((a, b) => b.seeders.compareTo(a.seeders));
    
    return {
      'torrents': deduplicatedResults,
      'engineCounts': engineCounts,
    };
  }

  static List<SearchEngine> getAvailableEngines() {
    return SearchEngineFactory.getAllEngines();
  }

  static List<String> getAvailableEngineNames() {
    return SearchEngineFactory.getAllEngineNames();
  }

  static List<String> getAvailableEngineDisplayNames() {
    return SearchEngineFactory.getAllEngineDisplayNames();
  }
} 