import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/widgets/parallax_focus.dart';
import '../../utils/tv_keys.dart';
import 'onboarding_models.dart';

@immutable
class OnboardCell {
  const OnboardCell(this.row, this.column);

  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is OnboardCell && row == other.row && column == other.column;

  @override
  int get hashCode => Object.hash(row, column);
}

const Map<OnboardStep, OnboardCell> onboardLandingCells = {
  OnboardStep.mode: OnboardCell(0, 0),
  OnboardStep.services: OnboardCell(0, 0),
  OnboardStep.key: OnboardCell(1, 0),
  OnboardStep.engines: OnboardCell(0, 0),
  OnboardStep.trackers: OnboardCell(0, 0),
  OnboardStep.importing: OnboardCell(0, 0),
  OnboardStep.done: OnboardCell(0, 0),
};

/// Explicit DPAD graph for the current step. Vertical moves across a shorter
/// row use its nearest column; LEFT from column zero parks on Back and RIGHT
/// returns.
class OnboardFocusController {
  final FocusNode backNode = FocusNode(debugLabel: 'onboarding-back');
  final Map<OnboardCell, FocusNode> _nodes = <OnboardCell, FocusNode>{};
  OnboardCell? _parked;
  OnboardCell? _landingOverride;

  void register(OnboardCell cell, FocusNode node) => _nodes[cell] = node;

  void unregister(OnboardCell cell, FocusNode node) {
    if (identical(_nodes[cell], node)) _nodes.remove(cell);
  }

  void setLandingOverride(OnboardCell? cell) => _landingOverride = cell;

  void focusLanding(OnboardStep step) {
    final requested = _landingOverride ?? onboardLandingCells[step];
    final target = requested == null ? null : _nodes[requested];
    (target ?? (_nodes.isEmpty ? null : _nodes.values.first))?.requestFocus();
  }

  void move(OnboardCell from, TraversalDirection direction) {
    if (direction == TraversalDirection.left && from.column == 0) {
      _parked = from;
      backNode.requestFocus();
      return;
    }
    final target = switch (direction) {
      TraversalDirection.left => OnboardCell(from.row, from.column - 1),
      TraversalDirection.right => OnboardCell(from.row, from.column + 1),
      TraversalDirection.up => OnboardCell(from.row - 1, from.column),
      TraversalDirection.down => OnboardCell(from.row + 1, from.column),
    };
    final node =
        _nodes[target] ??
        ((direction == TraversalDirection.up ||
                direction == TraversalDirection.down)
            ? _nearestNodeInRow(target.row, from.column)
            : null);
    if (node == null) return;
    ParallaxTravel.note(switch (direction) {
      TraversalDirection.left => const Offset(-1, 0),
      TraversalDirection.right => const Offset(1, 0),
      TraversalDirection.up => const Offset(0, -1),
      TraversalDirection.down => const Offset(0, 1),
    });
    node.requestFocus();
  }

  FocusNode? _nearestNodeInRow(int row, int column) {
    MapEntry<OnboardCell, FocusNode>? nearest;
    for (final entry in _nodes.entries) {
      if (entry.key.row != row || !entry.value.canRequestFocus) continue;
      if (nearest == null ||
          (entry.key.column - column).abs() <
              (nearest.key.column - column).abs()) {
        nearest = entry;
      }
    }
    return nearest?.value;
  }

  void returnFromBack() {
    final target = _parked == null ? null : _nodes[_parked!];
    (target ?? (_nodes.isEmpty ? null : _nodes.values.first))?.requestFocus();
  }

  void clearStep() {
    _nodes.clear();
    _parked = null;
    _landingOverride = null;
  }

  void dispose() => backNode.dispose();
}

class OnboardFocusable extends StatefulWidget {
  const OnboardFocusable({
    super.key,
    required this.controller,
    required this.cell,
    required this.onActivate,
    required this.builder,
    this.shape = ParallaxShape.sourceCard,
    this.radius,
    this.enabled = true,
    this.autofocus = false,
    this.semanticLabel,
  });

  final OnboardFocusController controller;
  final OnboardCell cell;
  final VoidCallback onActivate;
  final Widget Function(BuildContext context, bool focused) builder;
  final ParallaxShape shape;
  final BorderRadius? radius;
  final bool enabled;
  final bool autofocus;
  final String? semanticLabel;

  @override
  State<OnboardFocusable> createState() => _OnboardFocusableState();
}

class _OnboardFocusableState extends State<OnboardFocusable> {
  late final FocusNode _node = FocusNode(
    debugLabel: 'onboarding-${widget.cell.row}-${widget.cell.column}',
  );
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
    widget.controller.register(widget.cell, _node);
  }

  @override
  void didUpdateWidget(OnboardFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.cell != widget.cell) {
      oldWidget.controller.unregister(oldWidget.cell, _node);
      widget.controller.register(widget.cell, _node);
    }
  }

  void _onFocus() {
    if (mounted && _focused != _node.hasFocus) {
      setState(() => _focused = _node.hasFocus);
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent || !widget.enabled) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (isActivateKey(key) && event is! KeyRepeatEvent) {
      widget.onActivate();
      return KeyEventResult.handled;
    }
    final direction = switch (key) {
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      _ => null,
    };
    if (direction == null) return KeyEventResult.ignored;
    widget.controller.move(widget.cell, direction);
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    widget.controller.unregister(widget.cell, _node);
    _node.removeListener(_onFocus);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = RepaintBoundary(
      child: ParallaxFocus(
        focused: _focused,
        shape: widget.shape,
        radius: widget.radius,
        child: widget.builder(context, _focused),
      ),
    );
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: Focus(
        focusNode: _node,
        autofocus: widget.autofocus,
        canRequestFocus: widget.enabled,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onActivate : null,
          child: child,
        ),
      ),
    );
  }
}
