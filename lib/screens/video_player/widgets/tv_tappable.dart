import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/platform_util.dart';

/// A tap target that a remote can also reach.
///
/// The player's sheets were built for touch: rows are bare `GestureDetector`s,
/// which answer taps and nothing else, so on a television the DPAD had nowhere
/// to go and OK did nothing. This adds focus and keyboard/remote activation
/// around the same child.
///
/// Deliberately non-invasive so the touch layout is untouched:
/// * focus is only requestable on a television, so phones and desktop keep
///   exactly the traversal they have today;
/// * the focus ring is painted with `foregroundDecoration`, which draws OVER
///   the child instead of wrapping it — a border container would add insets and
///   shift every row.
class TvTappable extends StatefulWidget {
  const TvTappable({
    super.key,
    required this.onTap,
    required this.child,
    this.autofocus = false,
    this.borderRadius = 10,
  });

  final VoidCallback? onTap;
  final Widget child;
  final bool autofocus;
  final double borderRadius;

  @override
  State<TvTappable> createState() => _TvTappableState();
}

class _TvTappableState extends State<TvTappable> {
  bool _focused = false;

  bool get _enabled => widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final tv = PlatformUtil.isTelevision;
    final child = GestureDetector(onTap: widget.onTap, child: widget.child);
    if (!tv) return child;

    return Focus(
      canRequestFocus: _enabled,
      skipTraversal: !_enabled,
      autofocus: widget.autofocus && _enabled,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent || !_enabled) return KeyEventResult.ignored;
        final k = event.logicalKey;
        // `enter` is what the Siri Remote's click pad sends; the others cover
        // Android TV remotes, controllers and keyboards.
        if (k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter ||
            k == LogicalKeyboardKey.select ||
            k == LogicalKeyboardKey.gameButtonA ||
            k == LogicalKeyboardKey.space) {
          widget.onTap!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        foregroundDecoration: _focused
            ? BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(widget.borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.22),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              )
            : null,
        child: child,
      ),
    );
  }
}
