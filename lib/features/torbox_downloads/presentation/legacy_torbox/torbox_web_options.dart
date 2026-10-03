import 'package:debrify/features/torbox_downloads/presentation/maybe_blur.dart';
import 'package:debrify/models/torbox_web_download.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

typedef TorboxWebOptionsDeps = ({
  BuildContext Function() context,
  Widget Function({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  })
  buildDownloadOptionCard,
  Future<void> Function(TorboxWebDownload webDownload) downloadWebDownloadFiles,
  Future<void> Function({
    required TorboxWebDownload webDownload,
    required BuildContext sheetContext,
  })
  enqueueWebDownloadZipDownload,
});

class TorboxWebOptions {
  TorboxWebOptions(this._deps);
  final TorboxWebOptionsDeps _deps;

  /// Show dialog with download options for web downloads: select files or download as ZIP
  void showWebDownloadOptionsDialog(TorboxWebDownload webDownload) {
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
                        _deps.buildDownloadOptionCard(
                          icon: Icons.checklist_rounded,
                          title: 'Select files to download',
                          description:
                              'Choose specific files from this download',
                          color: const Color(0xFF6366F1),
                          onTap: () {
                            Navigator.of(dialogContext).pop();
                            _deps.downloadWebDownloadFiles(webDownload);
                          },
                        ),
                        const SizedBox(height: 12),
                        // Option 2: Download as ZIP
                        _deps.buildDownloadOptionCard(
                          icon: Icons.folder_zip_rounded,
                          title: 'Download as ZIP',
                          description:
                              'Download all files in a single ZIP archive',
                          color: const Color(0xFF10B981),
                          onTap: () {
                            _deps.enqueueWebDownloadZipDownload(
                              webDownload: webDownload,
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
}
