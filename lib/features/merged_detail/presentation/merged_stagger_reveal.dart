import 'dart:async';
import 'package:flutter/material.dart';
// ── Small presentational widgets ───────────────────────────────────────────

/// One-shot entrance for a hero-block item: after [delayMs], fades up from
/// transparent while rising 12px, so the detail header assembles itself around
/// the shared-element poster flight instead of popping in fully formed.
///
/// Cheap and TV-safe: a single 340ms opacity+translate on a small widget, run
/// once on mount (the controller never resets, so metadata-load rebuilds don't
/// replay it). [enabled] is false under OS reduced-motion — the child shows
/// immediately with no controller. Late-arriving sections (their own first
/// mount happens when enrichment lands) simply fade in on arrival.
class _StaggerReveal extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final bool enabled;

  const _StaggerReveal({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.enabled = true,
  });

  @override
  State<_StaggerReveal> createState() => _StaggerRevealState();
}

class _StaggerRevealState extends State<_StaggerReveal>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _timer = Timer(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller?.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return widget.child;
    return AnimatedBuilder(
      animation: c,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

typedef MergedStaggerReveal = _StaggerReveal;

const mergedStaggerRevealConstructor = _StaggerReveal.new;
