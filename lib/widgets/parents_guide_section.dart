import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/imdb_parents_guide_service.dart';
import '../services/storage_service.dart';
import '../utils/tv_keys.dart';
import 'detail/theme/detail_theme.dart';
import 'home/home_theme.dart';

class ParentsGuideSection extends StatefulWidget {
  final ParentsGuideResult guide;
  final bool tv;
  final bool dense;
  final bool interactive;
  final Color? accent;

  /// Set ONLY by the themed detail layouts.
  ///
  /// Null keeps today's exact literals, which is what Classic and every other
  /// caller must keep rendering — passing the theme is opt-in precisely so
  /// this widget cannot drift for them. Without it, white text and a gold
  /// focus ring land on Broadsheet's paper and Concrete's grey.
  final DetailTheme? theme;

  const ParentsGuideSection({
    super.key,
    required this.guide,
    this.tv = false,
    this.dense = false,
    this.interactive = true,
    this.accent,
    this.theme,
  });

  @override
  State<ParentsGuideSection> createState() => _ParentsGuideSectionState();
}

class _ParentsGuideSectionState extends State<ParentsGuideSection> {
  String? _expandedCategoryId;
  String? _selectedCategoryId;

  @override
  Widget build(BuildContext context) {
    final cats = widget.guide.categories;
    if (cats.isEmpty) return const SizedBox.shrink();

    if (StorageService.parentsGuideStyleCached == 'compass') {
      final selected = cats.firstWhere(
        (cat) => cat.id == _selectedCategoryId,
        orElse: () => cats.first,
      );
      return _CompassGuide(
        categories: cats,
        selected: selected,
        tv: widget.tv,
        dense: widget.dense,
        interactive: widget.interactive,
        accent: widget.accent,
        theme: widget.theme,
        onSelect: (cat) => setState(() => _selectedCategoryId = cat.id),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'PARENTS GUIDE',
          style: TextStyle(
            // The shipped ALPHA with the theme's ink, so Signal is exactly the
            // 50% white it always was and a light theme gets 50% black.
            color: widget.theme == null
                ? Colors.white.withValues(alpha: 0.5)
                : widget.theme!.fade(widget.theme!.tx, 0.5),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.2,
          ),
        ),
        SizedBox(height: widget.dense ? 8 : 12),
        for (final cat in cats)
          _CategoryRow(
            theme: widget.theme,
            category: cat,
            expanded: _expandedCategoryId == cat.id,
            tv: widget.tv,
            dense: widget.dense,
            onToggle: () => setState(() {
              _expandedCategoryId = _expandedCategoryId == cat.id
                  ? null
                  : cat.id;
            }),
          ),
      ],
    );
  }
}

class _CompassGuide extends StatelessWidget {
  final List<ParentsGuideCategory> categories;
  final ParentsGuideCategory selected;
  final bool tv;
  final bool dense;
  final bool interactive;
  final Color? accent;
  final DetailTheme? theme;
  final ValueChanged<ParentsGuideCategory> onSelect;

