import 'package:flutter/material.dart';

import '../../theme/app_focus.dart';
import '../../theme/app_theme_scope.dart';
import '../../theme/widgets/parallax_focus.dart';
import 'widgets/settings_widgets.dart';

/// Responsive classes for the Settings root.
///
/// Compact surfaces show a category dashboard and an in-place detail view.
/// Medium and expanded surfaces keep the category rail visible beside the
/// selected pane. The 720dp split is deliberately content-driven: below it a
/// useful rail leaves too little room for a settings row and its trailing
/// value, even on a nominally "tablet" device in portrait.
enum SettingsSurfaceClass { compact, medium, expanded }

@visibleForTesting
SettingsSurfaceClass settingsSurfaceClassForWidth(double width) {
  if (width < 720) return SettingsSurfaceClass.compact;
  if (width < 1080) return SettingsSurfaceClass.medium;
  return SettingsSurfaceClass.expanded;
}

@immutable
class SettingsCategoryDefinition {
  const SettingsCategoryDefinition({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.eyebrow,
    required this.title,
    required this.description,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final String eyebrow;
  final String title;
  final String description;
  final bool destructive;
}

typedef SettingsCategoryBuilder =
    Widget Function(BuildContext context, int categoryIndex);

/// The non-television Settings shell.
///
/// It owns presentation state only. Every setting action and every dynamic
/// value remains in [SettingsScreen]; [categoryBuilder] supplies those real
/// controls for the selected category. This keeps the redesign from creating
/// a second settings behavior layer merely to get a responsive layout.
class SettingsSpotlightShell extends StatefulWidget {
  const SettingsSpotlightShell({
    super.key,
    required this.categories,
    required this.categoryBuilder,
    required this.onOpenSearch,
    this.compactSummary,
    this.initialCategory = 0,
  }) : assert(categories.length > 0);

  final List<SettingsCategoryDefinition> categories;
  final SettingsCategoryBuilder categoryBuilder;
  final VoidCallback onOpenSearch;
  final Widget? compactSummary;
  final int initialCategory;

  @override
  State<SettingsSpotlightShell> createState() => _SettingsSpotlightShellState();
}

class _SettingsSpotlightShellState extends State<SettingsSpotlightShell> {
  late int _selected = widget.initialCategory.clamp(
    0,
    widget.categories.length - 1,
  );
  bool _compactDetailOpen = false;

  @override
  void didUpdateWidget(SettingsSpotlightShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selected >= widget.categories.length) {
      _selected = widget.categories.length - 1;
      _compactDetailOpen = false;
    }
  }

  void _select(int index, {required bool openCompact}) {
    if (_selected == index && _compactDetailOpen == openCompact) return;
    setState(() {
      _selected = index;
      _compactDetailOpen = openCompact;
    });
  }

  void _closeCompactDetail() {
    if (!_compactDetailOpen) return;
    setState(() => _compactDetailOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsBackground(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final surface = settingsSurfaceClassForWidth(constraints.maxWidth);
            if (surface == SettingsSurfaceClass.compact) {
              return PopScope<void>(
                canPop: !_compactDetailOpen,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) _closeCompactDetail();
                },
                child: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _compactDetailOpen
                      ? _buildCompactDetail()
                      : _buildCompactRoot(),
                ),
              );
            }
            return _buildWide(surface);
          },
        ),
      ),
    );
  }

  Widget _buildWide(SettingsSurfaceClass surface) {
    final app = AppThemeScope.of(context);
    final railWidth = surface == SettingsSurfaceClass.expanded ? 304.0 : 244.0;
    final railHorizontal = surface == SettingsSurfaceClass.expanded
        ? 24.0
        : 16.0;
    final category = widget.categories[_selected];
    return KeyedSubtree(
      key: const Key('settings-wide-shell'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: railWidth,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                railHorizontal,
                28,
                railHorizontal,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SettingsRootHeader(compact: true),
                  const SizedBox(height: 22),
                  SettingsSpotlightSearchButton(
                    onTap: widget.onOpenSearch,
                    compact: true,
                  ),
                  const SizedBox(height: 18),
                  for (var i = 0; i < widget.categories.length; i++) ...[
                    _SettingsRailItem(
                      key: ValueKey<String>('settings-rail-$i'),
                      definition: widget.categories[i],
                      selected: i == _selected,
                      onTap: () => _select(i, openCompact: false),
                    ),
                    if (i != widget.categories.length - 1)
                      const SizedBox(height: 3),
                  ],
                ],
              ),
            ),
          ),
          Container(width: 1, color: app.settings.line),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    surface == SettingsSurfaceClass.expanded ? 42 : 30,
                    35,
                    surface == SettingsSurfaceClass.expanded ? 44 : 30,
                    20,
                  ),
                  child: _SettingsCategoryHeading(definition: category),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    key: PageStorageKey<String>(
                      'settings-category-${category.label}',
                    ),
                    padding: EdgeInsets.fromLTRB(
                      surface == SettingsSurfaceClass.expanded ? 42 : 30,
                      2,
                      surface == SettingsSurfaceClass.expanded ? 44 : 30,
                      48,
                    ),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: KeyedSubtree(
                          key: ValueKey<int>(_selected),
                          child: widget.categoryBuilder(context, _selected),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactRoot() {
    final normal = <MapEntry<int, SettingsCategoryDefinition>>[];
    final destructive = <MapEntry<int, SettingsCategoryDefinition>>[];
    for (var i = 0; i < widget.categories.length; i++) {
      final entry = MapEntry(i, widget.categories[i]);
      (entry.value.destructive ? destructive : normal).add(entry);
    }
    return ListView(
      key: const Key('settings-compact-root'),
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 40),
      children: [
        const SettingsRootHeader(),
        const SizedBox(height: 20),
        SettingsSpotlightSearchButton(onTap: widget.onOpenSearch),
        if (widget.compactSummary != null) ...[
          const SizedBox(height: 18),
          widget.compactSummary!,
        ],
        const SizedBox(height: 26),
        const SettingsSectionLabel('Browse by category'),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 344;
            final width = twoColumns
                ? (constraints.maxWidth - 10) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final entry in normal)
                  SizedBox(
                    width: width,
                    child: _SettingsCategoryCard(
                      key: ValueKey<String>('settings-category-${entry.key}'),
                      definition: entry.value,
                      onTap: () => _select(entry.key, openCompact: true),
                    ),
                  ),
              ],
            );
          },
        ),
        if (destructive.isNotEmpty) ...[
          const SizedBox(height: 26),
          SettingsSectionLabel(
            'Danger zone',
            color: AppThemeScope.of(context).settings.danger,
          ),
          for (final entry in destructive)
            _SettingsCategoryCard(
              key: ValueKey<String>('settings-category-${entry.key}'),
              definition: entry.value,
              onTap: () => _select(entry.key, openCompact: true),
              compactHeight: true,
            ),
        ],
      ],
    );
  }

  Widget _buildCompactDetail() {
    final category = widget.categories[_selected];
    final app = AppThemeScope.of(context);
    return ListView(
      key: const Key('settings-compact-detail'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 42),
      children: [
        Row(
          children: [
            Semantics(
              button: true,
              label: 'Back to settings categories',
              child: Material(
                color: app.fade(app.core.tx, 0.08),
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _closeCompactDetail,
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 42,
                    height: 42,
                    child: Icon(Icons.arrow_back_rounded, size: 20),
                  ),
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Search settings',
              onPressed: widget.onOpenSearch,
              icon: const Icon(Icons.search_rounded),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _SettingsCategoryHeading(definition: category, compact: true),
        const SizedBox(height: 22),
        widget.categoryBuilder(context, _selected),
      ],
    );
  }
}

class SettingsRootHeader extends StatelessWidget {
  const SettingsRootHeader({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'YOUR SPACE',
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: compact ? 8.5 : 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.1,
            color: t.accent.withValues(alpha: 0.88),
          ),
        ),
        SizedBox(height: compact ? 9 : 11),
        Text(
          'Settings',
          style: TextStyle(
            fontSize: compact ? 25 : 30,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: compact ? -0.6 : -0.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Services, screens and playback—tuned in one place.',
          style: TextStyle(
            fontSize: compact ? 10.5 : 12,
            height: 1.45,
            color: t.dim,
          ),
        ),
      ],
    );
  }
}

