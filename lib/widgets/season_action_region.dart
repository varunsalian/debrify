import 'package:flutter/material.dart';
import '../utils/tv_keys.dart';

/// Adds held-OK and touch long-press without turning a short press into a hold.
class SeasonActionRegion extends StatefulWidget {
  const SeasonActionRegion({
    super.key,
    required this.child,
    required this.onTap,
    this.onOptions,
  });
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onOptions;
  @override
  State<SeasonActionRegion> createState() => _SeasonActionRegionState();
}

class _SeasonActionRegionState extends State<SeasonActionRegion> {
  late final TvHoldOk _hold = TvHoldOk(
    onTap: () => widget.onTap(),
    onHold: () => widget.onOptions?.call(),
  );
  @override
  void dispose() {
    _hold.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onOptions == null) return widget.child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (!focused) _hold.reset();
      },
      onKeyEvent: (_, event) => isActivateOrSpaceKey(event.logicalKey)
          ? _hold.handle(event)
          : KeyEventResult.ignored,
      child: GestureDetector(
        onLongPress: widget.onOptions,
        child: widget.child,
      ),
    );
  }
}
