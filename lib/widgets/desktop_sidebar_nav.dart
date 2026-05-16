import 'package:flutter/material.dart';

import 'home/home_theme.dart';
import 'window_drag_area.dart';

/// One entry in the desktop sidebar. [section] is the group header it lives
/// under (e.g. "Main"); consecutive entries sharing a section are grouped.
class DesktopNavEntry {
  final IconData icon;
  final String label;
  final String section;
  final String? tag;
  const DesktopNavEntry(this.icon, this.label, this.section, {this.tag});
}

/// Always-visible left navigation rail for wide desktop windows — replaces
/// the top nav bar. Mouse-driven (hover + click); the TV build keeps its own
/// focus-driven [TvSidebarNav] and mobile keeps the floating bar. Entries are
/// rendered as grouped sections in the order given.
class DesktopSidebarNav extends StatelessWidget {
  /// Index into [entries] of the active screen.
  final int currentIndex;
  final List<DesktopNavEntry> entries;

  /// Called with the index into [entries] that was clicked.
  final ValueChanged<int> onTap;

  static const double width = 248.0;

  const DesktopSidebarNav({
    super.key,
    required this.currentIndex,
    required this.entries,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Build a flat child list, injecting a section header whenever the
    // section label changes from the previous entry.
    final children = <Widget>[];
    String? lastSection;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.section != lastSection) {
        children.add(_SectionLabel(e.section));
        lastSection = e.section;
      }
      children.add(
        _SidebarItem(
          icon: e.icon,
          label: e.label,
          selected: i == currentIndex,
          onTap: () => onTap(i),
        ),
      );
    }

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0C13),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo header doubles as the window drag handle (no AppBar here).
          WindowDragArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/app_icon.png',
                      width: 28,
                      height: 28,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Debrify',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.38),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
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
    final Color fg = selected
        ? HomeTheme.focusGold
        : (_hovered ? cs.onSurface : Colors.white.withValues(alpha: 0.72));

    final Color bg = selected
        ? HomeTheme.focusGold.withValues(alpha: 0.14)
        : (_hovered ? Colors.white.withValues(alpha: 0.06) : Colors.transparent);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 20, color: fg),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
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
