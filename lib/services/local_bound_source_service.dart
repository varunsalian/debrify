import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/sources/data/local_source_file_rules.dart';
import '../features/sources/data/local_source_files.dart';
import '../features/sources/models/local_source_file.dart';
import '../features/sources/presentation/local_movie_pick_mode_sheet.dart';
import '../features/sources/presentation/local_source_choice_dialogs.dart';
import '../features/sources/presentation/local_series_folder_help.dart';
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

    final mode = await showLocalMoviePickMode(
      context,
      androidFolderSelection: Platform.isAndroid,
    );

    if (mode == null || !context.mounted) return null;

    return switch (mode) {
      LocalMoviePickMode.file => _pickFile(context),
      LocalMoviePickMode.folder => _pickFromFolder(
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
    final selected = await showLocalFileChoice(context, candidates);
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
        await showLocalSeriesFolderHelp(
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
    final selected = await showLocalSeriesFolderChoice(
      context,
      title: title,
      candidates: matches,
    );
    return selected?.directory;
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

}