class _SettingsCategoryHeading extends StatelessWidget {
  const _SettingsCategoryHeading({
    required this.definition,
    this.compact = false,
  });

  final SettingsCategoryDefinition definition;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          definition.eyebrow.toUpperCase(),
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: definition.destructive
                ? t.danger
                : t.accent.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          definition.title,
          style: TextStyle(
            fontSize: compact ? 25 : 29,
            height: 1.06,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.75,
          ),
        ),
        const SizedBox(height: 9),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660),
          child: Text(
            definition.description,
            style: TextStyle(
              fontSize: compact ? 11.5 : 12.5,
              height: 1.48,
              color: t.dim,
            ),
          ),
        ),
      ],
    );
  }
}

class SettingsSpotlightSearchButton extends StatefulWidget {
  const SettingsSpotlightSearchButton({
    super.key,
    required this.onTap,
    this.compact = false,
  });

  final VoidCallback onTap;
  final bool compact;

  @override
  State<SettingsSpotlightSearchButton> createState() =>
      _SettingsSpotlightSearchButtonState();
}

class _SettingsSpotlightSearchButtonState
    extends State<SettingsSpotlightSearchButton> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final lit = _focused || _hovered;
    final inverse = lit && app.focus.expression == FocusExpression.parallax;
    final foreground = inverse ? app.inkOn(app.core.tx) : t.dim;
    final radius = app.shape.br(24);
    return ParallaxFocus(
      focused: _focused,
      shape: ParallaxShape.settingsRow,
      radius: radius,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (value) => setState(() => _focused = value),
          onHover: (value) => setState(() => _hovered = value),
          borderRadius: radius,
          child: Container(
            height: widget.compact ? 43 : 48,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            decoration: BoxDecoration(
              color: inverse
                  ? app.core.tx
                  : (lit ? t.panel2 : app.fade(app.core.tx, 0.07)),
              borderRadius: radius,
              border: Border.all(color: inverse ? app.core.tx : t.line),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 18, color: foreground),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'Search settings',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: widget.compact ? 11.5 : 12.5,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
                if (!widget.compact)
                  Text(
                    'FIND ANYTHING',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 7.5,
                      letterSpacing: 0.8,
                      color: foreground.withValues(alpha: 0.55),
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

class _SettingsRailItem extends StatefulWidget {
  const _SettingsRailItem({
    super.key,
    required this.definition,
    required this.selected,
    required this.onTap,
  });

  final SettingsCategoryDefinition definition;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SettingsRailItem> createState() => _SettingsRailItemState();
}

class _SettingsRailItemState extends State<_SettingsRailItem> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final lit = _focused || _hovered;
    final inverse = lit && app.focus.expression == FocusExpression.parallax;
    final foreground = inverse
        ? app.inkOn(app.core.tx)
        : widget.definition.destructive
        ? t.danger
        : (widget.selected ? app.core.tx : t.dim);
    final radius = app.shape.br(11);
    return ParallaxFocus(
      focused: _focused,
      shape: ParallaxShape.settingsRow,
      radius: radius,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (value) => setState(() => _focused = value),
          onHover: (value) => setState(() => _hovered = value),
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: inverse
                  ? app.core.tx
                  : widget.selected
                  ? app.fade(app.core.tx, 0.1)
                  : (lit ? t.panel2 : Colors.transparent),
              borderRadius: radius,
            ),
            child: Row(
              children: [
                Container(
                  width: 31,
                  height: 31,
                  decoration: BoxDecoration(
                    color: inverse
                        ? foreground.withValues(alpha: 0.08)
                        : widget.selected
                        ? t.accent.withValues(alpha: 0.16)
                        : app.fade(app.core.tx, 0.055),
                    borderRadius: app.shape.br(9),
                  ),
                  child: Icon(
                    widget.definition.icon,
                    size: 17,
                    color: inverse
                        ? foreground
                        : widget.definition.destructive
                        ? t.danger
                        : widget.selected
                        ? t.accent2
                        : t.dim,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.definition.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.definition.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 8.5,
                          color: foreground.withValues(alpha: 0.52),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.selected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: inverse ? foreground : t.accent,
                      boxShadow: inverse
                          ? null
                          : [
                              BoxShadow(
                                color: t.accent.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ],
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

class _SettingsCategoryCard extends StatefulWidget {
  const _SettingsCategoryCard({
    super.key,
    required this.definition,
    required this.onTap,
    this.compactHeight = false,
  });

  final SettingsCategoryDefinition definition;
  final VoidCallback onTap;
  final bool compactHeight;

  @override
  State<_SettingsCategoryCard> createState() => _SettingsCategoryCardState();
}

class _SettingsCategoryCardState extends State<_SettingsCategoryCard> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final lit = _focused || _hovered;
    final inverse = lit && app.focus.expression == FocusExpression.parallax;
    final foreground = inverse
        ? app.inkOn(app.core.tx)
        : widget.definition.destructive
        ? t.danger
        : app.core.tx;
    final radius = app.shape.br(15);
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 3.0);
    final cardHeight = widget.compactHeight
        ? 74 + ((textScale - 1) * 34)
        : 112 + ((textScale - 1) * 40);
    return ParallaxFocus(
      focused: _focused,
      shape: ParallaxShape.settingsRow,
      radius: radius,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (value) => setState(() => _focused = value),
          onHover: (value) => setState(() => _hovered = value),
          borderRadius: radius,
          child: Container(
            height: cardHeight,
            padding: EdgeInsets.all(widget.compactHeight ? 13 : 14),
            decoration: BoxDecoration(
              color: inverse
                  ? app.core.tx
                  : (lit ? t.panel2 : app.fade(app.core.tx, 0.047)),
              borderRadius: radius,
              border: Border.all(
                color: inverse
                    ? app.core.tx
                    : widget.definition.destructive
                    ? t.danger.withValues(alpha: 0.28)
                    : t.line,
              ),
            ),
            child: widget.compactHeight
                ? Row(
                    children: [
                      _CategoryIcon(
                        definition: widget.definition,
                        foreground: foreground,
                        inverse: inverse,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _copy(foreground)),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: foreground.withValues(alpha: 0.42),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CategoryIcon(
                        definition: widget.definition,
                        foreground: foreground,
                        inverse: inverse,
                      ),
                      const Spacer(),
                      _copy(foreground),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _copy(Color foreground) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        widget.definition.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        widget.definition.subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground.withValues(alpha: 0.48),
          fontSize: 9,
          height: 1.3,
        ),
      ),
    ],
  );
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({
    required this.definition,
    required this.foreground,
    required this.inverse,
  });

  final SettingsCategoryDefinition definition;
  final Color foreground;
  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: inverse
            ? foreground.withValues(alpha: 0.08)
            : definition.destructive
            ? t.danger.withValues(alpha: 0.12)
            : app.fade(app.core.tx, 0.07),
        borderRadius: app.shape.br(10),
      ),
      child: Icon(
        definition.icon,
        size: 17,
        color: inverse
            ? foreground
            : definition.destructive
            ? t.danger
            : t.accent2,
      ),
    );
  }
}

enum SettingsSummaryTone { good, attention }

/// Health/status callout used above the compact category dashboard.
class SettingsSpotlightSummaryCard extends StatefulWidget {
  const SettingsSpotlightSummaryCard({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
    required this.tone,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;
  final SettingsSummaryTone tone;

  @override
  State<SettingsSpotlightSummaryCard> createState() =>
      _SettingsSpotlightSummaryCardState();
}

class _SettingsSpotlightSummaryCardState
    extends State<SettingsSpotlightSummaryCard> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final color = widget.tone == SettingsSummaryTone.good
        ? t.success
        : t.warning;
    final lit = _focused || _hovered;
    final inverse = lit && app.focus.expression == FocusExpression.parallax;
    final foreground = inverse ? app.inkOn(app.core.tx) : app.core.tx;
    final radius = app.shape.br(17);
    return ParallaxFocus(
      focused: _focused,
      shape: ParallaxShape.settingsRow,
      radius: radius,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (value) => setState(() => _focused = value),
          onHover: (value) => setState(() => _hovered = value),
          borderRadius: radius,
          child: Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: inverse
                  ? app.core.tx
                  : Color.alphaBlend(
                      color.withValues(alpha: 0.1),
                      app.fade(app.core.tx, 0.045),
                    ),
              borderRadius: radius,
              border: Border.all(
                color: inverse ? app.core.tx : color.withValues(alpha: 0.24),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: inverse
                            ? Color.lerp(color, foreground, 0.35)
                            : color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.eyebrow.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.25,
                          color: inverse
                              ? foreground.withValues(alpha: 0.7)
                              : color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.subtitle,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.45,
                    color: foreground.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: inverse
                        ? foreground.withValues(alpha: 0.08)
                        : app.core.tx,
                    borderRadius: app.shape.br(18),
                  ),
                  child: Text(
                    widget.actionLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: inverse ? foreground : app.inkOn(app.core.tx),
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
