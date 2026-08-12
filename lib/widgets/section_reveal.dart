import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_motion.dart';
import '../theme/app_theme_scope.dart';
import '../utils/platform_util.dart';

/// How a section arrives on screen.
///
/// The theme's [EntranceStyle] decides, with one exception: **under Debrify
/// Classic the MOUNT reveal is exactly the 350 ms fade-and-rise it has always
/// been.** Legacy's token value is `none`, which would mean "no entrance at
/// all" — and honouring it there would delete a shipped animation rather than
/// keep one. So the token is consulted only off legacy, which is the same
/// shape the focus widgets use. [startWhenVisible] is NOT covered by that pin;
/// see its own note.
class SectionReveal extends StatefulWidget {
  const SectionReveal({
    super.key,
    required this.child,
    this.index = 0,
    this.startWhenVisible = false,
    this.scaleFrom,
    this.alreadyRevealed = false,
    this.onRevealed,
  });

  final Widget child;

  /// Position in the sequence, for [EntranceStyle.stagger]. Ignored by every
  /// other style, and 0 is the honest default for a caller that has no idea
  /// where it sits.
  ///
  /// A [startWhenVisible] caller should leave this at 0: its sections are
  /// already sequenced by the scroll itself, and a per-index delay on top of
  /// that would hold a band back for no reason the eye can connect to.
  final int index;

  /// Wait until the section has actually scrolled into the viewport rather
  /// than animating on mount.
  ///
  /// Mount is the right trigger for a section that is on screen when the page
  /// opens. It is the WRONG one for a long scrolling page: a list that builds
  /// ahead — the Showcase detail page carries `cacheExtent: 1200` — mounts its
  /// lower sections while they are still a screenful below the fold, so a
  /// mount-triggered reveal plays to nobody and the section is sitting there
  /// finished by the time it is scrolled to.
  ///
  /// **The legacy pin does not apply in this mode.** That pin exists to keep
  /// an animation legacy ALREADY SHIPPED; a viewport-triggered reveal is new
  /// motion, so honouring the pin here would invent an entrance for the one
  /// look whose claim is that it has none — and one no token could switch off,
  /// since legacy's own `none` is the value the pin ignores.
  ///
  /// Off by default: the shipped caller reveals on mount and must keep doing
  /// exactly that.
  final bool startWhenVisible;

  /// Adds a scale to the arrival, from this value up to 1.
  ///
  /// Null — the default, and what the shipped caller uses — is fade and rise
  /// alone. Keep any value close to 1: this scales the LAID-OUT section, so a
  /// figure that reads as a gentle push forward on a 200pt row is a lurch on
  /// a full-width one.
  final double? scaleFrom;

  /// Start already arrived, with no animation.
  ///
  /// A lazy list DESTROYS the state of anything it scrolls far enough past —
  /// past `cacheExtent`, the element is garbage-collected — so "have I
  /// revealed yet" cannot live in this widget's own state if the answer must
  /// survive a scroll away and back. The caller that cares owns the memory
  /// and hands the answer back in; see [onRevealed].
  final bool alreadyRevealed;

  /// Fired when the reveal starts, so the caller can remember it.
  ///
  /// Called during a post-frame callback, never during build.
  final VoidCallback? onRevealed;

  /// Tags the reveal's own wrapper so a test can assert its absence without
  /// naming a widget type a section might legitimately contain itself.
  static const Key activeKey = ValueKey('section-reveal-active');

  @override
  State<SectionReveal> createState() => _SectionRevealState();
}

