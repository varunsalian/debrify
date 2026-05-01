import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../utils/file_utils.dart';
import '../utils/series_parser.dart';
import 'series_source_service.dart';

class LocalBoundSourceService {
  static const String mobileDisabledReason =
      'Local source binding is not supported on Android or iOS yet.';
  static const String _androidRestrictionMessage =
      'Local sources on Android are supported only from Downloads/Debrify.';

  static const List<String> _videoExtensions = [
    'mp4',
    'avi',
    'mkv',
    'mov',
    'wmv',
    'flv',
    'webm',
    'm4v',
    '3gp',
    'ts',
    'mts',
    'm2ts',
  ];

  static Future<SeriesSource?> pickMovieSource(
    BuildContext context, {
    required String title,
    String? year,
  }) async {
    if (isLocalBindingDisabled) {
      _showSnack(context, mobileDisabledReason, isError: true);
      return null;
    }

    final mode = await showModalBottomSheet<_LocalPickMode>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Local Movie Source',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Choose a video file or scan a folder for the best match.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 14),
                _LocalPickTile(
                  icon: Icons.movie_creation_outlined,
                  color: const Color(0xFF34D399),
                  title: 'Pick Video File',
                  subtitle: 'Bind one local movie file',
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_LocalPickMode.file),
                ),
                const SizedBox(height: 8),
                _LocalPickTile(
                  icon: Icons.folder_open_rounded,
                  color: const Color(0xFF60A5FA),
                  title: 'Pick Folder',
                  subtitle: 'Match by filename, then use the largest match',
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_LocalPickMode.folder),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (mode == null || !context.mounted) return null;

