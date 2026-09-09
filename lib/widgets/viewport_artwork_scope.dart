import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Defers a band's artwork without deferring its layout or remote focus nodes.
/// Consumers keep their usual, identically sized placeholders until admitted.
/// Opt-in: artwork outside this scope retains its existing loading behavior.
class ViewportArtworkScope extends StatefulWidget {
  const ViewportArtworkScope({
    super.key,
    required this.child,
    this.focused = false,
  });

  final Widget child;
  final bool focused;

  static bool enabledOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_ArtworkAdmission>()
          ?.enabled ??
      true;

  @override
  State<ViewportArtworkScope> createState() => _ViewportArtworkScopeState();
}

class _ViewportArtworkScopeState extends State<ViewportArtworkScope> {
  bool _admitted = false;
  bool _pending = false;
  bool _routeVisible = true;

  void _scheduleCheck() {
    if (_admitted || _pending) return;
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      if (!mounted || _admitted) return;
      if (_routeVisible && (widget.focused || _nearViewport())) {
        setState(() => _admitted = true);
      } else {
        // Observe frames, never request them. This also handles sections
        // moving after late metadata changes without spinning while idle.
        _scheduleCheck();
      }
    });
  }

  bool _nearViewport() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return false;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return true;
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null || !position.hasContentDimensions) return false;
    final start = viewport.getOffsetToReveal(box, 0).offset;
    final extent = axisDirectionToAxis(position.axisDirection) == Axis.vertical
        ? box.size.height
        : box.size.width;
    // A small look-ahead, not the focus mounting window (which may span
    // several screens). Already admitted bands stay admitted until disposal.
    final margin = position.viewportDimension * .25;
    return start <= position.pixels + position.viewportDimension + margin &&
        start + extent >= position.pixels - margin;
  }

  @override
  Widget build(BuildContext context) {
    _routeVisible = ModalRoute.isCurrentOf(context) ?? true;
    _scheduleCheck();
    return _ArtworkAdmission(enabled: _admitted, child: widget.child);
  }
}

class _ArtworkAdmission extends InheritedWidget {
  const _ArtworkAdmission({required this.enabled, required super.child});

  final bool enabled;

  @override
  bool updateShouldNotify(_ArtworkAdmission oldWidget) =>
      enabled != oldWidget.enabled;
}