class _SectionRevealState extends State<SectionReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  Animation<double>? _scale;

  /// Per-step delay for a staggered arrival, capped so a long list does not
  /// take a second and a half to finish appearing.
  static const Duration _step = Duration(milliseconds: 55);
  static const int _maxSteps = 6;

  /// How far into the viewport the section's leading edge must come before it
  /// counts as arrived. Without it the reveal fires on the first pixel, which
  /// puts the whole animation in the sliver of screen below the fold — the
  /// section is finished before there is enough of it to look at. Clamped to
  /// the section's own height so a short one is not held to a bar taller than
  /// itself.
  static const double _entered = 64;

  bool _started = false;
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    final from = widget.scaleFrom;
    if (from != null) {
      _scale = Tween<double>(begin: from, end: 1).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
      );
    }

    if (widget.alreadyRevealed) {
      _started = true;
      _ctrl.value = 1;
      return;
    }

    if (!widget.startWhenVisible) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start();
      });
    }
  }

  @override
  void didUpdateWidget(SectionReveal old) {
    super.didUpdateWidget(old);
    // The caller can force an arrival — the Showcase ladder does it to the
    // band it is about to scroll to, so nothing measures that band through a
    // half-played transform. It SNAPS rather than animating: the point is to
    // be at rest before the frame ends.
    if (widget.alreadyRevealed && !old.alreadyRevealed && !_started) {
      _started = true;
      _ctrl.value = 1;
    }
  }

  void _start() {
    if (_started) return;
    _started = true;
    widget.onRevealed?.call();
    final app = AppThemeScope.of(context);
    final staggered = !app.isLegacy &&
        app.motion.entranceFor(PlatformUtil.isTelevision) ==
            EntranceStyle.stagger;
    final delay =
        staggered ? _step * widget.index.clamp(0, _maxSteps) : Duration.zero;
    if (delay == Duration.zero) {
      _ctrl.forward();
      return;
    }
    Future<void>.delayed(delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  /// While a section is waiting, re-check after every frame.
  ///
  /// A `ScrollPosition` listener is the obvious trigger and the wrong one. A
  /// section also enters the viewport when content ABOVE it changes height —
  /// a season swap replaces a tall episode rail with a one-line note, an
  /// accordion row collapses, an image finishes decoding — and Flutter
  /// reports that as a metrics change, not as a pixel notification. Listening
  /// for pixels alone leaves such a section at opacity 0 with nothing left
  /// that could ever wake it, which is the one failure this widget must not
  /// have.
  ///
  /// Rescheduling per frame is not a spin: nothing can move the section
  /// without producing a frame, so an idle app queues one callback and stops.
  /// Each pass is a single transform walk, and it ends for good on arrival.
  void _scheduleCheck() {
    if (_started || _pending) return;
    _pending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      if (!mounted || _started) return;
      _check();
      if (!_started) _scheduleCheck();
    });
  }

  /// Has the section crossed far enough into the viewport to be worth
  /// animating?
  ///
  /// Asked of the VIEWPORT rather than by comparing global coordinates:
  /// `getOffsetToReveal` is the same machinery `ensureVisible` uses, so it
  /// already accounts for the list's padding, its insets and which way it
  /// grows, none of which a hand-rolled `localToGlobal` comparison would.
  void _check() {
    if (_started || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    // Not laid out yet. Laying out REQUIRES a frame, and that frame will run
    // this check again — so there is nothing to do but wait, and no need for
    // the retry counter an unscheduled callback would have needed.
    if (box == null || !box.hasSize) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    // Not in a scrollable at all: there is no "scrolled into view" to wait
    // for, and waiting would mean never showing. Arrive now.
    if (viewport == null) {
      _start();
      return;
    }
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos == null || !pos.hasPixels || !pos.hasViewportDimension) return;
    // The scroll offset at which this section's leading edge would sit at the
    // viewport's leading edge. Subtract a viewport and it is entering at the
    // trailing edge instead, which is where it is first seen.
    final reveal = viewport.getOffsetToReveal(box, 0).offset;
    final entered = math.min(_entered, box.size.height);
    if (pos.pixels >= reveal - pos.viewportDimension + entered) _start();
  }

  /// Legacy keeps its shipped mount reveal — fade AND rise, 350 ms — which is
  /// why it has its own value here rather than being mapped onto one of the
  /// three token styles. Read from the scope rather than stored, so a theme
  /// change mid-life is picked up by the next section that builds.
  _Reveal _style() {
    final app = AppThemeScope.of(context);
    // See [startWhenVisible]: the pin protects motion legacy already has, and
    // there is none to protect in a mode legacy has never rendered.
    if (app.isLegacy) {
      return widget.startWhenVisible ? _Reveal.instant : _Reveal.fadeAndRise;
    }
    return switch (app.motion.entranceFor(PlatformUtil.isTelevision)) {
      EntranceStyle.none => _Reveal.instant,
      // `fadeUp` is a fade AND a rise — the name says so, and a fade with no
      // motion is indistinguishable from a slow image decode. What separates
      // it from `stagger` is that every section arrives at once.
      EntranceStyle.fadeUp => _Reveal.fadeAndRise,
      EntranceStyle.stagger => _Reveal.fadeAndRise,
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A section that arrives under a no-entrance look must be fully visible
    // immediately — including one that was mid-reveal when the theme changed.
    // Marked started as well as opened: a look with nothing to play has
    // nothing to watch for either, and every waiting section is per-frame
    // work on the app's most-scrolled page.
    if (_style() == _Reveal.instant) {
      if (_ctrl.value != 1) _ctrl.value = 1;
      _started = true;
      return;
    }
    if (widget.startWhenVisible) _scheduleCheck();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _style();
    if (style == _Reveal.instant) return widget.child;

    Widget out = FadeTransition(opacity: _opacity, child: widget.child);
    final scale = _scale;
    if (scale != null) out = ScaleTransition(scale: scale, child: out);
    // The rise is what makes a staggered arrival read as a SEQUENCE; a whole
    // page rising at once is what makes a page look like it is loading. So
    // `fadeUp` gets the fade alone.
    return KeyedSubtree(
      key: SectionReveal.activeKey,
      child: SlideTransition(position: _slide, child: out),
    );
  }
}

/// What this widget actually does, as distinct from what the token names.
///
/// The token values map onto two behaviours here — arrive, or already be
/// there — and the third dimension (whether the arrival is staggered) is a
/// delay rather than a different animation. Legacy needs a value no token
/// names, so the mapping gets a type rather than a chain of booleans.
enum _Reveal { instant, fadeAndRise }
