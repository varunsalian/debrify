import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';

/// A [LayoutBuilder] that keeps the size it had before the system keyboard
/// opened.
///
/// Android resizes the app above the system keyboard. On a TV that can take
/// half the screen, which drops IPTV Spotlight below its minimum height: the
/// page switched to the classic layout, the Spotlight search field that had
/// just opened the keyboard was removed, and the keyboard closed with it. While
/// the keyboard is open and only the height has shrunk, this lays [builder]
/// out at the earlier size and clips what the keyboard covers.
class KeyboardSteadyLayoutBuilder extends StatefulWidget {
  const KeyboardSteadyLayoutBuilder({
    super.key,
    required this.builder,
    this.enabled = true,
  });

  final LayoutWidgetBuilder builder;

  /// False behaves exactly like a plain [LayoutBuilder].
  final bool enabled;

  @override
  State<KeyboardSteadyLayoutBuilder> createState() =>
      _KeyboardSteadyLayoutBuilderState();
}

class _KeyboardSteadyLayoutBuilderState
    extends State<KeyboardSteadyLayoutBuilder> {
  Size? _steady;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final keyboardOpen = View.of(context).viewInsets.bottom > 0;
      final steady = _steady;
      final hold =
          widget.enabled &&
          keyboardOpen &&
          steady != null &&
          steady.width == size.width &&
          size.height < steady.height;
      // Only a keyboard-free size is a size to come back to.
      if (!keyboardOpen && size.isFinite) _steady = size;
      final target = hold ? BoxConstraints.tight(steady) : constraints;
      // One tree shape whether holding or not: a wrapper that appeared only
      // while the keyboard is open would remount the page under it, search
      // field and keyboard included.
      return ClipRect(
        clipBehavior: hold ? Clip.hardEdge : Clip.none,
        child: OverflowBox(
          alignment: Alignment.topCenter,
          fit: OverflowBoxFit.deferToChild,
          minWidth: target.minWidth,
          maxWidth: target.maxWidth,
          minHeight: target.minHeight,
          maxHeight: target.maxHeight,
          child: Builder(builder: (context) => widget.builder(context, target)),
        ),
      );
    },
  );
}
