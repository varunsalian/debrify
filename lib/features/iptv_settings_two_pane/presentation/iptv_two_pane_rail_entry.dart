import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ------------------------------------------------------------------ pieces

class IptvTwoPaneRailHeading extends StatelessWidget {
  const IptvTwoPaneRailHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: t.dim2,
        ),
      ),
    );
  }
}

/// One rail entry. Focus selects it (the pane updates live), OK/RIGHT enters
/// the pane. Snap styling, never a tween — the TV GPU rule.
class IptvTwoPaneRailEntry extends StatefulWidget {
  const IptvTwoPaneRailEntry({
    required this.focusNode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onFocused,
    required this.onSelect,
    required this.onUp,
    required this.onDown,
    required this.onRight,
    this.trailing,
    this.chevron = false,
    this.busy = false,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onFocused;
  final VoidCallback onSelect;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onRight;
  final Widget? trailing;
  final bool chevron;
  final bool busy;

  @override
  State<IptvTwoPaneRailEntry> createState() => IptvTwoPaneRailEntryState();
}

class IptvTwoPaneRailEntryState extends State<IptvTwoPaneRailEntry> {
  /// Live, never cached — a remembered flag survives the focus change it
  /// missed. See the note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  bool get _focused => widget.focusNode.hasFocus;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final active = _focused || widget.selected;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (has) {
        if (!mounted) return;
        setState(() {});
        if (has) {
          widget.onFocused();
          // Keep the entry on screen when DPAD walks past the fold.
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: Duration.zero,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowUp:
            // Deliberately NOT consumed at the top of the rail: UP has to
            // escape upward to the page's back button, the way every other
            // settings page behaves.
            if (widget.onUp == null) return KeyEventResult.ignored;
            widget.onUp!();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowDown:
            // Consumed at the bottom, unlike UP: there is nothing below the
            // rail, and leaving it to geometric traversal would fling focus
            // sideways into the pane instead of simply stopping.
            if (widget.onDown == null) return KeyEventResult.handled;
            widget.onDown!();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowRight:
            widget.onRight();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.select:
          case LogicalKeyboardKey.space:
            widget.onSelect();
            return KeyEventResult.handled;
        }
        // LEFT is deliberately unhandled: the page's own back/sidebar
        // handling owns it, exactly as the main settings rail does.
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        // The whole row is the target, not just the glyphs it happens to
        // paint. Without this the padding is dead space — tolerable while
        // hover also selected, unacceptable now that clicking is the only
        // pointer affordance.
        behavior: HitTestBehavior.opaque,
        // Pointer: select only. Deliberately NOT onSelect() — that enters the
        // pane, which is the remote's OK behaviour; with a mouse it would
        // yank the focus ring into the pane on every click in the rail.
        onTap: widget.focusNode.requestFocus,
        child: MouseRegion(
          // Hover deliberately does nothing. Focus previews the pane, and on
          // TV focus IS the cursor — but with a mouse, merely crossing the
          // rail on the way somewhere else would swap the pane out from under
          // whatever the user was reading.
          cursor: SystemMouseCursors.click,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: _focused ? t.panel2 : (widget.selected ? t.panel : null),
              borderRadius: app.shape.br(11),
              border: Border.all(
                color: _focused ? t.accent : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _focused ? t.accent : t.panel2,
                    borderRadius: app.shape.br(9),
                  ),
                  child: widget.busy
                      ? const Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          widget.icon,
                          size: 18,
                          // Focused rides an accent fill; unfocused sits on a
                          // panel, where the accent tint is the right ink.
                          color: _focused ? app.inkOn(t.accent) : t.accent2,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: active ? app.core.tx : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: t.dim),
                      ),
                    ],
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
                if (widget.chevron)
                  Icon(Icons.chevron_right_rounded, size: 18, color: t.dim2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
