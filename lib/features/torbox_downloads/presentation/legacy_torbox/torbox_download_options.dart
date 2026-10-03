import 'package:debrify/features/torbox_downloads/presentation/maybe_blur.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

typedef TorboxDownloadOptionsDeps = ({
  BuildContext Function() context,
  Future<void> Function(TorboxTorrent torrent) downloadAllTorrentFiles,
  Future<void> Function({
    required TorboxTorrent torrent,
    required BuildContext sheetContext,
  })
  enqueueTorboxZipDownload,
});

class TorboxDownloadOptions {
  TorboxDownloadOptions(this._deps);
  final TorboxDownloadOptionsDeps _deps;

  /// Show dialog with download options: select files or download as ZIP
  void showDownloadOptionsDialog(TorboxTorrent torrent) {
    showDialog(
      context: _deps.context(),
      builder: (dialogContext) {
        final app = AppThemeScope.of(dialogContext);
        return Dialog(
          backgroundColor: Colors.transparent,
          child: maybeBlur(
            Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [const Color(0xFF0F172A), app.cloud.dialogSurface],
                ),
                borderRadius: app.shape.br(24),
                border: Border.all(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.download_rounded,
                          color: Color(0xFF10B981),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Download Options',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close),
                          color: Colors.grey.shade400,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  // Options
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Option 1: Select files to download
                        buildDownloadOptionCard(
                          icon: Icons.checklist_rounded,
                          title: 'Select files to download',
                          description:
                              'Choose specific files from this torrent',
                          color: const Color(0xFF6366F1),
                          onTap: () {
                            Navigator.of(dialogContext).pop();
                            _deps.downloadAllTorrentFiles(torrent);
                          },
                        ),
                        const SizedBox(height: 12),
                        // Option 2: Download whole torrent as ZIP
                        buildDownloadOptionCard(
                          icon: Icons.folder_zip_rounded,
                          title: 'Download whole torrent as ZIP',
                          description:
                              'Download all files in a single ZIP archive',
                          color: const Color(0xFF10B981),
                          onTap: () {
                            _deps.enqueueTorboxZipDownload(
                              torrent: torrent,
                              sheetContext: dialogContext,
                            );
                          },
                        ),
                      ],
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

  /// Build a download option card for the dialog
  Widget buildDownloadOptionCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.15),
                color.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: color.withValues(alpha: 0.5),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