  const _CompassGuide({
    required this.categories,
    required this.selected,
    required this.tv,
    required this.dense,
    required this.interactive,
    required this.accent,
    required this.theme,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final hair = theme?.hair ?? Colors.white.withValues(alpha: 0.10);
    final resolvedAccent = accent ?? theme?.accent ?? const Color(0xFFABA124);
    final panel = theme == null
        ? const Color(0xFF121117)
        : theme!.fade(theme!.pane, 0.96);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720 && !dense;
        final overview = _CompassOverview(
          categories: categories,
          dense: dense,
          accent: resolvedAccent,
          theme: theme,
        );
        final dashboard = _CompassDashboard(
          categories: categories,
          selected: selected,
          tv: tv,
          dense: dense,
          interactive: interactive,
          accent: resolvedAccent,
          theme: theme,
          onSelect: onSelect,
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            color: panel,
            borderRadius: theme?.brRadius ?? BorderRadius.circular(16),
            border: Border.all(color: hair),
            boxShadow: theme?.shadowFor(tv),
          ),
          child: Padding(
            padding: EdgeInsets.all(dense ? 12 : 18),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 218, child: overview),
                      SizedBox(
                        height: 310,
                        child: VerticalDivider(color: hair, width: 34),
                      ),
                      Expanded(child: dashboard),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      overview,
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: dense ? 12 : 16,
                        ),
                        child: Divider(color: hair, height: 1),
                      ),
                      dashboard,
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _CompassOverview extends StatelessWidget {
  final List<ParentsGuideCategory> categories;
  final bool dense;
  final Color accent;
  final DetailTheme? theme;

  const _CompassOverview({
    required this.categories,
    required this.dense,
    required this.accent,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final tx = theme?.tx ?? Colors.white;
    final tx2 = theme?.tx2 ?? Colors.white.withValues(alpha: 0.65);
    final strongest = categories.reduce(
      (a, b) => _severityRank(a.severity) >= _severityRank(b.severity) ? a : b,
    );
    final noteCount = categories.fold<int>(
      0,
      (sum, cat) => sum + cat.items.where((item) => !item.isSpoiler).length,
    );
    final ringSize = dense ? 62.0 : 74.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'PARENTS GUIDE',
                style: _compassDataStyle(
                  theme,
                  size: 9.5,
                  color: accent,
                  weight: FontWeight.w800,
                  tracking: 2.0,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                theme?.displayCase('Know before you watch.') ??
                    'Know before you watch.',
                style: _compassTitleStyle(
                  theme,
                  size: dense ? 16 : 19,
                  color: tx,
                  weight: FontWeight.w700,
                  tracking: -0.35,
                  height: 1.08,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                '${categories.length} categories · $noteCount spoiler-safe '
                '${noteCount == 1 ? 'note' : 'notes'}',
                style: _compassBodyStyle(
                  theme,
                  size: dense ? 10.5 : 11.5,
                  color: tx2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        SizedBox.square(
          dimension: ringSize,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: _severityFraction(strongest.severity),
                strokeWidth: dense ? 5 : 6,
                backgroundColor: tx.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(
                  _severityColor(strongest.severity),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      strongest.severity.isEmpty ? '—' : strongest.severity,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _compassDataStyle(
                        theme,
                        size: dense ? 9 : 10,
                        color: tx,
                        weight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'STRONGEST',
                      style: _compassDataStyle(
                        theme,
                        size: 6.5,
                        color: tx2,
                        weight: FontWeight.w700,
                        tracking: 0.7,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompassDashboard extends StatelessWidget {
  final List<ParentsGuideCategory> categories;
  final ParentsGuideCategory selected;
  final bool tv;
  final bool dense;
  final bool interactive;
  final Color accent;
  final DetailTheme? theme;
  final ValueChanged<ParentsGuideCategory> onSelect;

  const _CompassDashboard({
    required this.categories,
    required this.selected,
    required this.tv,
    required this.dense,
    required this.interactive,
    required this.accent,
    required this.theme,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final tx2 = theme?.tx2 ?? Colors.white.withValues(alpha: 0.65);
    final categoriesWithNotes = [
      for (final category in categories)
        if (category.items.any((item) => !item.isSpoiler)) category,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              'AT A GLANCE',
              style: _compassDataStyle(
                theme,
                size: 9,
                color: accent,
                weight: FontWeight.w800,
                tracking: 1.8,
              ),
            ),
            const Spacer(),
            if (interactive)
              Text(
                'Select a category',
                style: _compassBodyStyle(theme, size: 10, color: tx2),
              ),
          ],
        ),
        SizedBox(height: dense ? 9 : 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 610
                ? 5
                : constraints.maxWidth >= 390
                ? 3
                : 2;
            final gap = dense ? 6.0 : 8.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final cat in categories)
                  SizedBox(
                    width: width,
                    child: _CompassCategoryTile(
                      category: cat,
                      selected: interactive && cat.id == selected.id,
                      tv: tv,
                      dense: dense,
                      interactive: interactive,
                      theme: theme,
                      onSelect: () => onSelect(cat),
                    ),
                  ),
              ],
            );
          },
        ),
        if (interactive) ...[
          SizedBox(height: dense ? 10 : 14),
          _CompassDetail(category: selected, dense: dense, theme: theme),
        ] else if (categoriesWithNotes.isNotEmpty) ...[
          SizedBox(height: dense ? 14 : 18),
          Text(
            'SPOILER-SAFE NOTES',
            style: _compassDataStyle(
              theme,
              size: 9,
              color: accent,
              weight: FontWeight.w800,
              tracking: 1.6,
            ),
          ),
          SizedBox(height: dense ? 8 : 10),
          for (var i = 0; i < categoriesWithNotes.length; i++) ...[
            if (i > 0) SizedBox(height: dense ? 8 : 10),
            _CompassDetail(
              category: categoriesWithNotes[i],
              dense: dense,
              theme: theme,
              selectedPrefix: false,
            ),
          ],
        ],
      ],
    );
  }
}

class _CompassCategoryTile extends StatefulWidget {
  final ParentsGuideCategory category;
  final bool selected;
  final bool tv;
  final bool dense;
  final bool interactive;
  final DetailTheme? theme;
  final VoidCallback onSelect;

  const _CompassCategoryTile({
    required this.category,
    required this.selected,
    required this.tv,
    required this.dense,
    required this.interactive,
    required this.theme,
    required this.onSelect,
  });

  @override
  State<_CompassCategoryTile> createState() => _CompassCategoryTileState();
}

class _CompassCategoryTileState extends State<_CompassCategoryTile> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final tx = t?.tx ?? Colors.white;
    final severity = _severityColor(widget.category.severity);
    final active = _focused || _hovered;
    final focus = t?.focus ?? HomeTheme.focusGold;
    final hair = t?.hair ?? Colors.white.withValues(alpha: 0.08);

    final tile = AnimatedContainer(
      duration: widget.tv ? Duration.zero : const Duration(milliseconds: 140),
      height: widget.dense ? 70 : 82,
      padding: EdgeInsets.all(widget.dense ? 8 : 10),
      decoration: BoxDecoration(
        color: widget.selected
            ? severity.withValues(alpha: 0.08)
            : (t == null
                  ? Colors.white.withValues(alpha: 0.035)
                  : t.fade(t.tx, 0.035)),
        borderRadius: t?.brRadius ?? BorderRadius.circular(10),
        border: Border.all(
          color: active
              ? focus
              : widget.selected
              ? severity.withValues(alpha: 0.55)
              : hair,
          width: active
              ? (t?.focusWidthFor(widget.tv) ?? 2)
              : widget.selected
              ? 1.2
              : 0.7,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              widget.category.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _compassBodyStyle(
                t,
                size: widget.dense ? 10.5 : 11.5,
                color: tx,
                height: 1.15,
                weight: FontWeight.w600,
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 3,
              child: ColoredBox(
                color: tx.withValues(alpha: 0.09),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: _severityFraction(widget.category.severity),
                    child: ColoredBox(color: severity),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            widget.category.severity.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _compassDataStyle(
              t,
              size: widget.dense ? 7.5 : 8,
              color: severity,
              weight: FontWeight.w800,
              tracking: 0.55,
            ),
          ),
        ],
      ),
    );

    if (!widget.interactive) {
      return Semantics(
        label: '${widget.category.label}, ${widget.category.severity}',
        child: tile,
      );
    }

    return Semantics(
      button: true,
      selected: widget.selected,
      label: '${widget.category.label}, ${widget.category.severity}',
      child: Focus(
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent || event is KeyRepeatEvent) {
            final direction = switch (event.logicalKey) {
              LogicalKeyboardKey.arrowDown => TraversalDirection.down,
              LogicalKeyboardKey.arrowUp => TraversalDirection.up,
              _ => null,
            };
            if (direction != null &&
                FocusScope.of(context).focusInDirection(direction)) {
              return KeyEventResult.handled;
            }
          }
          if (event is KeyDownEvent &&
              (isActivateKey(event.logicalKey) ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onSelect,
            child: tile,
          ),
        ),
      ),
    );
  }
}

class _CompassDetail extends StatelessWidget {
  final ParentsGuideCategory category;
  final bool dense;
  final DetailTheme? theme;
  final bool selectedPrefix;

  const _CompassDetail({
    required this.category,
    required this.dense,
    required this.theme,
    this.selectedPrefix = true,
  });

  @override
  Widget build(BuildContext context) {
    final tx = theme?.tx ?? Colors.white;
    final tx2 = theme?.tx2 ?? Colors.white.withValues(alpha: 0.65);
    final tx3 = theme?.tx3 ?? Colors.white.withValues(alpha: 0.38);
    final hair = theme?.hair ?? Colors.white.withValues(alpha: 0.08);
    final items = category.items.where((item) => !item.isSpoiler).toList();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Container(
        key: ValueKey(category.id),
        width: double.infinity,
        padding: EdgeInsets.all(dense ? 11 : 14),
        decoration: BoxDecoration(
          color: theme == null
              ? Colors.white.withValues(alpha: 0.035)
              : theme!.fade(theme!.tx, 0.035),
          borderRadius: theme?.brRadius ?? BorderRadius.circular(10),
          border: Border.all(color: hair),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    theme?.displayCase(
                          selectedPrefix
                              ? 'Selected · ${category.label}'
                              : category.label,
                        ) ??
                        (selectedPrefix
                            ? 'Selected · ${category.label}'
                            : category.label),
                    style: _compassTitleStyle(
                      theme,
                      size: dense ? 13 : 14,
                      color: tx,
                      weight: FontWeight.w700,
                      tracking: 0,
                    ),
                  ),
                ),
                _SeverityBadge(
                  label: category.severity,
                  color: _severityColor(category.severity),
                  dense: true,
                  theme: theme,
                ),
              ],
            ),
            SizedBox(height: dense ? 8 : 10),
            if (items.isEmpty)
              Text(
                'No spoiler-safe advisory notes are available.',
                style: _compassBodyStyle(
                  theme,
                  size: dense ? 10.5 : 11.5,
                  color: tx2,
                ),
              )
            else
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) SizedBox(height: dense ? 6 : 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: tx3,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        items[i].text,
                        style: _compassBodyStyle(
                          theme,
                          size: dense ? 10.5 : 11.5,
                          color: tx2,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
          ],
        ),
      ),
    );
  }
}

