import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

import 'debrid_download_state.dart';
import 'debrid_selection_state.dart';

typedef DebridDownloadToolbarDeps = ({
  BuildContext Function() context,
  bool Function() isBrowsePush,
  DebridDownloadState downloadState,
  DebridSelectionState selectionState,
  void Function() toggleSelectionMode,
  Future<void> Function() handleDeleteAllDownloads,
  Future<void> Function() showAddLinkDialog,
});

class DebridDownloadToolbar {
  DebridDownloadToolbar(this._deps);
  final DebridDownloadToolbarDeps _deps;

  Widget buildDownloadToolbar() {
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
              if (_deps.isBrowsePush()) ...[
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
              if (_deps.downloadState.downloads.isNotEmpty) ...[
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
                  message: 'Delete all downloads',
                  child: IconButton(
                    onPressed: _deps.handleDeleteAllDownloads,
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
                message: 'Add file link',
                child: IconButton(
                  onPressed: _deps.showAddLinkDialog,
                  iconSize: iconSize,
                  padding: iconPadding,
                  constraints: iconConstraints,
                  icon: const Icon(Icons.note_add_outlined),
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
