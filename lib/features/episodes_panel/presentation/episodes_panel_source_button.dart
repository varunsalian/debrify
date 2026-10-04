import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Select Source Button for catalog episode browser ────────────────────────
class _CatalogSelectSourceButton extends StatefulWidget {
  final bool hasBoundSource;
  final int sourceCount;
  final VoidCallback onTap;
  final FocusNode? onLeftFocus;
  final VoidCallback? onDownArrow;
  final VoidCallback? onUpArrow;

  const _CatalogSelectSourceButton({
    required this.hasBoundSource,
    this.sourceCount = 0,
    required this.onTap,
    this.onLeftFocus,
    this.onDownArrow,
    this.onUpArrow,
  });

  @override
  State<_CatalogSelectSourceButton> createState() =>
      _CatalogSelectSourceButtonState();
}

class _CatalogSelectSourceButtonState
    extends State<_CatalogSelectSourceButton> {
  final FocusNode _focusNode = FocusNode(
    debugLabel: 'catalog-select-source-btn',
  );
  bool _isFocused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.maybeOf(context);
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateKey(event.logicalKey)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          widget.onUpArrow?.call();
          return widget.onUpArrow != null
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            widget.onLeftFocus != null) {
          widget.onLeftFocus!.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          return KeyEventResult.handled; // rightmost button
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          widget.onDownArrow?.call();
          return widget.onDownArrow != null
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: PlatformUtil.isTelevision
              ? Duration.zero
              : const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: widget.hasBoundSource
                ? t.fade(t.focus, 0.14)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused
                  ? t.focus
                  : widget.hasBoundSource
                  ? t.fade(t.focus, 0.45)
                  : Colors.white.withValues(alpha: 0.14),
              width: _isFocused ? 2 : 1,
            ),
            boxShadow: (_isFocused && !PlatformUtil.isTelevision)
                ? [BoxShadow(color: t.fade(t.focus, 0.32), blurRadius: 12)]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.hasBoundSource
                    ? Icons.link_rounded
                    : Icons.link_off_rounded,
                size: 16,
                color: widget.hasBoundSource
                    ? t.focus
                    : Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 6),
              Text(
                widget.hasBoundSource
                    ? (widget.sourceCount > 1
                          ? 'Sources (${widget.sourceCount})'
                          : 'Source')
                    : 'Select Source',
                style: TextStyle(
                  color: widget.hasBoundSource
                      ? t.focus
                      : Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef EpisodesPanelSourceButton = _CatalogSelectSourceButton;

const episodesPanelSourceButtonConstructor = _CatalogSelectSourceButton.new;
