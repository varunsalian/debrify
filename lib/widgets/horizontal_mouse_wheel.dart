import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Wraps a horizontal scrollable so a vertical mouse wheel scrolls it
/// horizontally. Registers via pointerSignalResolver so the outer vertical
/// page Scrollable doesn't *also* scroll on the same event — only the row
/// moves. Trackpads and Shift+wheel are left alone.
class HorizontalMouseWheel extends StatelessWidget {
  final ScrollController controller;
  final Widget child;

  const HorizontalMouseWheel({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        // Only remap actual mouse wheels — trackpads send dy too and should
        // continue to scroll the outer vertical page, not the row.
        if (event.kind != PointerDeviceKind.mouse) return;
        if (!controller.hasClients) return;
        final dy = event.scrollDelta.dy;
        if (dy == 0 || event.scrollDelta.dx != 0) return;
        final pos = controller.position;
        final target = (pos.pixels + dy).clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        );
        // Row already at the edge — don't claim the event so the outer page
        // Scrollable can pick it up and scroll vertically instead.
        if (target == pos.pixels) return;
        // Claim the event via the resolver. Hit-test dispatch is leaf-first,
        // so this register call beats the outer vertical Scrollable's, which
        // means the outer page won't also scroll on this wheel tick.
        GestureBinding.instance.pointerSignalResolver.register(event, (e) {
          if (!controller.hasClients) return;
          controller.jumpTo(target);
        });
      },
      child: child,
    );
  }
}
