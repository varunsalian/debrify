import 'package:debrify/features/debrid_downloads/models/debrid_downloads_view.dart';
import 'package:debrify/features/debrid_downloads/models/folder_view_mode.dart';
import 'package:debrify/widgets/cloud/cloud_segmented_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'debrid_catalog_state.dart';
import 'debrid_focus_state.dart';

typedef DebridViewSelectorDeps = ({
  BuildContext Function() context,
  FolderViewMode Function() getCurrentViewMode,
  DebridFocusState focusState,
  void Function(FolderViewMode mode) setViewMode,
  DebridCatalogState catalogState,
  void Function() exitSelectionMode,
  void Function() resetListScroll,
  void Function(VoidCallback) setState,
});

class DebridViewSelector {
  DebridViewSelector(this._deps);
  final DebridViewSelectorDeps _deps;

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

  /// Full-width view switcher on its own line under the toolbar (two labels
  /// don't fit the toolbar slot the old single-label dropdown used).
  Widget buildViewSelectorBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: CloudSegmentedTabs<DebridDownloadsView>(
        segments: const [
          CloudSegment(
            DebridDownloadsView.torrents,
            'Torrent Downloads',
            Icons.folder_rounded,
          ),
          CloudSegment(
            DebridDownloadsView.ddl,
            'DDL Downloads',
            Icons.download_rounded,
          ),
        ],
        selected: _deps.catalogState.selectedView,
        onSelected: (value) {
          if (value == _deps.catalogState.selectedView) return;
          _deps.exitSelectionMode();
          // The two root lists swap in the same element slot, so the incoming
          // one would inherit the outgoing list's scroll offset.
          _deps.resetListScroll();
          _deps.setState(() => _deps.catalogState.selectedView = value);
        },
      ),
    );
  }
}
