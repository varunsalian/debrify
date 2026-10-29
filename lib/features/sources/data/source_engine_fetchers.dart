import 'dart:async';

import 'package:debrify/models/indexer_manager_config.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/media_server_service.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/source_search_preferences.dart';
import 'package:debrify/services/torrent_service.dart';

final class SourceEngineFetchers {
  const SourceEngineFetchers._();

  static Future<List<SourceAddonRef>> mediaServerSourceRefs() async {
    if (!(await SourceSearchPreferences.readOrDefault()).mediaServers) {
      return const [];
    }
    return [
      for (final server in await MediaServerService.connections())
        SourceAddonRef(
          'mediaserver:${server.id}',
          server.label,
          addonKey: 'mediaserver:${server.id}',
          resultSourceKey: 'mediaserver:${server.id}',
        ),
    ];
  }

  static Future<List<Torrent>?> fetchMediaServerSources(
    String sourceKey,
    String contentId,
    bool isMovie,
    int? season,
    int? episode,
  ) async {
    final result = await MediaServerService.search(
      id: contentId,
      isMovie: isMovie,
      season: season,
      episode: episode,
      resourceFilter: sourceKey.substring('mediaserver:'.length),
    );
    if ((result['addonErrors'] as Map).isNotEmpty) return null;
    return result['torrents'] as List<Torrent>;
  }

  static Future<List<SourceEngineRef>> sourceEngineListing() async {
    final engines = await TorrentService.getImdbSearchEngines();
    final refs = <SourceEngineRef>[];
    for (final engine in engines) {
      if (!await TorrentService.isEngineEnabled(engine.name)) continue;
      final source = IndexerManagerConfig.isIndexerManagerEngine(engine.name)
          ? engine.displayName
          : engine.name;
      refs.add(
        SourceEngineRef(engine.name, engine.displayName, source.toLowerCase()),
      );
    }
    return refs;
  }

  static Future<List<Torrent>?> fetchOneEngine(
    String engineId, {
    required String imdbId,
    required bool isMovie,
    int? season,
    int? episode,
  }) async {
    try {
      final engines = await TorrentService.getImdbSearchEngines();
      final states = <String, bool>{for (final e in engines) e.name: false};
      states[engineId] = true;
      final result = await TorrentService.searchByImdb(
        imdbId,
        engineStates: states,
        isMovie: isMovie,
        season: season,
        episode: episode,
      );
      final errors = result['engineErrors'] as Map<String, String>? ?? const {};
      if (errors.containsKey(engineId)) return null;
      return result['torrents'] as List<Torrent>? ?? const <Torrent>[];
    } catch (_) {
      return null;
    }
  }
}
