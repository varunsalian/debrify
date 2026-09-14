import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Keeps DPAD focus anchored as asynchronous badges/images change row heights.
/// The list still owns its controller, pagination and pointer scrolling.
class SourceListScrollAnchor extends StatefulWidget {
  const SourceListScrollAnchor({super.key, required this.child});
  final Widget child;

  static SourceListScrollAnchorState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SourceAnchorScope>()?.owner;

  @override
  State<SourceListScrollAnchor> createState() => SourceListScrollAnchorState();
}

class SourceListScrollAnchorState extends State<SourceListScrollAnchor> {
  FocusNode? _focus;
  BuildContext? _rowContext;
  int? _index;
  bool _manual = false;
  bool _animating = false;
  int _run = 0;
  double _pendingDelta = 0;
  bool _correctionScheduled = false;

  bool get _ownsFocus =>
      mounted &&
      !_manual &&
      (_focus?.hasFocus ?? false) &&
      (_rowContext?.mounted ?? false);

  void focusRow(BuildContext context, FocusNode focus, int index) {
    _focus = focus;
    _rowContext = context;
    _index = index;
    _manual = false;
    _pendingDelta = 0;
    _scheduleAlign();
  }

  void _scheduleAlign() {
    final run = ++_run;
    _animating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_ownsFocus || run != _run) return;
      try {
        await Scrollable.ensureVisible(
          _rowContext!,
          alignment: 0.3,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
        );
      } finally {
        if (run == _run) _animating = false;
      }
    });
  }

  void rowHeightChanged(int index, double delta) {
    if (!_ownsFocus ||
        _index == null ||
        index > _index! ||
        (index == _index && !_animating)) {
      return;
    }
    if (index < _index!) _pendingDelta += delta;
    if (_correctionScheduled) return;
    _correctionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _correctionScheduled = false;
      final delta = _pendingDelta;
      _pendingDelta = 0;
      // focusRow resets the accumulated delta when selection changes. If a
      // new row gains focus in this frame, apply only its subsequent deltas.
      if (!_ownsFocus) return;
      final position = Scrollable.maybeOf(_rowContext!)?.position;
      if (position == null || !position.hasContentDimensions) return;
      final resume = _animating;
      if (resume) ++_run;
      position.jumpTo(
        (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      if (resume) {
        // A lazy focused row can be remounted by the correction. Align after
        // that layout and invalidate the old animation's completion callback.
        _scheduleAlign();
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    });
  }

  @override
  Widget build(BuildContext context) => _SourceAnchorScope(
    owner: this,
    child: NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            ((notification is ScrollStartNotification &&
                    notification.dragDetails != null) ||
                (notification is UserScrollNotification &&
                    notification.direction != ScrollDirection.idle))) {
          _manual = true;
          _animating = false;
          ++_run;
          _pendingDelta = 0;
        }
        return false;
      },
      child: widget.child,
    ),
  );
}

class _SourceAnchorScope extends InheritedWidget {
  const _SourceAnchorScope({required this.owner, required super.child});
  final SourceListScrollAnchorState owner;
  @override
  bool updateShouldNotify(_SourceAnchorScope oldWidget) =>
      owner != oldWidget.owner;
}

/// Reports deltas only after the first layout; the owner defers scroll writes.
class SourceRowHeightObserver extends SingleChildRenderObjectWidget {
  const SourceRowHeightObserver({
    super.key,
    required this.onChanged,
    required super.child,
  });
  final ValueChanged<double> onChanged;
  @override
  RenderSourceRowHeightObserver createRenderObject(BuildContext context) =>
      RenderSourceRowHeightObserver(onChanged);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderSourceRowHeightObserver renderObject,
  ) {
    renderObject.onChanged = onChanged;
  }
}

class RenderSourceRowHeightObserver extends RenderProxyBox {
  RenderSourceRowHeightObserver(this.onChanged);
  ValueChanged<double> onChanged;
  double? _lastHeight;
  @override
  void performLayout() {
    super.performLayout();
    final previous = _lastHeight;
    _lastHeight = size.height;
    if (previous != null && previous != size.height) {
      onChanged(size.height - previous);
    }
  }
}
