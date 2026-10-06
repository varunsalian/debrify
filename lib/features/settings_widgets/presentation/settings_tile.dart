import 'package:debrify/features/settings_widgets/presentation/settings_rows.dart';
import 'package:debrify/theme/app_focus.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:flutter/material.dart';

/// Flat settings row: mono icon · title + subtitle · chevron (or custom
/// trailing). Focus/hover lights the row with the accent ring so DPAD focus
/// is unmissable on TV.
class SettingsTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;
  final String? tag;
  final Widget? trailing;

  /// Renders the icon and title in the destructive red (Danger Zone).
  final bool destructive;

  /// False greys the whole row out and makes it inert: no tap, no hover
  /// light, and DPAD traversal skips it. The subtitle stays readable — a
  /// disabled row should say WHY it's disabled (e.g. "Only used by the
  /// Spotlight layout") rather than vanish.
  final bool enabled;

  /// Lets a parent (e.g. the TV two-pane rail) drive focus onto this row.
  final FocusNode? focusNode;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tag,
    this.trailing,
    this.destructive = false,
    this.enabled = true,
    this.focusNode,
  });

  /// Build from a shared [SettingsRowContent] so the TV and phone layouts
  /// stay in lockstep. [subtitle] overrides the content's (for dynamic rows
  /// like "Check for Updates").
  factory SettingsTile.spec(
    SettingsRowContent content, {
    Key? key,
    required Future<void> Function() onTap,
    String? subtitle,
    String? tag,
    Widget? trailing,
    bool destructive = false,
    bool enabled = true,
    FocusNode? focusNode,
  }) {
    return SettingsTile(
      key: key,
      icon: content.icon,
      title: content.title,
      subtitle: subtitle ?? content.subtitle,
      onTap: onTap,
      tag: tag,
      trailing: trailing,
      destructive: destructive,
      enabled: enabled,
      focusNode: focusNode,
    );
  }

  @override
  State<SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<SettingsTile> {
  /// Owned only when the caller did not supply one.
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  bool _hovered = false;

  /// Read LIVE from the node, never cached from `onFocusChange`.
  ///
  /// A cached bool is only as good as the callback that maintains it, and
  /// Flutter does not guarantee the falling edge: pop a route that was opened
  /// with OK and focus is restored to the MODAL SCOPE rather than to a row, so
  /// the rows that were focus-walked on the way in are never told they lost
  /// it. They keep their cached `true`, and under the Spotlight look that is
  /// not a faint stale highlight — every one of them paints a solid white
  /// plate, so the list comes back from a sub-page with two or three cursors
  /// on it and no way to tell which row OK will open.
  ///
  /// Derived state cannot go stale the way a remembered one does: the value is
  /// re-read on every build, so it is only ever as old as the last rebuild
  /// rather than as old as the last callback that arrived.
  ///
  /// Being precise about what that does and does not buy, because the
  /// difference matters if this is ever revisited: the repaint trigger is
  /// still the same `onFocusChange` the bug rides on, so a silently-missed
  /// notification leaves the WRONG PIXELS up until something rebuilds this
  /// row — it does not repaint it the instant focus leaves. What reliably
  /// rebuilds it is the row's own `onTap` being awaited below: callers
  /// setState when the pushed page returns, which rebuilds the list with
  /// fresh values. (A route transition alone would NOT do it — ModalScope
  /// caches the page subtree behind its AnimatedBuilder's `child`.)
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
    final bool lit = widget.enabled && (_focused || _hovered);
    final bool inverse =
        spotlight && lit && app.focus.expression == FocusExpression.parallax;
    final Color foreground = inverse ? app.inkOn(app.core.tx) : app.core.tx;
    final Color iconColor = widget.destructive
        ? (inverse ? Color.lerp(t.danger, foreground, 0.38)! : t.danger)
        : (inverse ? foreground : (lit ? t.accent2 : t.dim));
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
          // Also drops the row out of DPAD traversal — an unfocusable node
          // never enters the traversal ring, so no remote step is eaten.
          canRequestFocus: widget.enabled,
          onFocusChange: (_) => setState(() {}),
          onHover: (h) => setState(() => _hovered = h),
          onTap: widget.enabled
              ? () async {
                  await widget.onTap();
                }
              : null,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            // One veil for the whole anatomy (icon, tag chip, chevron) rather
            // than per-part disabled colors that would drift out of sync.
            child: Opacity(
              opacity: widget.enabled ? 1 : 0.45,
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
                      child: Icon(widget.icon, color: iconColor, size: 20),
                    )
                  else
                    SizedBox(
                      width: 34,
                      child: Icon(widget.icon, color: iconColor, size: 22),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: widget.destructive
                                      ? t.danger
                                      : spotlight
                                      ? foreground
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                            if (widget.tag != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: t.accent.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  widget.tag!,
                                  style: TextStyle(
                                    color: inverse
                                        ? Color.lerp(t.accent, foreground, 0.25)
                                        : t.accent2,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 9.5,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.subtitle,
                          maxLines: 1,
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
                  if (widget.trailing case final trailing?)
                    IconTheme.merge(
                      data: IconThemeData(
                        color: inverse
                            ? foreground.withValues(alpha: 0.42)
                            : t.dim2,
                      ),
                      child: trailing,
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: inverse
                          ? foreground.withValues(alpha: 0.42)
                          : t.dim2,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
