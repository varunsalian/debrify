import 'package:flutter/services.dart';

import '../screens/video_player/models/playlist_entry.dart';
import '../utils/file_utils.dart';
import '../utils/series_parser.dart';
import 'series_source_service.dart';

/// Document URIs stay opaque: display names are used only for episode parsing.
class LocalSourceDocument {
  const LocalSourceDocument({
    required this.uri,
    required this.name,
    required this.relativePath,
    required this.isDirectory,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  factory LocalSourceDocument.fromMap(Map<dynamic, dynamic> map) =>
      LocalSourceDocument(
        uri: map['uri'] as String,
        name: map['name'] as String,
        relativePath: map['relativePath'] as String,
        isDirectory: map['isDirectory'] == true,
        sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
        modifiedAt: (map['modifiedAt'] as num?)?.toInt() ?? 0,
      );

  final String uri;
  final String name;
  final String relativePath;
  final bool isDirectory;
  final int sizeBytes;
  final int modifiedAt;

  SeriesSource toSource() => SeriesSource(
    torrentHash: SeriesSource.localSourceHash(uri),
    torrentName: name,
    debridService: SeriesSource.localService,
    debridTorrentId: uri,
    boundAt: DateTime.now().millisecondsSinceEpoch,
    localUri: uri,
    localKind: isDirectory
        ? SeriesSource.localKindSeriesFolder
        : SeriesSource.localKindMovieFile,
    localSizeBytes: sizeBytes,
    localModifiedAt: modifiedAt,
  );
}

class AndroidLocalEpisode {
  const AndroidLocalEpisode(this.document, this.season, this.episode);
  final LocalSourceDocument document;
  final int season;
  final int episode;
}

class AndroidLocalResolution {
  const AndroidLocalResolution(this.playlist, this.startIndex);
  final List<PlaylistEntry> playlist;
  final int startIndex;
}

class LocalSourceUnavailable implements Exception {
  const LocalSourceUnavailable(this.message);
  final String message;
}

abstract final class AndroidLocalSourceService {
  static const _channel = MethodChannel('debrify/local_sources');

  static String sourceUri(SeriesSource source) =>
      source.localUri ?? source.localPath ?? source.debridTorrentId;

  static bool isDocumentSource(SeriesSource source) =>
      Uri.tryParse(sourceUri(source))?.scheme == 'content';

  static Future<LocalSourceDocument?> pick({required bool directory}) async {
    final map = await _channel.invokeMapMethod<String, dynamic>(
      directory ? 'pickDirectory' : 'pickFile',
    );
    return map == null ? null : LocalSourceDocument.fromMap(map);
  }

  static Future<LocalSourceDocument> stat(String uri) async {
    final map = await _channel.invokeMapMethod<String, dynamic>('stat', {
      'uri': uri,
    });
    if (map == null) {
      throw const LocalSourceUnavailable(
        'Local source is unavailable. Select it again to restore access.',
      );
    }
    return LocalSourceDocument.fromMap(map);
  }

  static Future<List<LocalSourceDocument>> videos(String uri) async {
    final rows = await _channel.invokeListMethod<dynamic>('listFiles', {
      'uri': uri,
    });
    if (rows == null) {
      throw const LocalSourceUnavailable(
        'Local folder is unavailable. Reconnect it or select it again.',
      );
    }
    return rows
        .map((row) => LocalSourceDocument.fromMap(row as Map))
        .where((file) => !file.isDirectory && FileUtils.isVideoFile(file.name))
        .toList();
  }

  static List<AndroidLocalEpisode> episodes(List<LocalSourceDocument> files) {
    final parsed = SeriesParser.parsePlaylist(
      files.map((file) => file.relativePath).toList(),
      fileSizes: files.map((file) => file.sizeBytes).toList(),
    );
    final best = <String, AndroidLocalEpisode>{};
    for (var i = 0; i < files.length; i++) {
      final info = parsed[i];
      if (!info.isSeries ||
          info.season == null ||
          info.episode == null ||
          SeriesParser.isSampleFile(files[i].relativePath)) {
        continue;
      }
      final key = '${info.season}-${info.episode}';
      if (best[key] == null ||
          files[i].sizeBytes > best[key]!.document.sizeBytes) {
        best[key] = AndroidLocalEpisode(files[i], info.season!, info.episode!);
      }
    }
    return best.values.toList()..sort((a, b) {
      final season = a.season.compareTo(b.season);
      return season == 0 ? a.episode.compareTo(b.episode) : season;
    });
  }

  /// Re-query on every play so added episodes and restored drives are visible.
  /// Failures do not remove the saved binding or substitute a different episode.
  static Future<AndroidLocalResolution> resolve(
    SeriesSource source, {
    int? season,
    int? episode,
    bool series = false,
  }) async {
    final uri = sourceUri(source);
    if (series || source.isLocalSeriesFolder) {
      final available = episodes(await videos(uri));
      final index = available.indexWhere(
        (e) => e.season == season && e.episode == episode,
      );
      if (index < 0) {
        throw const LocalSourceUnavailable(
          'Requested episode was not found in the local folder.',
        );
      }
      return AndroidLocalResolution(
        available.map((e) => _entry(e.document)).toList(),
        index,
      );
    }
    final file = await stat(uri);
    if (file.isDirectory || !FileUtils.isVideoFile(file.name)) {
      throw const LocalSourceUnavailable(
        'The saved local movie file is unavailable.',
      );
    }
    return AndroidLocalResolution([_entry(file)], 0);
  }

  static PlaylistEntry _entry(LocalSourceDocument file) => PlaylistEntry(
    url: file.uri,
    title: file.relativePath,
    relativePath: file.relativePath,
    provider: SeriesSource.localService,
    sizeBytes: file.sizeBytes,
  );
}
