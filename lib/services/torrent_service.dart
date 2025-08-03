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