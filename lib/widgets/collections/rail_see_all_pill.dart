import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme_scope.dart';

/// The "See all ›" control at the right of a rail header on a stacked-rails
/// screen. On TV it is the rung between rails in the DPAD ladder (up to the
/// rail above, down into this rail's cards); elsewhere it is a plain link.
class RailSeeAllPill extends StatefulWidget {
  final FocusNode node;
  final bool isTelevision;
  final VoidCallback onPressed;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onFocused;

  const RailSeeAllPill({
    super.key,
    required this.node,
    required this.isTelevision,
    required this.onPressed,
    required this.onUp,
    required this.onDown,
    required this.onFocused,
  });

  @override
  State<RailSeeAllPill> createState() => _RailSeeAllPillState();
}

class _RailSeeAllPillState extends State<RailSeeAllPill> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.node.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant RailSeeAllPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node != widget.node) {
      oldWidget.node.removeListener(_onFocusChange);
      widget.node.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.node.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    final focused = widget.node.hasFocus;
    if (focused == _focused) return;
    setState(() => _focused = focused);
    if (focused) widget.onFocused();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (!widget.isTelevision || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      widget.onDown();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.onUp();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      // Nothing beside the pill — swallow so focus can't wander off-screen.
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      widget.onPressed();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final color = _focused ? app.core.tx : app.fade(app.core.tx, 0.62);
    return Focus(
      focusNode: widget.node,
      onKeyEvent: _onKey,
      child: InkWell(
        onTap: widget.onPressed,
        borderRadius: app.shape.br(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
          decoration: BoxDecoration(
            borderRadius: app.shape.br(9),
            color: _focused ? app.fade(app.core.tx, 0.10) : Colors.transparent,
            border: Border.all(
              color: _focused ? app.seeAll.accentBorder : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'See all',
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
