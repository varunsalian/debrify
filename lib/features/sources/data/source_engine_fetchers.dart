import 'dart:async';

import 'package:debrify/features/sources/data/webdav_quick_play_search.dart';
import 'package:debrify/features/sources/data/webdav_source_search.dart';
import 'package:debrify/features/sources/models/webdav_source_status.dart';
import 'package:debrify/models/advanced_search_selection.dart';
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

  /// Media-server and WebDAV sources: whole libraries, never season packs.
  static bool isLibrary(String sourceKey) =>
      sourceKey.startsWith('mediaserver:') || sourceKey.startsWith('webdav:');

  /// One entry per WebDAV server the profile may search, so the player's
  /// source sheet can fetch each separately.
  static Future<List<SourceAddonRef>> webDavSourceRefs() async => [
    for (final (key, name) in await WebDavSourceSearch().serverRefs())
      SourceAddonRef(
        key,
        'WebDAV · $name',
        addonKey: key,
        resultSourceKey: key,
      ),
  ];

  /// One server's title matches, for the player's source sheet. Null when the
  /// server could not be searched, so the sheet keeps a retry row.
  static Future<List<Torrent>?> fetchWebDavSources(
    String sourceKey, {
    required String title,
    String? imdbId,
    String? year,
    required bool isMovie,
    int? season,
    int? episode,
  }) async {
    final rows = <Torrent>[];
    // The sheet's own budget: the player may close before a full walk ends.
    final statuses =
        await WebDavSourceSearch(limits: WebDavQuickPlaySearch.limits).search(
          AdvancedSearchSelection(
            imdbId: imdbId ?? '',
            title: title,
            year: year,
            isSeries: !isMovie,
            season: isMovie ? null : season,
            episode: isMovie ? null : episode,
          ),
          onlyServerKey: sourceKey,
          shouldContinue: () => true,
          onStatus: (_) {},
          onRows: (_, found) => rows.addAll(found),
        );
    final failed = statuses.any(
      (status) =>
          status.phase == WebDavSearchPhase.failed ||
          status.phase == WebDavSearchPhase.timedOut,
    );
    return rows.isEmpty && failed ? null : rows;
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
