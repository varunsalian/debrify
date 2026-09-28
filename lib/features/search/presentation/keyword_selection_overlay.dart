import 'package:flutter/material.dart';

import '../../../theme/app_theme_scope.dart';

/// Small-screen entry and active selection controls; placed directly in a Stack.
class KeywordSelectionOverlay extends StatelessWidget {
  const KeywordSelectionOverlay({
    super.key,
    required this.selectionMode,
    required this.selectableCount,
    required this.selectedCount,
    required this.floatingNavigation,
    required this.onSelect,
    required this.onCancel,
    required this.onDeselectAll,
    required this.onSelectAll,
    required this.onAdd,
  });

  final bool selectionMode, floatingNavigation;
  final int selectableCount, selectedCount;
  final VoidCallback onSelect, onCancel, onDeselectAll, onSelectAll, onAdd;

  @override
  Widget build(BuildContext context) =>
      selectionMode ? _buildSelection(context) : _buildEntry(context);

  /// Floating checklist FAB (bottom-left) that enters multi-select on small
  /// screens — ported from Home's torrent-search layout.
  Widget _buildEntry(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Positioned(
      left: 16,
      bottom: 16,
      child: GestureDetector(
        onTap: onSelect,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: app.home.controlBg,
            shape: BoxShape.circle,
            border: Border.all(color: app.fade(app.core.tx, 0.15)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(Icons.checklist_rounded, color: app.core.tx, size: 20),
        ),
      ),
    );
  }

  /// Floating multi-select bar (bottom) — Home-style. Right-inset so it clears
  /// the mobile floating "Menu" nav.
  Widget _buildSelection(BuildContext context) {
    final app = AppThemeScope.of(context);
    final selectable = selectableCount;
    final count = selectedCount;
    final allSelected = count > 0 && count == selectable;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    Widget chip(Widget child, VoidCallback? onTap, Color bg) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: app.shape.br(8)),
        child: child,
      ),
    );

    return Positioned(
      left: 12,
      // Clear the bottom-right "Menu" FAB — which only the floating nav
      // style has; the classic bar occupies its own strip below the page.
      right: floatingNavigation ? 108 : 12,
      bottom: 12 + bottomPad,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: app.shape.br(16),
          border: Border.all(color: app.fade(app.home.chromeAccent, 0.45)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            chip(
              Icon(
                Icons.close_rounded,
                color: app.core.tx.withValues(alpha: 0xB3 / 0xFF),
                size: 18,
              ),
              onCancel,
              app.fade(app.core.tx, 0.1),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '$count selected',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: count > 0
                      ? app.home.chromeAccent
                      : app.core.tx.withValues(alpha: 0x8A / 0xFF),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            chip(
              Text(
                allSelected ? 'None' : 'All',
                style: TextStyle(
                  color: app.core.tx.withValues(alpha: 0xB3 / 0xFF),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              allSelected ? onDeselectAll : onSelectAll,
              app.fade(app.core.tx, 0.08),
            ),
            const SizedBox(width: 8),
            chip(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.playlist_add_rounded,
                    // Enabled, this chip is filled with the OPAQUE accent, so
                    // its ink is scored against it (white disappears on Noir's
                    // and Frost's #FFFFFF accent). Disabled, the fill is a 0.3
                    // wash over the dark bar, where white38 still reads.
                    color: count > 0
                        ? app.inkOn(app.home.chromeAccent)
                        : Colors.white38,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Add',
                    style: TextStyle(
                      color: count > 0
                          ? app.inkOn(app.home.chromeAccent)
                          : Colors.white38,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              count > 0 ? onAdd : null,
              count > 0
                  ? app.home.chromeAccent
                  : app.fade(app.home.chromeAccent, 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
