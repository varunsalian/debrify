import 'package:debrify/features/pikpak_files/models/folder_view_mode.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pikpak_focus_state.dart';
import 'pikpak_selection_state.dart';

typedef PikpakToolbarLayoutDeps = ({
  BuildContext Function() context,
  FolderViewMode Function() getCurrentViewMode,
  PikpakFocusState focusState,
  Future<void> Function(FolderViewMode mode) setViewMode,
  PikpakSelectionState selectionState,
  void Function() toggleSelectAll,
  bool Function() isAllSelected,
  Future<void> Function() handleDeleteSelected,
});

class PikpakToolbarLayout {
  PikpakToolbarLayout(this._deps);
  final PikpakToolbarLayoutDeps _deps;

  /// Build the view mode dropdown (shown below AppBar when inside folders)
  Widget buildViewModeDropdown() {
    final theme = Theme.of(_deps.context());
    final mode = _deps.getCurrentViewMode();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Focus(
        skipTraversal: true,
        onKeyEvent: (node, event) {
          // Navigate to back button on up arrow
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _deps.focusState.backButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: DropdownButtonFormField<FolderViewMode>(
          focusNode: _deps.focusState.viewModeDropdownFocusNode,
          autofocus: true,
          isExpanded: true,
          value: mode,
          decoration: InputDecoration(
            labelText: 'View Mode',
            prefixIcon: Icon(
              mode == FolderViewMode.raw
                  ? Icons.view_list
                  : mode == FolderViewMode.sortedAZ
                  ? Icons.sort_by_alpha
                  : Icons.video_library,
              color: theme.colorScheme.primary,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          items: const [
            DropdownMenuItem(value: FolderViewMode.raw, child: Text('Raw')),
            DropdownMenuItem(
              value: FolderViewMode.sortedAZ,
              child: Text('Sort (A-Z)'),
            ),
          ],
          onChanged: (value) {
            if (value != null) _deps.setViewMode(value);
          },
        ),
      ),
    );
  }

  Widget buildSelectionBar() {
    final app = AppThemeScope.of(_deps.context());
    final theme = Theme.of(_deps.context());
    final count = _deps.selectionState.selectedFileIds.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: app.shape.br(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$count selected',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _deps.toggleSelectAll,
            child: Text(_deps.isAllSelected() ? 'Deselect All' : 'Select All'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            focusNode: _deps.focusState.deleteButtonFocusNode,
            onPressed: count > 0 ? _deps.handleDeleteSelected : null,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style:
                FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  disabledBackgroundColor: theme.colorScheme.error.withValues(
                    alpha: 0.3,
                  ),
                ).copyWith(
                  side: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.focused)) {
                      return BorderSide(color: app.core.tx, width: 3);
                    }
                    return null;
                  }),
                ),
          ),
        ],
      ),
    );
  }
}
