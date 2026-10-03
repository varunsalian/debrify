import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

import 'debrid_catalog_state.dart';
import 'debrid_selection_state.dart';
import 'debrid_torrent_search_state.dart';

typedef DebridTorrentToolbarDeps = ({
  bool Function() isPushedRoute,
  bool Function() selectSourceMode,
  RDTorrent? Function() initialTorrentForOptions,
  BuildContext Function() context,
  DebridTorrentSearchState torrentSearchState,
  void Function() toggleTorrentSearch,
  DebridCatalogState catalogState,
  DebridSelectionState selectionState,
  void Function() toggleSelectionMode,
  Future<void> Function() handleDeleteAllTorrents,
  void Function() showAddMagnetDialog,
});

class DebridTorrentToolbar {
  DebridTorrentToolbar(this._deps);
  final DebridTorrentToolbarDeps _deps;

  /// Opened from the Cloud hub to browse (pushed, no deep-link target, not
  /// select-source) — the list root has no other Back affordance, so show one.
  bool get isBrowsePush =>
      _deps.isPushedRoute() &&
      !_deps.selectSourceMode() &&
      _deps.initialTorrentForOptions() == null;

  Widget buildTorrentToolbar() {
    final theme = Theme.of(_deps.context());
    final app = AppThemeScope.of(_deps.context());
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
              Tooltip(
                message: _deps.torrentSearchState.isTorrentSearchActive
                    ? 'Close search'
                    : 'Search torrents',
                child: IconButton(
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
              if (_deps.catalogState.torrents.isNotEmpty) ...[
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
                Tooltip(
                  message: 'Delete all torrents',
                  child: IconButton(
                    onPressed: _deps.handleDeleteAllTorrents,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    color: theme.colorScheme.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
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
            ],
          ),
        );
      },
    );
  }
}
