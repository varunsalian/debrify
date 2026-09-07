import 'package:flutter/material.dart';

import '../../theme/app_theme_scope.dart';

/// The multi-select action bar shared by the TorBox and Real-Debrid cloud
/// files screens (G4-5). Moved verbatim from the byte-identical
/// `_buildSelectionBar` each host carried; the host state it read is now
/// passed in.
class CloudSelectionBar extends StatelessWidget {
  const CloudSelectionBar({
    super.key,
    required this.selectedCount,
    required this.isAllSelected,
    required this.onToggleSelectAll,
    required this.onDeleteSelected,
    required this.deleteButtonFocusNode,
  });

  /// `_activeSelectedIds.length` on the host.
  final int selectedCount;

  /// `_isAllSelected` on the host: every item in the active view is selected
  /// and the view is not empty.
  final bool isAllSelected;

  final VoidCallback onToggleSelectAll;

  /// `_handleDeleteSelected`. Wired only while [selectedCount] is above zero,
  /// so the button renders disabled at zero.
  final VoidCallback onDeleteSelected;

  final FocusNode deleteButtonFocusNode;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final theme = Theme.of(context);
    final count = selectedCount;
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
            onPressed: onToggleSelectAll,
            child: Text(isAllSelected ? 'Deselect All' : 'Select All'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            focusNode: deleteButtonFocusNode,
            onPressed: count > 0 ? onDeleteSelected : null,
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
