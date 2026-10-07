import 'dart:async';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation_state.dart';
import 'package:debrify/models/alldebrid_file.dart';
import 'package:debrify/models/alldebrid_link.dart';
import 'package:debrify/models/alldebrid_magnet.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/widgets/file_selection_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef AllDebridDownloadsDeps = ({
  AllDebridLibraryState libraryState,
  AllDebridNavigationState navigationState,
  BuildContext Function() context,
  bool Function() mounted,
  void Function() dismissLoading,
  Future<void> Function(
    List<Map<String, dynamic>> selected,
    List<AllDebridFile> allFiles,
    String magnetName,
  )
  downloadSelectedFiles,
  void Function(String message) showLoading,
  void Function(String message, {bool isError}) snack,
  Future<String> Function(String apiKey, String lockedLink) unlockStart,
});

class AllDebridDownloads {
  final AllDebridDownloadsDeps _deps;
  AllDebridDownloads(this._deps);
  AllDebridLibraryState get _library => _deps.libraryState;
  AllDebridNavigationState get _navigation => _deps.navigationState;

  // ── Download ─────────────────────────────────────────────────────────────

  Future<void> downloadFile(AllDebridFile file) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    _deps.showLoading('Preparing download…');
    final url = await _deps.unlockStart(apiKey, file.link);
    _deps.dismissLoading();
    if (!_deps.mounted()) return;
    if (url.isEmpty) {
      _deps.snack('Failed to unlock this file.', isError: true);
      return;
    }
    try {
      await DownloadService.instance.enqueueDownload(
        credentialKey: 'alldebrid_api_key',
        url: url,
        fileName: file.fileName,
        context: _deps.mounted() ? _deps.context() : null,
      );
      _deps.snack('Download queued: ${file.fileName}', isError: false);
    } catch (e) {
      _deps.snack('Failed to download: $e', isError: true);
    }
  }

  Future<void> downloadMagnet(AllDebridMagnet magnet) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    List<AllDebridFile> files = _navigation.currentFiles;
    if (_navigation.currentMagnet?.id != magnet.id || files.isEmpty) {
      _deps.showLoading('Scanning magnet…');
      try {
        files = await AllDebridService.getMagnetFiles(apiKey, magnet.id);
      } catch (e) {
        _deps.dismissLoading();
        _deps.snack('Failed to scan magnet: $e', isError: true);
        return;
      }
      _deps.dismissLoading();
    }
    if (!_deps.mounted()) return;
    if (files.isEmpty) {
      _deps.snack('This magnet has no files.', isError: true);
      return;
    }
    final dialogFiles = <Map<String, dynamic>>[];
    for (int i = 0; i < files.length; i++) {
      dialogFiles.add({
        'name': files[i].path,
        '_fullPath': files[i].path,
        'size': files[i].size.toString(),
        '_adIndex': i,
      });
    }
    await showDialog(
      context: _deps.context(),
      builder: (ctx) => FileSelectionDialog(
        files: dialogFiles,
        torrentName: magnet.name,
        onDownload: (selected) =>
            _deps.downloadSelectedFiles(selected, files, magnet.name),
      ),
    );
  }

  Future<void> downloadSelectedFiles(
    List<Map<String, dynamic>> selected,
    List<AllDebridFile> allFiles,
    String magnetName,
  ) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    if (selected.isEmpty) return;
    int success = 0, fail = 0;
    for (final f in selected) {
      final idx = f['_adIndex'] as int? ?? -1;
      if (idx < 0 || idx >= allFiles.length) {
        fail++;
        continue;
      }
      final target = allFiles[idx];
      final url = await _deps.unlockStart(apiKey, target.link);
      if (url.isEmpty) {
        fail++;
        continue;
      }
      try {
        await DownloadService.instance.enqueueDownload(
          credentialKey: 'alldebrid_api_key',
          url: url,
          fileName: target.fileName,
          torrentName: magnetName,
          context: _deps.mounted() ? _deps.context() : null,
        );
        success++;
      } catch (_) {
        fail++;
      }
    }
    if (!_deps.mounted()) return;
    if (success > 0 && fail == 0) {
      _deps.snack(
        'Queued $success file${success == 1 ? '' : 's'}',
        isError: false,
      );
    } else if (success > 0) {
      _deps.snack('Queued $success, $fail failed', isError: true);
    } else {
      _deps.snack('Failed to queue any files', isError: true);
    }
  }

  Future<void> downloadLink(AllDebridLink l) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    _deps.showLoading('Preparing download…');
    final url = await _deps.unlockStart(apiKey, l.link);
    _deps.dismissLoading();
    if (!_deps.mounted()) return;
    if (url.isEmpty) {
      _deps.snack('Failed to unlock this link.', isError: true);
      return;
    }
    try {
      await DownloadService.instance.enqueueDownload(
        credentialKey: 'alldebrid_api_key',
        url: url,
        fileName: l.fileName,
        context: _deps.mounted() ? _deps.context() : null,
      );
      _deps.snack('Download queued: ${l.fileName}', isError: false);
    } catch (e) {
      _deps.snack('Failed to download: $e', isError: true);
    }
  }

  Future<void> copyLink(AllDebridLink l) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    _deps.showLoading('Unlocking…');
    final url = await _deps.unlockStart(apiKey, l.link);
    _deps.dismissLoading();
    if (!_deps.mounted()) return;
    if (url.isEmpty) {
      _deps.snack('Failed to unlock this link.', isError: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!_deps.mounted()) return;
    _deps.snack('Link copied', isError: false);
  }
}
