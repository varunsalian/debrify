import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../utils/tv_keys.dart';

/// Season, sort and filter controls with view-owned focus and action callbacks.
class SourceToolbarControls extends StatelessWidget {
  const SourceToolbarControls({
    super.key,
    required this.showSeason,
    required this.selectedSeason,
    required this.seasonMenuNumbers,
    required this.sortBy,
    required this.sortAsc,
    required this.filtersActive,
    required this.filterFocus,
    required this.onSelectSeason,
    required this.onSelectSort,
    required this.onToggleDirection,
    required this.onOpenFilters,
    required this.onFilterDown,
  });

  final bool showSeason;
  final int? selectedSeason;
  final ValueGetter<List<int>> seasonMenuNumbers;
  final String sortBy;
  final bool sortAsc;
  final bool filtersActive;

  /// Borrowed; its existing view listener drives focus-style rebuilds.
  final FocusNode filterFocus;
  final ValueChanged<int?> onSelectSeason;
  final ValueChanged<String> onSelectSort;
  final VoidCallback onToggleDirection;
  final VoidCallback onOpenFilters;
  final VoidCallback onFilterDown;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final accent = app.home.chromeAccent;
    final line = app.fade(app.core.tx, 0.08);
    final dim = app.fade(app.core.tx, 0.55);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Row(
        children: [
          // Season scope (pack-search mode): narrows the search to one
          // season's packs, like the old Home's season dropdown.
          if (showSeason)
            PopupMenuButton<int>(
              initialValue: selectedSeason ?? 0,
              tooltip: 'Season',
              color: const Color(0xFF1E1B2C),
              onSelected: (v) {
                onSelectSeason(v == 0 ? null : v);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 0, child: Text('All Seasons')),
                for (final s in seasonMenuNumbers())
                  PopupMenuItem(value: s, child: Text('Season $s')),
              ],
              child: _chip(
                context,
                selectedSeason != null ? accent : line,
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Season  ',
                        style: TextStyle(color: dim),
                      ),
                      TextSpan(
                        text: selectedSeason == null
                            ? 'All'
                            : '$selectedSeason',
                        style: const TextStyle(color: Color(0xFFF1F1F6)),
                      ),
                    ],
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const Spacer(),
          PopupMenuButton<String>(
            initialValue: sortBy,
            tooltip: 'Sort',
            color: const Color(0xFF1E1B2C),
            onSelected: onSelectSort,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'source', child: Text('Addon order')),
              PopupMenuItem(value: 'name', child: Text('Name')),
              PopupMenuItem(value: 'size', child: Text('Size')),
              PopupMenuItem(value: 'seeders', child: Text('Seeders')),
              PopupMenuItem(value: 'date', child: Text('Date')),
            ],
            child: _chip(
              context,
              line,
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Sort  ',
                      style: TextStyle(color: dim),
                    ),
                    TextSpan(
                      text: _sortLabel(sortBy),
                      style: const TextStyle(color: Color(0xFFF1F1F6)),
                    ),
                  ],
                ),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (sortBy != 'source')
            InkWell(
              borderRadius: app.shape.br(9),
              onTap: onToggleDirection,
              child: _chip(
                context,
                line,
                Icon(
                  sortAsc
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 16,
                  color: dim,
                ),
              ),
            ),
          const SizedBox(width: 6),
          Focus(
            focusNode: filterFocus,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (isActivateKey(event.logicalKey)) {
                onOpenFilters();
                return KeyEventResult.handled;
              }
              // DOWN returns to pending arrivals first, then the list;
              // the funnel is the toolbar anchor.
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                onFilterDown();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (_) {
                final focused = filterFocus.hasFocus;
                final tint = (filtersActive || focused) ? accent : dim;
                return InkWell(
                  borderRadius: app.shape.br(9),
                  // The outer Focus is the sole focus target; don't let the
                  // InkWell add a competing node that breaks D-pad traversal.
                  canRequestFocus: false,
                  onTap: onOpenFilters,
                  child: _chip(
                    context,
                    focused || filtersActive ? accent : line,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.filter_list_rounded, size: 16, color: tint),
                        const SizedBox(width: 5),
                        Text(
                          'Filter',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: tint,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, Color border, Widget child) {
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: app.fade(app.core.tx, 0.05),
        border: Border.all(color: border),
        borderRadius: app.shape.br(9),
      ),
      child: child,
    );
  }

  static String _sortLabel(String v) => switch (v) {
    'name' => 'Name',
    'size' => 'Size',
    'seeders' => 'Seeders',
    'date' => 'Date',
    _ => 'Addon order',
  };
}
