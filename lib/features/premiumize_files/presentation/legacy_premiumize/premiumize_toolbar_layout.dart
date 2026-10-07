import 'dart:async';

import 'package:debrify/features/premiumize_files/models/folder_view_mode.dart';
import 'package:debrify/features/premiumize_files/models/premiumize_view.dart';
import 'package:debrify/widgets/cloud/cloud_segmented_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'premiumize_focus_state.dart';
import 'premiumize_selection_state.dart';
import 'premiumize_view_state.dart';

typedef PremiumizeToolbarLayoutDeps = ({
  PremiumizeViewState viewState,
  void Function(PremiumizeView view) switchView,
  BuildContext Function() context,
  PremiumizeFolderViewMode Function() getCurrentViewMode,
  PremiumizeFocusState focusState,
  void Function(PremiumizeFolderViewMode mode) setViewMode,
  PremiumizeSelectionState selectionState,
  void Function() toggleSelectAll,
  bool Function() isAllSelected,
  Future<void> Function() handleDeleteSelected,
});

class PremiumizeToolbarLayout {
  PremiumizeToolbarLayout(this._deps);
  final PremiumizeToolbarLayoutDeps _deps;

  Widget buildViewSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: CloudSegmentedTabs<PremiumizeView>(
        segments: const [
          CloudSegment(PremiumizeView.files, 'My Files', Icons.folder_rounded),
          CloudSegment(
            PremiumizeView.transfers,
            'Transfers',
            Icons.swap_vert_rounded,
          ),
        ],
        selected: _deps.viewState.selectedView,
        onSelected: _deps.switchView,
      ),
    );
  }

  Widget buildViewModeDropdown() {
    final theme = Theme.of(_deps.context());
    final mode = _deps.getCurrentViewMode();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
      ),
      child: Focus(
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _deps.focusState.backButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: DropdownButtonFormField<PremiumizeFolderViewMode>(
          focusNode: _deps.focusState.viewModeDropdownFocusNode,
          isExpanded: true,
          value: mode,
          decoration: InputDecoration(
            labelText: 'View Mode',
            prefixIcon: Icon(
              mode == PremiumizeFolderViewMode.raw
                  ? Icons.view_list
                  : Icons.sort_by_alpha,
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
            DropdownMenuItem(
              value: PremiumizeFolderViewMode.raw,
              child: Text('Raw'),
            ),
            DropdownMenuItem(
              value: PremiumizeFolderViewMode.sortedAZ,
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
    final theme = Theme.of(_deps.context());
    final count = _deps.selectionState.selectedIds.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
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
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              disabledBackgroundColor: theme.colorScheme.error.withValues(
                alpha: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
