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
  bool _focusedHeightChanged = false;
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
    _focusedHeightChanged = false;
    _scheduleAlign();
  }

  void _scheduleAlign() {
    final run = ++_run;
    _animating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_ownsFocus || run != _run) return;
      final render = _rowContext!.findRenderObject();
      final position = Scrollable.maybeOf(_rowContext!)?.position;
      final viewport = render == null
          ? null
          : RenderAbstractViewport.maybeOf(render);
      if (render == null || position == null || viewport == null) {
        _animating = false;
        return;
      }
      // A DPAD step normally moves to another row already on screen. Forcing
      // every one of those rows to 30% of the viewport starts a scroll
      // animation and repaints the entire badge-heavy list on every press.
      // Only move the viewport when the new row actually approaches an edge.
      final top = viewport.getOffsetToReveal(render, 0).offset;
      final bottom = viewport.getOffsetToReveal(render, 1).offset;
      final current = position.pixels;
      const edge = 12.0;
      final oversized =
          render.paintBounds.height >= position.viewportDimension - edge * 2;
      final alignment = oversized
          ? ((top - current).abs() > edge ? 0.0 : null)
          : top < current - edge
          ? 0.1
          : bottom > current + edge
          ? 0.9
          : null;
      if (alignment == null) {
        // Invalidating callbacks does not stop the old scroll activity. A
        // reversal to an already visible row must hold this viewport position.
        if (position.isScrollingNotifier.value) position.jumpTo(current);
        _animating = false;
        return;
      }
      try {
        await Scrollable.ensureVisible(
          _rowContext!,
          alignment: alignment,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOutCubic,
        );
      } finally {
        if (run == _run) _animating = false;
      }
    });
  }

  void rowHeightChanged(int index, double delta) {
    if (!_ownsFocus || _index == null || index > _index!) {
      return;
    }
    if (index < _index!) _pendingDelta += delta;
    if (index == _index) _focusedHeightChanged = true;
    if (_correctionScheduled) return;
    _correctionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _correctionScheduled = false;
      final delta = _pendingDelta;
      final focusedHeightChanged = _focusedHeightChanged;
      _pendingDelta = 0;
      _focusedHeightChanged = false;
      // focusRow resets the accumulated delta when selection changes. If a
      // new row gains focus in this frame, apply only its subsequent deltas.
      if (!_ownsFocus || (delta == 0 && !focusedHeightChanged)) return;
      final position = Scrollable.maybeOf(_rowContext!)?.position;
      if (position == null || !position.hasContentDimensions) return;
      final resume = _animating;
      if (resume) ++_run;
      // Compensate only for rows ABOVE the selection. A zero-distance jump
      // cancels an active scroll and needlessly restarts it on badge updates.
      if (delta != 0) {
        position.jumpTo(
          (position.pixels + delta).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      }
      if (resume || focusedHeightChanged) {
        // A lazy focused row can be remounted by the correction. Align after
        // that layout. The focused row can also grow AFTER scrolling stops:
        // recheck its edges, leaving an already-visible row exactly in place.
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
          _focusedHeightChanged = false;
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
