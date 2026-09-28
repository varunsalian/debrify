import 'package:flutter/material.dart';

import '../../../theme/app_theme_scope.dart';

/// Keyword result actions. Selection state and focus-node lifetime belong to
/// the route; each accepted gesture dispatches the supplied action once.
class KeywordToolbar extends StatelessWidget {
  const KeywordToolbar({
    super.key,
    required this.selectionMode,
    required this.floatingSelect,
    required this.selectableCount,
    required this.selectedCount,
    required this.filterCount,
    required this.showProviderFilter,
    required this.providerFilterCount,
    required this.sortLabel,
    required this.focusNodes,
    required this.onKey,
    required this.onCancel,
    required this.onDeselectAll,
    required this.onSelectAll,
    required this.onAdd,
    required this.onSort,
    required this.onFilters,
    required this.onProviders,
    required this.onSources,
    required this.onSelect,
  });

  final bool selectionMode, floatingSelect, showProviderFilter;
  final int selectableCount, selectedCount, filterCount, providerFilterCount;
  final String sortLabel;
  final List<FocusNode> focusNodes;
  final KeyEventResult Function(int, int, VoidCallback, KeyEvent) onKey;
  final VoidCallback onCancel, onDeselectAll, onSelectAll, onAdd;
  final VoidCallback onSort, onFilters, onProviders, onSources, onSelect;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    // [navIndex]/[navTotal], when provided, make the pill keyboard/DPAD
    // focusable at that position in the toolbar (left/right between pills, up to
    // the search field, down into the results, select to activate).
    Widget pill(
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool active = false,
      bool compact = false,
      int? navIndex,
      int navTotal = 0,
    }) {
      Widget body(bool focused) => Container(
        padding: compact
            ? const EdgeInsets.all(10)
            : const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? scheme.primary.withValues(alpha: 0.16)
              : scheme.surfaceContainerHigh,
          borderRadius: app.shape.brPill,
          // Always 2px so focus never shifts layout: white ring when
          // focused, else the active/idle border.
          border: Border.all(
            color: focused
                ? app.fade(app.core.tx, 0.9)
                : active
                ? scheme.primary.withValues(alpha: 0.5)
                : app.fade(app.core.tx, 0.10),
            width: 2,
          ),
        ),
        child: compact
            ? Icon(
                icon,
                size: 18,
                color: active ? scheme.primary : scheme.onSurfaceVariant,
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
      );

      final Widget tappable = navIndex == null
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: app.shape.brPill,
                child: body(false),
              ),
            )
          : Focus(
              focusNode: focusNodes[navIndex],
              onKeyEvent: (n, event) => onKey(navIndex, navTotal, onTap, event),
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: app.shape.brPill,
                      canRequestFocus: false,
                      child: body(focused),
                    ),
                  );
                },
              ),
            );

      return Padding(padding: const EdgeInsets.only(right: 8), child: tappable);
    }

    if (selectionMode && !floatingSelect) {
      final selectable = selectableCount;
      final count = selectedCount;
      final allSelected = count > 0 && count == selectable;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(
          children: [
            pill(
              Icons.close_rounded,
              'Cancel',
              onCancel,
              navIndex: 0,
              navTotal: 3,
            ),
            pill(
              allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
              allSelected ? 'None' : 'All',
              allSelected ? onDeselectAll : onSelectAll,
              navIndex: 1,
              navTotal: 3,
            ),
            pill(
              Icons.playlist_add_rounded,
              count > 0 ? 'Add · $count' : 'Add',
              count > 0 ? onAdd : () {},
              active: count > 0,
              navIndex: 2,
              navTotal: 3,
            ),
          ],
        ),
      );
    }

    final canSelect = selectableCount > 0;
    final showSelect = canSelect && !floatingSelect;
    final showProviders = showProviderFilter;
    final providerActive = providerFilterCount;
    // Build the pill set dynamically so navIndex stays contiguous when the
    // optional Providers / Select pills come and go. Base pills always present:
    // Sort, Filters, Sources (3); Providers and Select are optional.
    final total = 3 + (showProviders ? 1 : 0) + (showSelect ? 1 : 0);
    var idx = 0;
    final pills = <Widget>[
      pill(
        Icons.sort_rounded,
        'Sort · $sortLabel',
        onSort,
        compact: floatingSelect,
        navIndex: idx++,
        navTotal: total,
      ),
      pill(
        Icons.filter_list_rounded,
        filterCount > 0 ? 'Filters · $filterCount' : 'Filters',
        onFilters,
        active: filterCount > 0,
        compact: floatingSelect,
        navIndex: idx++,
        navTotal: total,
      ),
      if (showProviders)
        pill(
          Icons.hub_rounded,
          providerActive > 0 ? 'Providers · $providerActive' : 'Providers',
          onProviders,
          active: providerActive > 0,
          compact: floatingSelect,
          navIndex: idx++,
          navTotal: total,
        ),
      pill(
        Icons.dns_rounded,
        'Sources',
        onSources,
        compact: floatingSelect,
        navIndex: idx++,
        navTotal: total,
      ),
      if (showSelect)
        pill(
          Icons.checklist_rounded,
          'Select',
          onSelect,
          navIndex: idx++,
          navTotal: total,
        ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(children: pills),
    );
  }
}