int _severityRank(String severity) => switch (severity.toLowerCase()) {
  'none' => 0,
  'mild' => 1,
  'moderate' => 2,
  'severe' => 3,
  _ => 0,
};

double _severityFraction(String severity) => switch (severity.toLowerCase()) {
  'none' => 0,
  'mild' => 1 / 3,
  'moderate' => 2 / 3,
  'severe' => 1,
  _ => 0,
};

Color _severityColor(String severity) => switch (severity.toLowerCase()) {
  'none' => const Color(0xFF4ADE80),
  'mild' => const Color(0xFFFBBF24),
  'moderate' => const Color(0xFFFB923C),
  'severe' => const Color(0xFFEF4444),
  _ => Colors.white54,
};

TextStyle _compassTitleStyle(
  DetailTheme? theme, {
  required double size,
  required Color color,
  required FontWeight weight,
  required double tracking,
  double height = 1.05,
}) {
  final themed = theme?.titleStyle(
    size: size,
    weight: weight,
    tracking: tracking,
    height: height,
  );
  return (themed ??
          TextStyle(
            fontSize: size,
            fontWeight: weight,
            letterSpacing: tracking,
            height: height,
          ))
      .copyWith(color: color);
}

TextStyle _compassDataStyle(
  DetailTheme? theme, {
  required double size,
  required Color color,
  required FontWeight weight,
  double? tracking,
}) {
  final themed = theme?.dataStyle(size: size, color: color, weight: weight);
  return (themed ?? TextStyle(fontSize: size, color: color, fontWeight: weight))
      .copyWith(letterSpacing: tracking);
}

