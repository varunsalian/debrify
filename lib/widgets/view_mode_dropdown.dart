import 'package:flutter/material.dart';

/// View modes for folder/content browsing
enum FolderViewMode {
  raw,
  sortedAZ,
  seriesArrange,
}

/// Reusable dropdown for selecting folder view modes
/// Used in RD/Torbox/PikPak download screens and playlist content viewer
class ViewModeDropdown extends StatelessWidget {
  final FolderViewMode currentMode;
  final ValueChanged<FolderViewMode> onModeChanged;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool showSeriesView;

  const ViewModeDropdown({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
    this.focusNode,
    this.autofocus = true,
    this.showSeriesView = true,
  });

  IconData _getIconForMode(FolderViewMode mode) {
    switch (mode) {
      case FolderViewMode.raw:
        return Icons.view_list;
      case FolderViewMode.sortedAZ:
        return Icons.sort_by_alpha;
      case FolderViewMode.seriesArrange:
        return Icons.video_library;
    }
  }

  String _getLabelForMode(FolderViewMode mode) {
    switch (mode) {
      case FolderViewMode.raw:
        return 'Raw';
      case FolderViewMode.sortedAZ:
        return 'Sort (A-Z)';
      case FolderViewMode.seriesArrange:
        return 'Series View';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
      child: DropdownButtonFormField<FolderViewMode>(
        focusNode: focusNode,
        autofocus: autofocus,
        isExpanded: true,
        value: currentMode,
        decoration: InputDecoration(
          labelText: 'View Mode',
          prefixIcon: Icon(
            _getIconForMode(currentMode),
            color: theme.colorScheme.primary,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        items: FolderViewMode.values
            .where((mode) => showSeriesView || mode != FolderViewMode.seriesArrange)
            .map((mode) {
          return DropdownMenuItem(
            value: mode,
            child: Text(_getLabelForMode(mode)),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) onModeChanged(value);
        },
      ),
    );
  }
}
