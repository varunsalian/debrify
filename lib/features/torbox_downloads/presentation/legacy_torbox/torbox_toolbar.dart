import 'package:debrify/features/torbox_downloads/presentation/torbox_downloads_view.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';
import 'torbox_focus_state.dart';
import 'torbox_selection_state.dart';
import 'torbox_torrent_search_state.dart';
import 'torbox_web_state.dart';

typedef TorboxToolbarDeps = ({
  bool Function() isPushedRoute,
  bool Function() selectSourceMode,
  TorboxTorrent? Function() initialTorrentToOpen,
  BuildContext Function() context,
  TorboxCatalogState catalogState,
  TorboxWebState webState,
  TorboxSelectionState selectionState,
  void Function() toggleSelectionMode,
  Future<void> Function() confirmDeleteAll,
  TorboxTorrentSearchState torrentSearchState,
  TorboxFocusState focusState,
  void Function() toggleTorrentSearch,
  Future<void> Function() showAddMagnetDialog,
  Future<void> Function() showAddWebDownloadDialog,
});

class TorboxToolbar {
  TorboxToolbar(this._deps);
  final TorboxToolbarDeps _deps;

  /// Opened from the Cloud hub to browse (pushed, no deep-link target, not
  /// select-source) — the list root otherwise has no Back affordance.
  bool get isBrowsePush =>
      _deps.isPushedRoute() &&
      !_deps.selectSourceMode() &&
      _deps.initialTorrentToOpen() == null;

  Widget buildToolbar() {
    final theme = Theme.of(_deps.context());
    final app = AppThemeScope.of(_deps.context());
    final isTorrentsView =
        _deps.catalogState.selectedView == TorboxDownloadsView.torrents;
    final hasItems = isTorrentsView
        ? _deps.catalogState.torrents.isNotEmpty
        : _deps.webState.webDownloads.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 480;
        final double iconSize = isCompact ? 20 : 24;
        final EdgeInsets iconPadding = isCompact
            ? const EdgeInsets.all(6)
            : const EdgeInsets.all(8);
        final BoxConstraints iconConstraints = isCompact
            ? const BoxConstraints(minWidth: 36, minHeight: 36)
            : const BoxConstraints(minWidth: 44, minHeight: 44);
        return Container(
          margin: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 16,
            vertical: 8,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 16,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: app.fade(app.core.tx, 0.05),
            borderRadius: app.shape.br(12),
            border: Border.all(color: app.fade(app.core.tx, 0.08)),
          ),
          child: Row(
            children: [
              if (isBrowsePush) ...[
                Tooltip(
                  message: 'Back',
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.arrow_back),
                    color: theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                SizedBox(width: isCompact ? 4 : 8),
              ],
              const Spacer(),
              if (hasItems) ...[
                Tooltip(
                  message: _deps.selectionState.isSelectionMode
                      ? 'Exit selection'
                      : 'Select items',
                  child: IconButton(
                    onPressed: _deps.toggleSelectionMode,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: Icon(
                      _deps.selectionState.isSelectionMode
                          ? Icons.close
                          : Icons.checklist_outlined,
                    ),
                    color: _deps.selectionState.isSelectionMode
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                if (isTorrentsView)
                  Tooltip(
                    message: 'Delete all torrents',
                    child: IconButton(
                      onPressed: _deps.confirmDeleteAll,
                      iconSize: iconSize,
                      padding: iconPadding,
                      constraints: iconConstraints,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      color: theme.colorScheme.error,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
              if (isTorrentsView) ...[
                Tooltip(
                  message: _deps.torrentSearchState.isTorrentSearchActive
                      ? 'Close search'
                      : 'Search torrents',
                  child: IconButton(
                    focusNode: _deps.focusState.torrentSearchToggleFocusNode,
                    onPressed: _deps.toggleTorrentSearch,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: Icon(
                      _deps.torrentSearchState.isTorrentSearchActive
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                    ),
                    color: _deps.torrentSearchState.isTorrentSearchActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Tooltip(
                  message: 'Add magnet link',
                  child: IconButton(
                    onPressed: _deps.showAddMagnetDialog,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.add_circle_outline),
                    color: theme.colorScheme.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ] else ...[
                Tooltip(
                  message: 'Add web download',
                  child: IconButton(
                    onPressed: _deps.showAddWebDownloadDialog,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.link),
                    color: theme.colorScheme.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