TextStyle _compassBodyStyle(
  DetailTheme? theme, {
  required double size,
  required Color color,
  double height = 1.4,
  FontWeight? weight,
}) {
  final themed = theme?.bodyStyle(size: size, color: color, height: height);
  return (themed ?? TextStyle(fontSize: size, color: color, height: height))
      .copyWith(fontWeight: weight);
}

class _CategoryRow extends StatefulWidget {
  final DetailTheme? theme;
  final ParentsGuideCategory category;
  final bool expanded;
  final bool tv;
  final bool dense;
  final VoidCallback onToggle;

  const _CategoryRow({
    required this.theme,
    required this.category,
    required this.expanded,
    required this.tv,
    required this.dense,
    required this.onToggle,
  });

  @override
  State<_CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends State<_CategoryRow> {
  bool _focused = false;
  bool _hovered = false;
  bool get _active => _focused || _hovered;

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    final color = _severityColor(cat.severity);
    final hasItems = cat.items.isNotEmpty;
    // Null under Classic, which renders this section unthemed.
    final t = widget.theme;

    return Padding(
      padding: EdgeInsets.only(bottom: widget.dense ? 4 : 6),
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              hasItems &&
              (isActivateKey(event.logicalKey) ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onToggle();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: hasItems
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            onTap: hasItems ? widget.onToggle : null,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: widget.tv
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(
                horizontal: widget.dense ? 10 : 12,
                vertical: widget.dense ? 7 : 9,
              ),
              decoration: BoxDecoration(
                // The shipped alphas over the theme's ink: Signal keeps exactly
                // the 8%/4% white it had, and a light theme gets those same
                // weights in black rather than an invisible white.
                color: _active
                    ? (t == null
                          ? Colors.white.withValues(alpha: 0.08)
                          : t.fade(t.tx, 0.08))
                    : (t == null
                          ? Colors.white.withValues(alpha: 0.04)
                          : t.fade(t.tx, 0.04)),
                borderRadius: t?.brRadius ?? BorderRadius.circular(10),
                border: Border.all(
                  // _active is the FOCUS state, so a theme's ring must be full
                  // strength and must honour the TV width floor — a 1.2px 50%
                  // hairline is not a cursor you can see at three metres.
                  color: _active
                      ? (t?.focus ?? HomeTheme.focusGold.withValues(alpha: 0.5))
                      : (t?.hair ?? Colors.white.withValues(alpha: 0.06)),
                  width: _active ? (t?.focusWidthFor(widget.tv) ?? 1.2) : 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _SeverityDot(color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          cat.label,
                          style: TextStyle(
                            color: widget.theme == null
                                ? Colors.white.withValues(alpha: 0.88)
                                : widget.theme!.fade(widget.theme!.tx, 0.88),
                            fontSize: widget.dense ? 12 : 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      _SeverityBadge(
                        label: cat.severity,
                        color: color,
                        dense: widget.dense,
                      ),
                      if (hasItems) ...[
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: widget.expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            Icons.expand_more_rounded,
                            size: 16,
                            color:
                                widget.theme?.tx3 ??
                                Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ],
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: _buildItems(cat),
                    crossFadeState: widget.expanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                    sizeCurve: Curves.easeOutCubic,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItems(ParentsGuideCategory cat) {
    final nonSpoilerItems = cat.items.where((i) => !i.isSpoiler).toList();
    if (nonSpoilerItems.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < nonSpoilerItems.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color:
                          widget.theme?.tx3 ??
                          Colors.white.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    nonSpoilerItems[i].text,
                    style: TextStyle(
                      color:
                          widget.theme?.tx2 ??
                          Colors.white.withValues(alpha: 0.65),
                      fontSize: widget.dense ? 11 : 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SeverityDot extends StatelessWidget {
  final Color color;
  const _SeverityDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6),
        ],
      ),
    );
  }
}

class _SeverityBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool dense;
  final DetailTheme? theme;

  const _SeverityBadge({
    required this.label,
    required this.color,
    this.dense = false,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 8,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: theme?.brSm ?? BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        label,
        style: _compassDataStyle(
          theme,
          size: dense ? 10 : 11,
          color: color,
          weight: FontWeight.w700,
          tracking: 0.3,
        ),
      ),
    );
  }
}
