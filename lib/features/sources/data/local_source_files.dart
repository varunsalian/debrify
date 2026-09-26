import 'dart:io';

import '../../../models/series_source.dart';
import '../../../utils/file_utils.dart';
import '../../../utils/series_parser.dart';
import '../models/local_source_file.dart';
import 'local_source_file_rules.dart';

Future<List<LocalSeriesEpisodeFile>> scanLocalSeriesFolder(String path) async {
  final candidates = await scanLocalVideoFolder(path);
  if (candidates.isEmpty) return const [];

  final relativeNames = candidates
      .map((candidate) => localRelativePath(path, candidate.file.path))
      .toList();
  final sizes = candidates.map((candidate) => candidate.sizeBytes).toList();
  final parsed = SeriesParser.parsePlaylist(relativeNames, fileSizes: sizes);
  final bestByEpisode = <String, LocalSeriesEpisodeFile>{};

  for (int i = 0; i < candidates.length; i++) {
    final info = parsed[i];
    final season = info.season;
    final episode = info.episode;
    if (!info.isSeries || season == null || episode == null) continue;
    if (SeriesParser.isSampleFile(relativeNames[i])) continue;

    final candidate = candidates[i];
    final entry = LocalSeriesEpisodeFile(
      file: candidate.file,
      relativePath: relativeNames[i],
      fileName: candidate.fileName,
      season: season,
      episode: episode,
      sizeBytes: candidate.sizeBytes,
      modifiedAt: candidate.modifiedAt,
    );
    final key = '$season-$episode';
    final existing = bestByEpisode[key];
    if (existing == null || entry.sizeBytes > existing.sizeBytes) {
      bestByEpisode[key] = entry;
    }
  }

  final episodes = bestByEpisode.values.toList();
  episodes.sort((a, b) {
    final seasonCompare = a.season.compareTo(b.season);
    if (seasonCompare != 0) return seasonCompare;
    final episodeCompare = a.episode.compareTo(b.episode);
    if (episodeCompare != 0) return episodeCompare;
    return a.relativePath.compareTo(b.relativePath);
  });
  return List.unmodifiable(episodes);
}

Future<List<LocalVideoCandidate>> scanLocalVideoFolder(String path) async {
  final root = Directory(path);
  if (!await root.exists()) return const [];

  final candidates = <LocalVideoCandidate>[];
  try {
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = localPathName(entity.path);
      if (!FileUtils.isVideoFile(name)) continue;
      try {
        final stat = await entity.stat();
        candidates.add(
          LocalVideoCandidate(
            file: entity,
            fileName: name,
            sizeBytes: stat.size,
            modifiedAt: stat.modified.millisecondsSinceEpoch,
          ),
        );
      } catch (_) {
        // Skip files that cannot be statted.
      }
    }
  } catch (_) {
    return List.unmodifiable(candidates);
  }

  candidates.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
  return List.unmodifiable(candidates);
}

Future<List<LocalSeriesFolderCandidate>> matchingLocalSeriesFolders(
  String pickedPath, {
  required String title,
}) async {
  final root = Directory(pickedPath);
  final candidates = <LocalSeriesFolderCandidate>[];
  try {
    await for (final entity in root.list(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is! Directory) continue;
      final folderName = localPathName(entity.path);
      final score = localSeriesFolderMatchScore(folderName, title);
      if (score <= 0) continue;
      candidates.add(
        LocalSeriesFolderCandidate(
          directory: entity,
          folderName: folderName,
          score: score,
        ),
      );
    }
  } catch (_) {
    return List.unmodifiable(candidates);
  }
  candidates.sort((a, b) {
    final scoreCompare = b.score.compareTo(a.score);
    if (scoreCompare != 0) return scoreCompare;
    return a.folderName.compareTo(b.folderName);
  });
  return List.unmodifiable(candidates);
}

Future<SeriesSource?> localSourceFromFile(File file) async {
  if (!await file.exists()) return null;
  final name = localPathName(file.path);
  if (!FileUtils.isVideoFile(name)) return null;

  final stat = await file.stat();
  return SeriesSource(
    torrentHash: SeriesSource.localSourceHash(file.path),
    torrentName: name,
    debridService: SeriesSource.localService,
    debridTorrentId: file.path,
    boundAt: DateTime.now().millisecondsSinceEpoch,
    localPath: file.path,
    localUri: Uri.file(file.path).toString(),
    localKind: SeriesSource.localKindMovieFile,
    localSizeBytes: stat.size,
    localModifiedAt: stat.modified.millisecondsSinceEpoch,
  );
}
