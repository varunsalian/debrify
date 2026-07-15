import 'package:flutter/material.dart';

import 'window_drag_area.dart';

/// Stremio-style indigo accent + purple-tinted rail background.
const Color _kAccent = Color(0xFF7B5CFF);
const Color _kRailBg = Color(0xFF120F24);

/// One entry in the desktop sidebar. [section] groups consecutive entries; a
/// small divider is inserted whenever the section changes.
class DesktopNavEntry {
  final IconData icon;
  final String label;
  final String section;
  final String? tag;
  const DesktopNavEntry(this.icon, this.label, this.section, {this.tag});
}

/// Stremio-style icon rail for wide desktop windows. Each item is a rounded
/// cell showing its icon; the active item — and any item on hover — reveals its
/// label beneath the icon inside a highlighted rounded box (no floating
/// tooltip, no rail expansion). TV keeps its focus-driven rail and mobile keeps
/// the floating bar.
///
/// When [expanded] is true the rail is wider and every item's label is always
/// visible beneath its icon — used on touch tablets (iPad / Android tablet in
/// landscape) where there is no mouse hover to reveal the other labels.
class DesktopSidebarNav extends StatelessWidget {
  /// Index into [entries] of the active screen.
  final int currentIndex;
  final List<DesktopNavEntry> entries;

  /// Called with the index into [entries] that was clicked.
  final ValueChanged<int> onTap;

  /// Show every label permanently in a wider rail (touch tablets have no hover).
  final bool expanded;

  static const double width = 90.0;
  static const double expandedWidth = 128.0;

  const DesktopSidebarNav({
    super.key,
    required this.currentIndex,
    required this.entries,
    required this.onTap,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    String? lastSection;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (lastSection != null && e.section != lastSection) {
        children.add(const _GroupDivider());
      }
      lastSection = e.section;
      children.add(
        _SidebarItem(
          icon: e.icon,
          label: e.label,
          selected: i == currentIndex,
          alwaysShowLabel: expanded,
          onTap: () => onTap(i),
        ),
      );
    }

    return Container(
      width: expanded ? expandedWidth : width,
      decoration: const BoxDecoration(color: _kRailBg),
      foregroundDecoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo doubles as the window drag handle (no AppBar here).
          WindowDragArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.asset('assets/app_icon.png',
                      width: 32, height: 32),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 2, bottom: 16),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      child: Container(
        height: 1,
        color: Colors.white.withValues(alpha: 0.06),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;

  /// When true the label is shown regardless of hover/selection (touch tablets).
  final bool alwaysShowLabel;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.alwaysShowLabel,
    required this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = widget.selected;
    // The label shows for the active item and for any item on hover — or
    // always, on touch tablets where there is no hover to reveal it.
    final showLabel = selected || _hovered || widget.alwaysShowLabel;
    final Color fg = selected
        ? _kAccent
        : (_hovered ? cs.onSurface : Colors.white.withValues(alpha: 0.6));
    final Color bg = selected
        ? _kAccent.withValues(alpha: 0.16)
        : (_hovered ? Colors.white.withValues(alpha: 0.05) : Colors.transparent);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        // Guard against a trailing onExit after the rail unmounts (e.g. the
        // window shrinks below the desktop-layout threshold while hovered).
        onEnter: (_) {
          if (mounted) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _hovered = false);
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 24, color: fg),
                const SizedBox(height: 5),
                // Label height is always reserved (one line) so hovering never
                // reflows the rail; only its visibility toggles.
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 130),
                  style: TextStyle(
                    color: fg.withValues(alpha: showLabel ? 1 : 0),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                    letterSpacing: 0.1,
                  ),
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
