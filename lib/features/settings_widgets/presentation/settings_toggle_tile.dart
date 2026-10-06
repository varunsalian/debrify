import 'package:debrify/features/settings_widgets/presentation/settings_rows.dart';
import 'package:debrify/theme/app_focus.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:flutter/material.dart';

/// Flat toggle row — same anatomy as [SettingsTile] with a switch on the
/// right instead of a chevron.
class SettingsToggleTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final FocusNode? focusNode;
  final int subtitleMaxLines;

  const SettingsToggleTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.focusNode,
    this.subtitleMaxLines = 1,
  });

  factory SettingsToggleTile.spec(
    SettingsRowContent content, {
    Key? key,
    required bool value,
    required ValueChanged<bool> onChanged,
    FocusNode? focusNode,
    int subtitleMaxLines = 1,
  }) {
    return SettingsToggleTile(
      key: key,
      icon: content.icon,
      title: content.title,
      subtitle: content.subtitle,
      value: value,
      onChanged: onChanged,
      focusNode: focusNode,
      subtitleMaxLines: subtitleMaxLines,
    );
  }

  @override
  State<SettingsToggleTile> createState() => _SettingsToggleTileState();
}

class _SettingsToggleTileState extends State<SettingsToggleTile> {
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  bool _hovered = false;

  /// Live, never cached — see the note on `_SettingsTileState._focused`.
  bool get _focused => _node.hasFocus;

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final spotlight = app.id == 'spotlight';
    final bool lit = _focused || _hovered;
    final bool inverse =
        spotlight && lit && app.focus.expression == FocusExpression.parallax;
    final foreground = inverse ? app.inkOn(app.core.tx) : app.core.tx;
    final radius = app.shape.br(12);
    // Snap, don't tween — per-keypress decoration lerps add cost on TV.
    return ParallaxFocus(
      focused: _focused,
      shape: ParallaxShape.settingsRow,
      radius: radius,
      child: Container(
        decoration: BoxDecoration(
          color: inverse ? app.core.tx : (lit ? t.panel2 : Colors.transparent),
          borderRadius: radius,
          border: Border.all(
            color: inverse
                ? app.core.tx
                : (_focused ? t.accent : Colors.transparent),
            width: 1,
          ),
        ),
        child: InkWell(
          focusNode: _node,
          onFocusChange: (_) => setState(() {}),
          onHover: (h) => setState(() => _hovered = h),
          onTap: () => widget.onChanged(!widget.value),
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                if (spotlight)
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: inverse
                          ? foreground.withValues(alpha: 0.08)
                          : app.fade(app.core.tx, 0.055),
                      borderRadius: app.shape.br(10),
                    ),
                    child: Icon(
                      widget.icon,
                      color: inverse ? foreground : (lit ? t.accent2 : t.dim),
                      size: 20,
                    ),
                  )
                else
                  SizedBox(
                    width: 34,
                    child: Icon(
                      widget.icon,
                      color: lit ? t.accent2 : t.dim,
                      size: 22,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: spotlight
                              ? foreground
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle,
                        maxLines: widget.subtitleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: inverse
                              ? foreground.withValues(alpha: 0.5)
                              : t.dim,
                        ),
                      ),
                    ],
                  ),
                ),
                // The row's InkWell is the single DPAD stop; a focusable
                // Switch would make every toggle cost two presses on TV.
                ExcludeFocus(
                  child: Switch.adaptive(
                    value: widget.value,
                    onChanged: widget.onChanged,
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
