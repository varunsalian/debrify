import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/imdb_parents_guide_service.dart';
import 'home/home_theme.dart';

class ParentsGuideSection extends StatefulWidget {
  final ParentsGuideResult guide;
  final bool tv;
  final bool dense;

  const ParentsGuideSection({
    super.key,
    required this.guide,
    this.tv = false,
    this.dense = false,
  });

  @override
  State<ParentsGuideSection> createState() => _ParentsGuideSectionState();
}

class _ParentsGuideSectionState extends State<ParentsGuideSection> {
  String? _expandedCategoryId;

  @override
  Widget build(BuildContext context) {
    final cats = widget.guide.categories;
    if (cats.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'PARENTS GUIDE',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.2,
          ),
        ),
        SizedBox(height: widget.dense ? 8 : 12),
        for (final cat in cats)
          _CategoryRow(
            category: cat,
            expanded: _expandedCategoryId == cat.id,
            tv: widget.tv,
            dense: widget.dense,
            onToggle: () => setState(() {
              _expandedCategoryId =
                  _expandedCategoryId == cat.id ? null : cat.id;
            }),
          ),
      ],
    );
  }
}

class _CategoryRow extends StatefulWidget {
  final ParentsGuideCategory category;
  final bool expanded;
  final bool tv;
  final bool dense;
  final VoidCallback onToggle;

  const _CategoryRow({
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

    return Padding(
      padding: EdgeInsets.only(bottom: widget.dense ? 4 : 6),
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              hasItems &&
              (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onToggle();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor:
              hasItems ? SystemMouseCursors.click : SystemMouseCursors.basic,
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
                color: _active
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _active
                      ? HomeTheme.focusGold.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.06),
                  width: _active ? 1.2 : 0.5,
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
                            color: Colors.white.withValues(alpha: 0.88),
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
                            color: Colors.white.withValues(alpha: 0.4),
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
    final nonSpoilerItems =
        cat.items.where((i) => !i.isSpoiler).toList();
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
                      color: Colors.white.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    nonSpoilerItems[i].text,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
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

  static Color _severityColor(String severity) {
    return switch (severity.toLowerCase()) {
      'none' => const Color(0xFF4ADE80),
      'mild' => const Color(0xFFFBBF24),
      'moderate' => const Color(0xFFFB923C),
      'severe' => const Color(0xFFEF4444),
      _ => Colors.white54,
    };
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

  const _SeverityBadge({
    required this.label,
    required this.color,
    this.dense = false,
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
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: dense ? 10 : 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
