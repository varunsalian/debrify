import 'dart:async';
import 'package:debrify/features/alldebrid_files/models/alldebrid_view.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection_state.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/cloud/cloud_segmented_tabs.dart';
import 'package:flutter/material.dart';

typedef AllDebridToolbarDeps = ({
  AllDebridNavigationState navigationState,
  AllDebridLibraryState libraryState,
  AllDebridSelectionState selectionState,
  AllDebridSearchState searchState,
  AllDebridFocusState focusState,
  BuildContext Function() context,
  void Function(VoidCallback) setState,
  bool Function() isPushedRoute,
  bool Function() selectSourceMode,
  void Function() confirmDeleteAll,
  void Function() confirmDeleteAllLinks,
  void Function() exitSelectionMode,
  Future<void> Function() handleDeleteSelected,
  bool Function() isAllSelected,
  bool Function() isBrowsePush,
  Future<void> Function() loadLinks,
  Future<void> Function() refresh,
  Future<void> Function() showAddLinkDialog,
  Future<void> Function() showAddMagnetDialog,
  void Function() toggleSearch,
  void Function() toggleSelectAll,
  void Function() toggleSelectionMode,
});

class AllDebridToolbar {
  final AllDebridToolbarDeps _deps;
  AllDebridToolbar(this._deps);
  AllDebridNavigationState get _navigation => _deps.navigationState;
  AllDebridLibraryState get _library => _deps.libraryState;
  AllDebridSelectionState get _selection => _deps.selectionState;
  AllDebridSearchState get _search => _deps.searchState;
  AllDebridFocusState get _f => _deps.focusState;

  /// Pushed (from the Cloud hub or the openAllDebridFolder deep link) to browse
  /// — the root has no other Back affordance, so show one.
  bool get isBrowsePush => _deps.isPushedRoute();

  Widget buildToolbar() {
    final theme = Theme.of(_deps.context());
    final app = AppThemeScope.of(_deps.context());
    final isWeb = _navigation.selectedView == AllDebridView.webDownloads;
    final hasItems = isWeb
        ? _library.links.isNotEmpty
        : _library.magnets.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 480;
        final double iconSize = isCompact ? 20 : 24;
        final iconPadding = isCompact
            ? const EdgeInsets.all(6)
            : const EdgeInsets.all(8);
        final iconConstraints = isCompact
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
              if (_deps.selectSourceMode())
                const Text(
                  'Select AllDebrid Source',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              const Spacer(),
              // Selection mode is torrents-only (it bulk-deletes magnets).
              if (!_deps.selectSourceMode() && !isWeb && hasItems)
                Tooltip(
                  message: _selection.selectionMode
                      ? 'Exit selection'
                      : 'Select items',
                  child: IconButton(
                    onPressed: _deps.toggleSelectionMode,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: Icon(
                      _selection.selectionMode
                          ? Icons.close
                          : Icons.checklist_outlined,
                    ),
                    color: _selection.selectionMode
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (!_deps.selectSourceMode() && hasItems) ...[
                Tooltip(
                  message: isWeb ? 'Delete all links' : 'Delete all magnets',
                  child: IconButton(
                    onPressed: isWeb
                        ? _deps.confirmDeleteAllLinks
                        : _deps.confirmDeleteAll,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    color: theme.colorScheme.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Tooltip(
                  message: _search.searchActive
                      ? 'Close search'
                      : (isWeb ? 'Search links' : 'Search magnets'),
                  child: IconButton(
                    focusNode: _f.toolbarSearchFocusNode,
                    onPressed: _deps.toggleSearch,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: Icon(
                      _search.searchActive
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                    ),
                    color: _search.searchActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
              if (_deps.selectSourceMode() && hasItems)
                Tooltip(
                  message: _search.searchActive
                      ? 'Close search'
                      : (isWeb ? 'Search links' : 'Search magnets'),
                  child: IconButton(
                    focusNode: _f.toolbarSearchFocusNode,
                    onPressed: _deps.toggleSearch,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: Icon(
                      _search.searchActive
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                    ),
                    color: _search.searchActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (!_deps.selectSourceMode())
                Tooltip(
                  message: isWeb ? 'Add link' : 'Add magnet link',
                  child: IconButton(
                    onPressed: isWeb
                        ? _deps.showAddLinkDialog
                        : _deps.showAddMagnetDialog,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.add_circle_outline),
                    color: theme.colorScheme.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              Tooltip(
                message: 'Refresh',
                child: IconButton(
                  onPressed: _deps.refresh,
                  iconSize: iconSize,
                  padding: iconPadding,
                  constraints: iconConstraints,
                  icon: const Icon(Icons.refresh),
                  color: theme.colorScheme.onSurface,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Full-width view switcher on its own line under the toolbar (two labels
  /// don't fit the toolbar slot the old single-label dropdown used).
  Widget buildViewSelectorBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: CloudSegmentedTabs<AllDebridView>(
        segments: const [
          CloudSegment(
            AllDebridView.torrents,
            'Torrent Downloads',
            Icons.folder_rounded,
          ),
          CloudSegment(
            AllDebridView.webDownloads,
            'Web Downloads',
            Icons.link_rounded,
          ),
        ],
        selected: _navigation.selectedView,
        onSelected: (value) {
          if (value == _navigation.selectedView) return;
          _deps.exitSelectionMode();
          // Both root lists share _scrollController; reset so the incoming
          // view doesn't inherit the outgoing list's scroll offset.
          if (_f.scrollController.hasClients) _f.scrollController.jumpTo(0);
          _deps.setState(() {
            _navigation.selectedView = value;
            _search.searchActive = false;
            _search.searchQuery = '';
            _search.searchController.clear();
          });
          if (value == AllDebridView.webDownloads &&
              !_library.linksLoadedOnce) {
            _deps.loadLinks();
          }
        },
      ),
    );
  }

  Widget buildSelectionBar() {
    final theme = Theme.of(_deps.context());
    final count = _selection.selectedIds.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
            focusNode: _f.deleteButtonFocusNode,
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
