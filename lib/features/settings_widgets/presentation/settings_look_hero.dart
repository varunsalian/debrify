import 'package:debrify/theme/app_focus.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:flutter/material.dart';

/// Prominent active-Look row used at the top of Appearance.
///
/// A Look changes several downstream controls at once, so presenting it as
/// one more 52dp row understated its effect and made Appearance read as an
/// arbitrary list. The swatches are derived from the active theme itself.
class SettingsLookHero extends StatefulWidget {
  const SettingsLookHero({
    super.key,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.focusNode,
  });

  final String label;
  final String subtitle;
  final Future<void> Function() onTap;
  final FocusNode? focusNode;

  @override
  State<SettingsLookHero> createState() => _SettingsLookHeroState();
}

class _SettingsLookHeroState extends State<SettingsLookHero> {
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
    final lit = _focused || _hovered;
    final inverse = lit && app.focus.expression == FocusExpression.parallax;
    final foreground = inverse ? app.inkOn(app.core.tx) : app.core.tx;
    final radius = app.shape.br(13);
    return ParallaxFocus(
      focused: _focused,
      shape: ParallaxShape.settingsRow,
      radius: radius,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          focusNode: _node,
          onFocusChange: (_) => setState(() {}),
          onHover: (value) => setState(() => _hovered = value),
          onTap: () async => await widget.onTap(),
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: 116),
            padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 18),
            decoration: BoxDecoration(
              color: inverse
                  ? app.core.tx
                  : Color.alphaBlend(
                      t.accent.withValues(alpha: 0.1),
                      app.fade(app.core.tx, 0.04),
                    ),
              borderRadius: radius,
              border: Border.all(
                color: inverse ? app.core.tx : t.accent.withValues(alpha: 0.24),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showSwatches = constraints.maxWidth >= 390;
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ACTIVE LOOK',
                            style: TextStyle(
                              fontFamily: 'JetBrainsMono',
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.55,
                              color: inverse
                                  ? foreground.withValues(alpha: 0.6)
                                  : t.accent2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 20,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              color: foreground,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            widget.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.4,
                              color: inverse
                                  ? foreground.withValues(alpha: 0.5)
                                  : t.dim,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showSwatches) ...[
                      const SizedBox(width: 20),
                      _SettingsSwatches(inverse: inverse),
                    ],
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: inverse
                          ? foreground.withValues(alpha: 0.42)
                          : t.dim2,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSwatches extends StatelessWidget {
  const _SettingsSwatches({required this.inverse});

  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final colors = [
      app.core.ground,
      app.core.pane,
      app.settings.accent,
      app.core.tx,
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < colors.length; i++) ...[
          Container(
            width: 25,
            height: 42,
            decoration: BoxDecoration(
              color: colors[i],
              borderRadius: app.shape.br(7),
              border: Border.all(
                color: inverse
                    ? app.inkOn(app.core.tx).withValues(alpha: 0.12)
                    : app.settings.line,
              ),
            ),
          ),
          if (i != colors.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}
