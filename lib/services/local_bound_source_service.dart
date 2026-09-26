import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/sources/data/local_source_file_rules.dart';
import '../features/sources/data/local_source_files.dart';
import '../features/sources/models/local_source_file.dart';
import '../models/series_source.dart';
import '../utils/file_utils.dart';
import 'android_local_source_service.dart';

export '../features/sources/models/local_source_file.dart'
    show LocalSeriesEpisodeFile;

class LocalBoundSourceService {
  static const String mobileDisabledReason =
      'Local source binding is not supported on iOS yet.';

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
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
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
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Choose a video file or browse a folder.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _LocalPickTile(
                    autofocus: true,
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
                    subtitle: Platform.isAndroid
                        ? 'Choose a movie file inside a folder'
                        : 'Match by filename, then use the largest match',
                    onTap: () =>
                        Navigator.of(sheetContext).pop(_LocalPickMode.folder),
                  ),
                ],
              ),
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

    if (Platform.isAndroid) return _pickAndroidSeries(context, title);

    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.trim().isEmpty) return null;
    if (!context.mounted) return null;

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
    final folderName = localPathName(resolvedPath).isNotEmpty
        ? localPathName(resolvedPath)
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
  ) async => (await scanLocalSeriesFolder(path)).toList();

  static bool get isLocalBindingDisabled => Platform.isIOS;

  static String? get localDisabledReason =>
      isLocalBindingDisabled ? mobileDisabledReason : null;

  static Future<SeriesSource?> _pickFile(BuildContext context) async {
    if (Platform.isAndroid) return _pickAndroidMovie(context, folder: false);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _videoExtensions,
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.trim().isEmpty) return null;
    return localSourceFromFile(File(path));
  }

  static Future<SeriesSource?> _pickFromFolder(
    BuildContext context, {
    required String title,
    String? year,
  }) async {
    if (Platform.isAndroid) return _pickAndroidMovie(context, folder: true);
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.trim().isEmpty) return null;

    final candidates = await scanLocalVideoFolder(path);
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

    final matched = matchLocalMovieFiles(candidates, title: title, year: year);
    if (matched != null) {
      return localSourceFromFile(matched.file);
    }

    if (!context.mounted) return null;
    final selected = await _showManualFileChooser(context, candidates);
    return selected == null ? null : localSourceFromFile(selected.file);
  }

  static Future<List<LocalSourceDocument>> _scanAndroidFolder(
    BuildContext context,
    String uri,
  ) async {
    final navigator = Navigator.of(context);
    final progress = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text('Reading local folder…')),
            ],
          ),
        ),
      ),
    );
    unawaited(navigator.push(progress));
    try {
      return await AndroidLocalSourceService.videos(uri);
    } finally {
      if (navigator.mounted && progress.isActive) {
        navigator.removeRoute(progress);
      }
    }
  }

  static Future<SeriesSource?> _pickAndroidMovie(
    BuildContext context, {
    required bool folder,
  }) async {
    try {
      final picked = await AndroidLocalSourceService.pick(directory: folder);
      if (picked == null || !context.mounted) return null;
      if (!folder) {
        if (picked.isDirectory || !FileUtils.isVideoFile(picked.name)) {
          _showSnack(context, 'Please select a video file.', isError: true);
          return null;
        }
        return picked.toSource();
      }
      final videos = await _scanAndroidFolder(context, picked.uri);
      if (!context.mounted) return null;
      if (videos.isEmpty) {
        _showSnack(
          context,
          'No video files found in that folder.',
          isError: true,
        );
        return null;
      }
      videos.sort((a, b) => a.relativePath.compareTo(b.relativePath));
      final selected = await showDialog<LocalSourceDocument>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Choose movie file'),
          content: SizedBox(
            width: 560,
            height: MediaQuery.sizeOf(dialogContext).height * 0.5,
            child: ListView.builder(
              itemCount: videos.length,
              itemBuilder: (_, index) => ListTile(
                autofocus: index == 0,
                title: Text(videos[index].name),
                subtitle: Text(videos[index].relativePath),
                onTap: () => Navigator.of(dialogContext).pop(videos[index]),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      return selected?.toSource();
    } on PlatformException catch (error) {
      if (context.mounted) {
        _showSnack(
          context,
          error.message ?? 'Local source could not be opened.',
          isError: true,
        );
      }
    } on LocalSourceUnavailable catch (error) {
      if (context.mounted) _showSnack(context, error.message, isError: true);
    }
    return null;
  }

  static Future<SeriesSource?> _pickAndroidSeries(
    BuildContext context,
    String title,
  ) async {
    try {
      final folder = await AndroidLocalSourceService.pick(directory: true);
      if (folder == null || !context.mounted) return null;
      final videos = await _scanAndroidFolder(context, folder.uri);
      final episodes = AndroidLocalSourceService.episodes(videos);
      if (!context.mounted) return null;
      if (episodes.isEmpty) {
        _showSnack(
          context,
          'No episodes found. Select this show’s folder with episode filenames such as S01E01.',
          isError: true,
        );
        return null;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: Text('Use folder for $title?'),
          content: Text(
            '${folder.name}\n${episodes.length} episodes found.\n\nChoose a folder containing only this series.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Use folder'),
            ),
          ],
        ),
      );
      return confirmed == true ? folder.toSource() : null;
    } on PlatformException catch (error) {
      if (context.mounted) {
        _showSnack(
          context,
          error.message ?? 'Local folder could not be opened.',
          isError: true,
        );
      }
    } on LocalSourceUnavailable catch (error) {
      if (context.mounted) _showSnack(context, error.message, isError: true);
    }
    return null;
  }

  static Future<Directory?> _resolveSeriesFolder(
    BuildContext context,
    String pickedPath, {
    required String title,
  }) async {
    final pickedFolder = Directory(pickedPath);
    if (!await pickedFolder.exists()) return null;

    if (localSeriesFolderMatchScore(localPathName(pickedPath), title) > 0) {
      return pickedFolder;
    }

    final matches = await matchingLocalSeriesFolders(pickedPath, title: title);
    if (matches.isEmpty) {
      if (context.mounted) {
        await _showSeriesFolderExpectationDialog(
          context,
          title: title,
          pickedFolderName: localPathName(pickedPath),
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
            style: TextStyle(fontWeight: FontWeight.w700),
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

  static Future<LocalSeriesFolderCandidate?> _showSeriesFolderChooser(
    BuildContext context, {
    required String title,
    required List<LocalSeriesFolderCandidate> candidates,
  }) {
    final visibleCandidates = candidates.take(40).toList();
    return showDialog<LocalSeriesFolderCandidate>(
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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

  static Future<LocalVideoCandidate?> _showManualFileChooser(
    BuildContext context,
    List<LocalVideoCandidate> candidates,
  ) {
    final visibleCandidates = candidates.take(80).toList();
    return showDialog<LocalVideoCandidate>(
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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

class _LocalPickTile extends StatelessWidget {
  final bool autofocus;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LocalPickTile({
    this.autofocus = false,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      autofocus: autofocus,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor: Colors.white.withValues(alpha: 0.05),
      leading: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
      onTap: onTap,
    );
  }
}
