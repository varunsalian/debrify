import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/platform_util.dart';

/// How a section arrives on screen.
///
/// The theme's [EntranceStyle] decides, with one exception: **under Debrify
/// Classic this is exactly the 350 ms fade-and-rise it has always been.**
/// Legacy's token value is `none`, which would mean "no entrance at all" — and
/// honouring it here would delete a shipped animation rather than keep one. So
/// the token is consulted only off legacy, which is the same shape the focus
/// widgets use.
class HomeSectionReveal extends StatefulWidget {
  const HomeSectionReveal({
    super.key,
    required this.child,
    this.index = 0,
  });

  final Widget child;

  /// Position in the sequence, for [EntranceStyle.stagger]. Ignored by every
  /// other style, and 0 is the honest default for a caller that has no idea
  /// where it sits.
  ///
  /// **Today every live caller is at 0**, because this widget has exactly one
  /// — a single card — so `stagger` currently renders identically to
  /// `fadeUp`. That is a missing consumer, not a broken token: the moment the
  /// home board's sections adopt this widget and pass their positions, Deep
  /// Field's arrival becomes a sequence with no change here.
  final int index;

  @override
  State<HomeSectionReveal> createState() => _HomeSectionRevealState();
}

class _HomeSectionRevealState extends State<HomeSectionReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  /// Per-step delay for a staggered arrival, capped so a long list does not
  /// take a second and a half to finish appearing.
  static const Duration _step = Duration(milliseconds: 55);
  static const int _maxSteps = 6;

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

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  void _start() {
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

  /// Legacy keeps its shipped reveal — fade AND rise, 350 ms — which is why
  /// it has its own value here rather than being mapped onto one of the three
  /// token styles. Read from the scope rather than stored, so a theme change
  /// mid-life is picked up by the next section that builds.
  _Reveal _style() {
    final app = AppThemeScope.of(context);
    if (app.isLegacy) return _Reveal.fadeAndRise;
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
    if (_style() == _Reveal.instant && _ctrl.value != 1) {
      _ctrl.value = 1;
    }
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

    final faded = FadeTransition(opacity: _opacity, child: widget.child);
    // The rise is what makes a staggered arrival read as a SEQUENCE; a whole
    // page rising at once is what makes a page look like it is loading. So
    // `fadeUp` gets the fade alone.
    return SlideTransition(position: _slide, child: faded);
  }
}

/// What this widget actually does, as distinct from what the token names.
///
/// The token values map onto two behaviours here — arrive, or already be
/// there — and the third dimension (whether the arrival is staggered) is a
/// delay rather than a different animation. Legacy needs a value no token
/// names, so the mapping gets a type rather than a chain of booleans.
enum _Reveal { instant, fadeAndRise }
