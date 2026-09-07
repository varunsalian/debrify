/// The synopsis block on `CatalogItemDetailScreen` and its focusable
/// "Read more / Show less" toggle.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/tv_keys.dart';
import 'theme/detail_theme.dart';

// ── Description with "Read more" ───────────────────────────────────────────

class CatalogDetailDescription extends StatelessWidget {
  final String text;
  final bool wide;
  final bool dense;
  final int collapsedLines;
  final bool expanded;
  final VoidCallback onToggle;
  const CatalogDetailDescription({
    super.key,
    required this.text,
    required this.wide,
    required this.expanded,
    required this.onToggle,
    this.dense = false,
    this.collapsedLines = 4,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.82),
      fontSize: dense ? 13 : (wide ? 17 : 15),
      height: dense ? 1.4 : 1.5,
      letterSpacing: 0.1,
      shadows: const [Shadow(color: Color(0x66000000), blurRadius: 6)],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: collapsedLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: style,
              maxLines: expanded ? null : collapsedLines,
              overflow: expanded ? TextOverflow.visible : TextOverflow.fade,
            ),
            if (overflows) ...[
              const SizedBox(height: 6),
              CatalogDetailReadMoreToggle(
                label: expanded ? 'Show less' : 'Read more',
                onToggle: onToggle,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Focusable "Read more / Show less" toggle. A bare GestureDetector is not
/// reachable or activatable with a D-pad/remote, so this mirrors the
/// focus idiom used by [CatalogDetailQuickAction]: a [Focus] that tracks focus, accepts
/// select/enter/space, and shows a gold affordance when focused or hovered.
class CatalogDetailReadMoreToggle extends StatefulWidget {
  final String label;
  final VoidCallback onToggle;
  const CatalogDetailReadMoreToggle({
    super.key,
    required this.label,
    required this.onToggle,
  });

  @override
  State<CatalogDetailReadMoreToggle> createState() =>
      _CatalogDetailReadMoreToggleState();
}

class _CatalogDetailReadMoreToggleState
    extends State<CatalogDetailReadMoreToggle> {
  bool _focused = false;
  bool _hovered = false;
  bool get _active => _focused || _hovered;

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.maybeOf(context);
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
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
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onToggle,
          behavior: HitTestBehavior.opaque,
          // Inactive state is byte-identical to the old bare text link (no
          // box/indent, so the phone/touch look is unchanged). Focus/hover is
          // signalled with gold + underline + a transform-only scale (no
          // layout reflow), echoing CatalogDetailQuickAction's scale feedback.
          child: AnimatedScale(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            scale: _active ? 1.04 : 1.0,
            alignment: Alignment.centerLeft,
            child: Text(
              widget.label,
              style: TextStyle(
                color: _active ? t.focus : Colors.white.withValues(alpha: 0.95),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                decoration: _active ? TextDecoration.underline : null,
                decorationColor: t.focus,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
