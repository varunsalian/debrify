import 'package:debrify/features/torbox_downloads/presentation/maybe_blur.dart';
import 'package:debrify/features/torbox_downloads/presentation/torbox_more_option.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

typedef TorboxTorrentOptionsDeps = ({
  Future<void> Function(TorboxTorrent torrent) handleAddToPlaylist,
  Future<void> Function(TorboxTorrent torrent) handleAddToDebrifyTv,
  Future<void> Function(TorboxTorrent torrent) copyTorrentZipLink,
  Future<void> Function(TorboxTorrent torrent) copyTorrentLink,
  Future<void> Function(TorboxTorrent torrent) confirmDeleteTorrent,
  BuildContext Function() context,
});

class TorboxTorrentOptions {
  TorboxTorrentOptions(this._deps);
  final TorboxTorrentOptionsDeps _deps;

  void showTorboxTorrentMoreOptions(TorboxTorrent torrent) {
    final isMultiFile = torrent.files.length > 1;
    final options = <TorboxMoreOption>[
      TorboxMoreOption(
        icon: Icons.playlist_add,
        label: 'Add to Playlist',
        onTap: () => _deps.handleAddToPlaylist(torrent),
      ),
      TorboxMoreOption(
        icon: Icons.live_tv_rounded,
        label: 'Add to Debrify TV',
        onTap: () => _deps.handleAddToDebrifyTv(torrent),
      ),
      TorboxMoreOption(
        icon: Icons.copy,
        label: 'Copy Link',
        onTap: isMultiFile
            ? () => _deps.copyTorrentZipLink(torrent)
            : () => _deps.copyTorrentLink(torrent),
      ),
      TorboxMoreOption(
        icon: Icons.delete_outline,
        label: 'Delete Torrent',
        onTap: () => _deps.confirmDeleteTorrent(torrent),
        destructive: true,
      ),
    ];

    showDialog(
      context: _deps.context(),
      builder: (sheetContext) {
        final app = AppThemeScope.of(sheetContext);
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final option in options) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: InkWell(
                          onTap: option.enabled
                              ? () async {
                                  Navigator.of(sheetContext).pop();
                                  await option.onTap();
                                }
                              : null,
                          borderRadius: app.shape.br(16),
                          splashColor: option.enabled
                              ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                              : Colors.transparent,
                          highlightColor: option.enabled
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.transparent,
                          child: Opacity(
                            opacity: option.enabled ? 1.0 : 0.45,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF111C32),
                                borderRadius: app.shape.br(16),
                                border: Border.all(
                                  color: const Color(
                                    0xFF475569,
                                  ).withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    option.icon,
                                    size: 20,
                                    color: option.destructive
                                        ? const Color(0xFFEF4444)
                                        : Colors.white,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      option.label,
                                      style: TextStyle(
                                        color: option.destructive
                                            ? const Color(0xFFEF4444)
                                            : Theme.of(
                                                _deps.context(),
                                              ).colorScheme.onSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 20,
                                    color: Colors.white.withValues(alpha: 0.25),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
