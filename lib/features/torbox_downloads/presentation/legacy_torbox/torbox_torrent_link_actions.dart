import 'package:debrify/features/torbox_downloads/application/torbox_file_policy.dart';
import 'package:debrify/models/torbox_file.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'torbox_catalog_state.dart';

typedef TorboxTorrentLinkActionsDeps = ({
  // TEMP(torbox): showComingSoon -> lib/features/torbox_downloads/presentation/legacy_torbox/torbox_magnet_actions.dart at step 4.
  void Function(String action) showComingSoon,
  TorboxCatalogState catalogState,
  bool Function() mounted,
  BuildContext Function() context,
});

class TorboxTorrentLinkActions {
  TorboxTorrentLinkActions(this._deps);
  final TorboxTorrentLinkActionsDeps _deps;

  Future<void> copyTorrentLink(TorboxTorrent torrent) async {
    if (torrent.files.isEmpty) {
      _deps.showComingSoon('No files available');
      return;
    }

    final file = torrent.files.firstWhere(
      (file) => !file.zipped,
      orElse: () => torrent.files.first,
    );

    await copyTorboxFileLink(torrent, file);
  }

  Future<void> copyTorboxFileLink(
    TorboxTorrent torrent,
    TorboxFile file,
  ) async {
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) {
      _deps.showComingSoon('Add Torbox API key');
      return;
    }

    try {
      final link = await TorboxService.requestFileDownloadLink(
        apiKey: key,
        torrentId: torrent.id,
        fileId: file.id,
      );
      if (!_deps.mounted()) return;
      await Clipboard.setData(ClipboardData(text: link));
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text('Download link copied to clipboard.')),
      );
    } catch (e) {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        SnackBar(
          content: Text('Failed to copy link: ${formatTorboxError(e)}'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> copyTorrentZipLink(TorboxTorrent torrent) async {
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) {
      _deps.showComingSoon('Add Torbox API key');
      return;
    }

    try {
      final zipUrl = TorboxService.createZipPermalink(key, torrent.id);
      await Clipboard.setData(ClipboardData(text: zipUrl));
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text('ZIP download link copied to clipboard.')),
      );
    } catch (e) {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        SnackBar(
          content: Text('Failed to copy ZIP link: ${formatTorboxError(e)}'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  void copyTorboxZipLink(TorboxTorrent torrent) {
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) {
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(
          content: Text('API key not available'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    final zipLink = TorboxService.createZipPermalink(key, torrent.id);
    Clipboard.setData(ClipboardData(text: zipLink));

    if (!_deps.mounted()) return;
    final app = AppThemeScope.of(_deps.context());
    ScaffoldMessenger.of(_deps.context()).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED),
                borderRadius: app.shape.br(8),
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'ZIP download link copied to clipboard!',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: app.cloud.dialogSurface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: app.shape.br(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
