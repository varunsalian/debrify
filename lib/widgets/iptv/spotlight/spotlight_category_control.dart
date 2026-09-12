import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/tv_keys.dart';
import '../styles/iptv_style.dart';

/// Prominent category selector shared by wide and compact Spotlight shells.
class SpotlightCategoryControl extends StatelessWidget {
  final String categoryLabel;
  final int channelCount;
  final bool loading;
  final bool dense;
  final VoidCallback onPressed;
  final VoidCallback? onOpenOptions;
  final FocusNode? focusNode;
  final FocusNode? optionsFocusNode;

  const SpotlightCategoryControl({
    super.key,
    required this.categoryLabel,
    required this.channelCount,
    required this.onPressed,
    this.loading = false,
    this.dense = false,
    this.onOpenOptions,
    this.focusNode,
    this.optionsFocusNode,
  });

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    final category = categoryLabel.trim().isEmpty
        ? 'All channels'
        : categoryLabel.trim();
    final countLabel = loading ? 'Loading' : _formatCount(channelCount);

    if (dense) {
      return KeyedSubtree(
        key: const ValueKey<String>('spotlight-category-control'),
        child: Row(
          children: [
            Expanded(
              child: _CategoryButton(
                focusNode: focusNode,
                semanticsLabel: 'Category, $category, $countLabel channels',
                onPressed: onPressed,
                child: Text(
                  '$category · $countLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (onOpenOptions != null) ...[
              const SizedBox(width: 7),
              _CategoryOptionsButton(
                focusNode: optionsFocusNode,
                onPressed: onOpenOptions!,
              ),
            ],
          ],
        ),
      );
    }

    return DecoratedBox(
      key: const ValueKey<String>('spotlight-category-control'),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CATEGORY',
              style: TextStyle(
                color: t.fgDim,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: _CategoryButton(
                    focusNode: focusNode,
                    semanticsLabel: 'Category, $category, $countLabel channels',
                    onPressed: onPressed,
                    child: Text(
                      '$category · $countLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (onOpenOptions != null) ...[
                  const SizedBox(width: 7),
                  _CategoryOptionsButton(
                    focusNode: optionsFocusNode,
                    onPressed: onOpenOptions!,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryButton extends StatefulWidget {
  final Widget child;
  final String semanticsLabel;
  final FocusNode? focusNode;
  final VoidCallback onPressed;

  const _CategoryButton({
    required this.child,
    required this.semanticsLabel,
    required this.focusNode,
    required this.onPressed,
  });

  @override
  State<_CategoryButton> createState() => _CategoryButtonState();
}

class _CategoryButtonState extends State<_CategoryButton> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    final ink = _focused ? t.focusInk! : t.fg;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: widget.semanticsLabel,
      onTap: widget.onPressed,
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        onKeyEvent: (_, event) {
          if (isActivateOrSpaceKey(event.logicalKey)) {
            if (event is KeyDownEvent) widget.onPressed();
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
            excludeFromSemantics: true,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              key: const ValueKey<String>('spotlight-category-pill'),
              duration: const Duration(milliseconds: 120),
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: _focused
                    ? t.focusFill
                    : _hovered
                    ? t.focusTint
                    : t.selectedTint,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: _focused ? t.focusFill! : t.hairline2,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: DefaultTextStyle(
                      style: TextStyle(
                        color: ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                      child: widget.child,
                    ),
                  ),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 19,
                    color: _focused ? t.focusInk : t.accent,
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

class _CategoryOptionsButton extends StatefulWidget {
  final FocusNode? focusNode;
  final VoidCallback onPressed;

  const _CategoryOptionsButton({
    required this.focusNode,
    required this.onPressed,
  });

  @override
  State<_CategoryOptionsButton> createState() => _CategoryOptionsButtonState();
}

class _CategoryOptionsButtonState extends State<_CategoryOptionsButton> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: 'Category options',
      onTap: widget.onPressed,
      child: Tooltip(
        message: 'Category options',
        child: Focus(
          focusNode: widget.focusNode,
          onFocusChange: (focused) {
            if (_focused != focused) setState(() => _focused = focused);
          },
          onKeyEvent: (_, event) {
            if (isActivateOrSpaceKey(event.logicalKey)) {
              if (event is KeyDownEvent) widget.onPressed();
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
              excludeFromSemantics: true,
              onTap: widget.onPressed,
              child: AnimatedContainer(
                key: const ValueKey<String>('spotlight-category-options'),
                duration: const Duration(milliseconds: 120),
                width: 42,
                height: 44,
                decoration: BoxDecoration(
                  color: _focused
                      ? t.focusFill
                      : _hovered
                      ? t.focusTint
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: _focused ? t.focusFill! : t.hairline2,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.more_horiz_rounded,
                  color: _focused ? t.focusInk : t.fgMid,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatCount(int value) {
  if (value < 1000) return '$value';
  if (value < 1000000) {
    final thousands = value / 1000;
    return '${thousands.toStringAsFixed(thousands >= 10 ? 0 : 1)}K';
  }
  final millions = value / 1000000;
  return '${millions.toStringAsFixed(millions >= 10 ? 0 : 1)}M';
}
