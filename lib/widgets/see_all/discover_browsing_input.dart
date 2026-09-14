import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Observe browsing input without consuming the card/filter navigation action.
class DiscoverBrowsingInput extends StatefulWidget {
  const DiscoverBrowsingInput({
    super.key,
    required this.onActivity,
    required this.child,
  });
  final VoidCallback onActivity;
  final Widget child;
  @override
  State<DiscoverBrowsingInput> createState() => _DiscoverBrowsingInputState();
}

class _DiscoverBrowsingInputState extends State<DiscoverBrowsingInput> {
  final _focus = FocusNode(canRequestFocus: false, skipTraversal: true);
  bool _key(KeyEvent event) {
    if (_focus.hasFocus && (event is KeyDownEvent || event is KeyRepeatEvent)) {
      widget.onActivity();
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_key);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.onActivity(),
      onPointerHover: (_) => widget.onActivity(),
      onPointerSignal: (_) => widget.onActivity(),
      child: widget.child,
    ),
  );
}
