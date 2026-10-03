import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

import 'torbox_focus_state.dart';

typedef TorboxSelectionBarDeps = ({
  BuildContext Function() context,
  Set<int> Function() activeSelectedIds,
  void Function() toggleSelectAll,
  bool Function() isAllSelected,
  TorboxFocusState focusState,
  Future<void> Function() handleDeleteSelected,
});

class TorboxSelectionBar {
  TorboxSelectionBar(this._deps);
  final TorboxSelectionBarDeps _deps;

  Widget buildSelectionBar() {
    final app = AppThemeScope.of(_deps.context());
    final theme = Theme.of(_deps.context());
    final count = _deps.activeSelectedIds().length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