    return switch (mode) {
      _LocalPickMode.file => _pickFile(context),
      _LocalPickMode.folder => _pickFromFolder(
        context,
        title: title,
        year: year,
      ),
    };
  }

  static Future<SeriesSource?> pickSeriesSource(
    BuildContext context, {
    required String title,
  }) async {
    if (isLocalBindingDisabled) {
      _showSnack(context, mobileDisabledReason, isError: true);
      return null;
    }

    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.trim().isEmpty) return null;
    if (!context.mounted) return null;
    if (!_isSupportedLocalPath(path)) {
      if (context.mounted) {
        _showSnack(context, _androidRestrictionMessage, isError: true);
      }
      return null;
    }

    final seriesFolder = await _resolveSeriesFolder(
      context,
      path,
      title: title,
    );
    if (seriesFolder == null) return null;

    final resolvedPath = seriesFolder.path;
    final episodes = await scanSeriesFolder(resolvedPath);
    if (episodes.isEmpty) {
      if (context.mounted) {
        _showSnack(context, 'No episodes found in that folder', isError: true);
      }
      return null;
    }

    final stat = await seriesFolder.stat();
    final folderName = _folderName(resolvedPath).isNotEmpty
        ? _folderName(resolvedPath)
        : title;
    return SeriesSource(
      torrentHash: SeriesSource.localSourceHash(resolvedPath),
      torrentName: folderName,
      debridService: SeriesSource.localService,
      debridTorrentId: resolvedPath,
      boundAt: DateTime.now().millisecondsSinceEpoch,
      localPath: resolvedPath,
      localUri: Uri.directory(resolvedPath).toString(),
      localKind: SeriesSource.localKindSeriesFolder,
      localSizeBytes: episodes.length,
      localModifiedAt: stat.modified.millisecondsSinceEpoch,
    );
  }

  static Future<List<LocalSeriesEpisodeFile>> scanSeriesFolder(
    String path,
  ) async {
    final candidates = await _scanFolder(path);
    if (candidates.isEmpty) return [];

    final relativeNames = candidates
        .map((candidate) => _relativePath(path, candidate.file.path))
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
    return episodes;
  }

  static bool get isLocalBindingDisabled =>
      Platform.isAndroid || Platform.isIOS;

  static String? get localDisabledReason =>
      isLocalBindingDisabled ? mobileDisabledReason : null;

  static Future<SeriesSource?> _pickFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _videoExtensions,
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty) return null;
    if (!_isSupportedLocalPath(path)) {
      if (context.mounted) {
        _showSnack(context, _androidRestrictionMessage, isError: true);
      }
      return null;
    }
    return _sourceFromFile(File(path));
  }

  static Future<SeriesSource?> _pickFromFolder(
    BuildContext context, {
    required String title,
    String? year,
  }) async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.trim().isEmpty) return null;
    if (!_isSupportedLocalPath(path)) {
      if (context.mounted) {
        _showSnack(context, _androidRestrictionMessage, isError: true);
      }
      return null;
    }

    final candidates = await _scanFolder(path);
    if (candidates.isEmpty) {
      if (context.mounted) {
        _showSnack(
          context,
          'No video files found in that folder',
          isError: true,
        );
      }
      return null;
    }

    final matched = _matchMovieFiles(candidates, title: title, year: year);
    if (matched != null) {
      return _sourceFromFile(matched.file);
    }

    if (!context.mounted) return null;
    final selected = await _showManualFileChooser(context, candidates);
    return selected == null ? null : _sourceFromFile(selected.file);
  }

  static Future<List<_LocalVideoCandidate>> _scanFolder(String path) async {
    final root = Directory(path);
    if (!await root.exists()) return [];

    final candidates = <_LocalVideoCandidate>[];
    try {
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final name = _pathName(entity.path);
        if (!FileUtils.isVideoFile(name)) continue;
        try {
          final stat = await entity.stat();
          candidates.add(
            _LocalVideoCandidate(
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
      return candidates;
    }

    candidates.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return candidates;
  }

  static Future<Directory?> _resolveSeriesFolder(
    BuildContext context,
    String pickedPath, {
    required String title,
  }) async {
    final pickedFolder = Directory(pickedPath);
    if (!await pickedFolder.exists()) return null;

    if (_seriesFolderMatchScore(_folderName(pickedPath), title) > 0) {
      return pickedFolder;
    }

    final matches = await _matchingSeriesChildFolders(pickedPath, title: title);
    if (matches.isEmpty) {
      if (context.mounted) {
        await _showSeriesFolderExpectationDialog(
          context,
          title: title,
          pickedFolderName: _folderName(pickedPath),
        );
      }
      return null;
    }

    if (matches.length == 1) {
      return matches.single.directory;
    }

    if (!context.mounted) return null;
    final selected = await _showSeriesFolderChooser(
      context,
      title: title,
      candidates: matches,
    );
    return selected?.directory;
  }

  static Future<List<_SeriesFolderCandidate>> _matchingSeriesChildFolders(
    String pickedPath, {
    required String title,
  }) async {
    final root = Directory(pickedPath);
    final candidates = <_SeriesFolderCandidate>[];
    try {
      await for (final entity in root.list(
        recursive: false,
        followLinks: false,
      )) {
        if (entity is! Directory) continue;
        final folderName = _folderName(entity.path);
        final score = _seriesFolderMatchScore(folderName, title);
        if (score <= 0) continue;
        candidates.add(
          _SeriesFolderCandidate(
            directory: entity,
            folderName: folderName,
            score: score,
          ),
        );
      }
    } catch (_) {
      return candidates;
    }
    candidates.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      return a.folderName.compareTo(b.folderName);
    });
    return candidates;
  }

  static Future<void> _showSeriesFolderExpectationDialog(
    BuildContext context, {
    required String title,
    required String pickedFolderName,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Choose the Show Folder',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select the folder named like "$title".',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              _ExpectationRow(
                label: 'Good',
                value: 'TV Shows/$title/',
                color: Color(0xFF34D399),
              ),
              const SizedBox(height: 6),
              _ExpectationRow(
                label: 'Not',
                value: pickedFolderName.isEmpty
                    ? 'TV Shows/'
                    : '$pickedFolderName/',
                color: Color(0xFFF87171),
              ),
              const SizedBox(height: 12),
              const Text(
                'Episode files inside can still be named S01E01.mkv, S01E02.mkv, and so on.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'OK',
                style: TextStyle(color: Color(0xFF60A5FA)),
              ),
            ),
          ],
        );
      },
    );
  }

  static _LocalVideoCandidate? _matchMovieFiles(
    List<_LocalVideoCandidate> candidates, {
    required String title,
    String? year,
  }) {
    final titleTokens = _importantTokens(title);
    if (titleTokens.isEmpty) return null;

    final titleMatches = candidates.where((candidate) {
      final normalizedName = _normalize(candidate.fileName);
      return titleTokens.every(normalizedName.contains);
    }).toList();

    if (titleMatches.isEmpty) return null;

    final normalizedYear = year?.trim();
    if (normalizedYear != null && RegExp(r'^\d{4}$').hasMatch(normalizedYear)) {
      final yearMatches = titleMatches
          .where(
            (candidate) =>
                _normalize(candidate.fileName).contains(normalizedYear),
          )
          .toList();
      if (yearMatches.isNotEmpty) {
        yearMatches.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        return yearMatches.first;
      }
    }

    titleMatches.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return titleMatches.first;
  }

  static Future<_SeriesFolderCandidate?> _showSeriesFolderChooser(
    BuildContext context, {
    required String title,
    required List<_SeriesFolderCandidate> candidates,
  }) {
    final visibleCandidates = candidates.take(40).toList();
    return showDialog<_SeriesFolderCandidate>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose Series Folder',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Multiple folders matched "$title".',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: visibleCandidates.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final candidate = visibleCandidates[index];
                        return ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          tileColor: Colors.white.withValues(alpha: 0.05),
                          leading: const Icon(
                            Icons.folder_open_rounded,
                            color: Color(0xFF60A5FA),
                          ),
                          title: Text(
                            candidate.folderName,
                            style: const TextStyle(color: Colors.white),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            candidate.directory.path,
                            style: const TextStyle(color: Colors.white54),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () =>
                              Navigator.of(dialogContext).pop(candidate),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Future<_LocalVideoCandidate?> _showManualFileChooser(
    BuildContext context,
    List<_LocalVideoCandidate> candidates,
  ) {
    final visibleCandidates = candidates.take(80).toList();
    return showDialog<_LocalVideoCandidate>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose Local File',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'No confident filename match was found.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: visibleCandidates.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final candidate = visibleCandidates[index];
                        return ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          tileColor: Colors.white.withValues(alpha: 0.05),
                          leading: const Icon(
                            Icons.movie_outlined,
                            color: Color(0xFF60A5FA),
                          ),
                          title: Text(
                            candidate.fileName,
                            style: const TextStyle(color: Colors.white),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            _formatSize(candidate.sizeBytes),
                            style: const TextStyle(color: Colors.white54),
                          ),
                          onTap: () =>
                              Navigator.of(dialogContext).pop(candidate),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Future<SeriesSource?> _sourceFromFile(File file) async {
    if (!await file.exists()) return null;
    final name = _pathName(file.path);
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

  static List<String> _importantTokens(String value) {
    const stopWords = {'a', 'an', 'and', 'of', 'the'};
    return _normalize(value)
        .split(' ')
        .where((token) => token.length > 1 && !stopWords.contains(token))
        .toSet()
        .toList();
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\.[a-z0-9]{2,5}$'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static int _seriesFolderMatchScore(String folderName, String title) {
    final titleTokens = _importantTokens(title);
    if (titleTokens.isEmpty) return 0;

    final normalizedFolder = _normalize(folderName);
    if (normalizedFolder.isEmpty) return 0;
    final normalizedTitle = _normalize(title);
    final titleWithoutArticle = _withoutLeadingArticle(normalizedTitle);
    var score = titleTokens.length * 10;

    if (normalizedFolder == normalizedTitle) return score + 120;
    if (titleWithoutArticle != normalizedTitle &&
        normalizedFolder == titleWithoutArticle) {
      return score + 110;
    }
    if (normalizedTitle.length > 3 &&
        normalizedFolder.startsWith('$normalizedTitle ')) {
      return score + 80;
    }
    if (titleWithoutArticle.length > 3 &&
        titleWithoutArticle != normalizedTitle &&
        normalizedFolder.startsWith('$titleWithoutArticle ')) {
      return score + 70;
    }

    if (titleTokens.length < 2) return 0;
    final folderTokens = normalizedFolder.split(' ').toSet();
    if (!titleTokens.every(folderTokens.contains)) return 0;
    score -= (folderTokens.length - titleTokens.length).clamp(0, 20);
    return score;
  }

  static String _withoutLeadingArticle(String normalizedTitle) {
    return normalizedTitle.replaceFirst(RegExp(r'^(the|a|an) '), '');
  }

  static bool _isSupportedLocalPath(String path) {
    if (!Platform.isAndroid) return true;
    final normalizedRaw = path
        .trim()
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+'), '/')
        .toLowerCase();
    final normalized = normalizedRaw.startsWith('/')
        ? normalizedRaw
        : '/$normalizedRaw';
    return _isInsidePath(normalized, '/download/debrify') ||
        _isInsidePath(normalized, '/downloads/debrify');
  }

  static bool _isInsidePath(String normalizedPath, String normalizedRoot) {
    return normalizedPath.endsWith(normalizedRoot) ||
        normalizedPath.contains('$normalizedRoot/');
  }

  static void _showSnack(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? const Color(0xFFEF4444)
            : const Color(0xFF10B981),
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return 'Unknown size';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    final decimals = unit <= 1 ? 0 : 1;
    return '${size.toStringAsFixed(decimals)} ${units[unit]}';
  }

  static String _folderName(String path) {
    return _pathName(path);
  }

  static String _pathName(String path) {
    final normalized = path.trim().replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final index = trimmed.lastIndexOf('/');
    return index == -1 ? trimmed : trimmed.substring(index + 1);
  }

  static String _relativePath(String rootPath, String filePath) {
    final root = rootPath.replaceAll('\\', '/').replaceFirst(RegExp(r'/$'), '');
    final file = filePath.replaceAll('\\', '/');
    if (file == root) return _folderName(file);
    if (file.startsWith('$root/')) {
      return file.substring(root.length + 1);
    }
    return _pathName(filePath);
  }
}

enum _LocalPickMode { file, folder }

class _ExpectationRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ExpectationRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _SeriesFolderCandidate {
  final Directory directory;
  final String folderName;
  final int score;

  const _SeriesFolderCandidate({
    required this.directory,
    required this.folderName,
    required this.score,
  });
}

class _LocalVideoCandidate {
  final File file;
  final String fileName;
  final int sizeBytes;
  final int modifiedAt;

  const _LocalVideoCandidate({
    required this.file,
    required this.fileName,
    required this.sizeBytes,
    required this.modifiedAt,
  });
}

class LocalSeriesEpisodeFile {
  final File file;
  final String relativePath;
  final String fileName;
  final int season;
  final int episode;
  final int sizeBytes;
  final int modifiedAt;

  const LocalSeriesEpisodeFile({
    required this.file,
    required this.relativePath,
    required this.fileName,
    required this.season,
    required this.episode,
    required this.sizeBytes,
    required this.modifiedAt,
  });
}

class _LocalPickTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LocalPickTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor: Colors.white.withValues(alpha: 0.05),
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
      onTap: onTap,
    );
  }
}
