import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../utils/dominant_color.dart';
import '../../utils/platform_util.dart';

/// A cover-colored halo, independent of the theme's normal focus indicator.
/// Only active tiles request a tiny color decode; stale completions are ignored.
class CollectionFocusGlow extends StatefulWidget {
  final bool active;
  final bool enabled;
  final String? imageUrl;
  final double radius;
  final Widget child;

  const CollectionFocusGlow({
    super.key,
    required this.active,
    required this.enabled,
    this.imageUrl,
    this.radius = 10,
    required this.child,
  });

  @override
  State<CollectionFocusGlow> createState() => _CollectionFocusGlowState();
}

class _CollectionFocusGlowState extends State<CollectionFocusGlow> {
  Color? _color;
  String? _requested;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(CollectionFocusGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageUrl != oldWidget.imageUrl) {
      _generation++;
      _color = null;
      _requested = null;
    }
    _resolve();
  }

  void _resolve() {
    final url = widget.imageUrl;
    if (!widget.active || !widget.enabled || url == null || url == _requested) {
      return;
    }
    _requested = url;
    final generation = ++_generation;
    extractDominantColor(CachedNetworkImageProvider(url)).then((color) {
      if (!mounted || generation != _generation || color == null) return;
      setState(() => _color = color);
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = _color ?? Theme.of(context).colorScheme.primary;
    if (PlatformUtil.isAndroidTvCached) {
      if (!widget.enabled) return widget.child;
      // Cache the blurred halo independently of the card. Animating its
      // opacity avoids repainting an evolving blurred shadow on every focus
      // frame. Keep the same color, geometry and fully focused appearance.
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -64,
            bottom: -64,
            left: -64,
            right: -64,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: widget.active ? 1 : 0,
                duration:
                    (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                child: RepaintBoundary(
                  // Include the blur's overflow in the raster-cache bounds.
                  child: Padding(
                    padding: const EdgeInsets.all(64),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(widget.radius),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.65),
                            blurRadius: 28,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          widget.child,
        ],
      );
    }
    return AnimatedContainer(
      duration: (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        boxShadow: [
          BoxShadow(
            color: color.withValues(
              alpha: widget.active && widget.enabled ? 0.65 : 0,
            ),
            blurRadius: 28,
            spreadRadius: 3,
          ),
        ],
      ),
      child: widget.child,
    );
  }
}
