import 'search_engine.dart';
import 'torrents_csv_engine.dart';
import 'pirate_bay_engine.dart';

class SearchEngineFactory {
  static final Map<String, SearchEngine> _engines = {
    'torrents_csv': const TorrentsCsvEngine(),
    'pirate_bay': const PirateBayEngine(),
  };

  static SearchEngine getEngine(String name) {
    return _engines[name] ?? const TorrentsCsvEngine();
  }

  static List<SearchEngine> getAllEngines() {
    return _engines.values.toList();
  }

  static List<String> getAllEngineNames() {
    return _engines.keys.toList();
  }

  static List<String> getAllEngineDisplayNames() {
    return _engines.values.map((e) => e.displayName).toList();
  }

  static SearchEngine getDefaultEngine() {
    return const TorrentsCsvEngine();
  }
} 