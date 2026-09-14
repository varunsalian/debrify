import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/stremio_addon.dart';
import '../../services/youtube_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_theme_scope.dart';
import '../hero_trailer_backdrop.dart';

/// The full-screen ambient-trailer layer for the TV Discover two-pane. It sits
/// ABOVE the two-pane and renders the trailer the rail resolved, positioned so
/// it reads as a window inside the rail's backdrop box — then, after a few
/// seconds of watching, it promotes to fullscreen (like the Home hero board
/// takeover). Any key eases it back to the window, playback never stopping.
///
/// Glitch-free growth (the whole game on weak TV silicon): the video is laid
/// out at the full stage size ONCE and never re-fitted. A [FittedBox] scales
/// that fixed surface down into the rail rect while ambient and up to fullscreen
/// on promote — a paint-time transform, not a platform-view resize. A
/// [GlobalKey] pins the player element so the animation never remounts it.
class DiscoverTrailerStage extends StatefulWidget {
  /// The streams the rail resolved for the focused title; null → nothing plays.
  final ValueListenable<YoutubeResolvedStreams?> trailer;

  /// Shared loading flag — the rail sets it true while resolving; this layer
  /// drops it the instant the trailer produces frames.
  final ValueNotifier<bool> loading;

  /// Ambient volume (0–100; 0 = silent). Read once at mount — the rail only
  /// publishes streams after the settings load, so it's always current by then.
  final ValueListenable<double> volume;

  /// The enriched title behind the current trailer — drives the fullscreen
  /// takeover's name/meta overlay.
  final ValueListenable<StremioMeta?> meta;

  /// The rail's backdrop-box rect in this layer's coordinate space — the shape
  /// of the ambient window.
  final Rect railRect;

  /// Published promote progress (eased 0→1). The host recedes the two-pane with
  /// it so the cards dim out as the trailer takes over.
  final ValueNotifier<double>? takeover;

  /// Full-stage mode (the Discover glass-stage design): the video is rendered
  /// across the WHOLE canvas from the first frame — no rail window, no rounded
  /// clip — and sits UNDER the host's tint veils and panes in the host's Stack,
  /// so it reads as the stage art coming alive behind the tint. [railRect] is
  /// ignored and the internal loading pill is suppressed (the host shows the
  /// Home-style TRAILER/AMBIENT chip pair instead, driven by [loading] and
  /// [showing]).
  final bool fullStage;

  /// True while trailer frames are actually on screen — the host's AMBIENT
  /// chip reads it. Reset to false whenever the video unmounts.
  final ValueNotifier<bool>? showing;

  const DiscoverTrailerStage({
    super.key,
    required this.trailer,
    required this.loading,
    required this.volume,
    required this.meta,
    required this.railRect,
    this.takeover,
    this.fullStage = false,
    this.showing,
  });

  @override
  State<DiscoverTrailerStage> createState() => _DiscoverTrailerStageState();
}

class _DiscoverTrailerStageState extends State<DiscoverTrailerStage>
    with SingleTickerProviderStateMixin {

  /// Graceful settle back to the window — quicker than the promote-in.
  static const Duration _collapseDuration = Duration(milliseconds: 900);

  late final AnimationController _promote = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  double get _promoteT => Curves.easeInOutCubic.transform(_promote.value);

  /// The streams actually rendered. Normally mirrors [widget.trailer], but
  /// outlives a null during a graceful collapse so the video keeps playing while
  /// the window eases back — unmounted only once that collapse lands.
  YoutubeResolvedStreams? _held;
  bool _collapsing = false;

  /// The takeover overlay's title — held alongside [_held] so it survives (and
  /// fades out with) the graceful collapse rather than snapping away when the
  /// rail nulls the shared notifier. Refreshed on late enrichment via
  /// [_onMetaChanged]; cleared only when [_held] is.
  StremioMeta? _heldMeta;

  /// Pins the player element across rebuilds; replaced per URL so each title
  /// still spins a fresh engine.
  GlobalKey _backdropKey = GlobalKey();
  String? _backdropUrl;

  @override
  void initState() {
    super.initState();
    _held = widget.trailer.value;
    _heldMeta = widget.meta.value;
    widget.trailer.addListener(_onTrailerChanged);
    widget.meta.addListener(_onMetaChanged);
    _promote.addListener(_publishTakeover);
    _promote.addStatusListener(_onPromoteStatus);
    HardwareKeyboard.instance.addHandler(_onTakeoverKey);
    // A prior stage may have been torn down mid-takeover (e.g. a sub-threshold
    // resize dropped the two-pane) leaving the shared takeover notifier non-zero
    // — which would curtain the grid behind a dark scrim on remount. Publish a
    // clean 0 once this frame settles (a synchronous write here would mark the
    // already-built scrim dirty mid-build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _promote.value == 0) _publishTakeover();
    });
  }

  @override
  void didUpdateWidget(DiscoverTrailerStage old) {
    super.didUpdateWidget(old);
    if (!identical(old.trailer, widget.trailer)) {
      old.trailer.removeListener(_onTrailerChanged);
      widget.trailer.addListener(_onTrailerChanged);
      _collapsing = false;
      _held = widget.trailer.value;
    }
    if (!identical(old.meta, widget.meta)) {
      old.meta.removeListener(_onMetaChanged);
      widget.meta.addListener(_onMetaChanged);
      _heldMeta = widget.meta.value;
    }
  }

  @override
  void dispose() {
    widget.trailer.removeListener(_onTrailerChanged);
    widget.meta.removeListener(_onMetaChanged);
    HardwareKeyboard.instance.removeHandler(_onTakeoverKey);
    _promote.dispose();
    // NOTE: [showing] is deliberately NOT reset here — on a full host teardown
    // the notifier is disposed in the same pass and a deferred write would land
    // on a dead notifier. The one case where this stage unmounts while the host
    // lives (the sub-threshold-canvas fallback) resets it host-side, next to
    // its matching takeover reset.
    super.dispose();
  }

  void _publishTakeover() => widget.takeover?.value = _promoteT;

  bool _deferDuringBuild(VoidCallback callback) {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      return false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
    return true;
  }

  /// Adopt a non-null meta (new title, or a late enrichment for the current one).
  /// Never clears here — the overlay must outlive the shared notifier's null
  /// during a graceful collapse; [_heldMeta] drops only when [_held] does.
  void _onMetaChanged() {
    if (_deferDuringBuild(_onMetaChanged)) return;
    final m = widget.meta.value;
    if (m != null && mounted) setState(() => _heldMeta = m);
  }

  void _onTrailerChanged() {
    if (!mounted || _deferDuringBuild(_onTrailerChanged)) return;
    final next = widget.trailer.value;
    if (next != null) {
      _collapsing = false;
      setState(() => _held = next);
      return;
    }
    // Cleared (focus moved, suppressed, playback launched). Fullscreen takeover
    // is disabled so _promote is always 0 — just drop the video + meta.
    if (_promote.value > 0) {
      // Keep _held AND _heldMeta through the collapse so the video and its
      // title/meta overlay fade out together.
      _collapsing = true;
      _promote.animateBack(0.0, duration: _collapseDuration);
    } else {
      _promote.value = 0;
      widget.showing?.value = false;
      setState(() {
        _held = null;
        _heldMeta = null;
      });
    }
  }

  void _onPromoteStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && _collapsing) {
      _collapsing = false;
      if (mounted && widget.trailer.value == null) {
        widget.showing?.value = false;
        setState(() {
          _held = null;
          _heldMeta = null;
        });
      }
    }
  }

  void _onPlaying(bool playing) {
    if (!mounted) return;
    // Fullscreen takeover is disabled — the trailer stays windowed in the rail.
    // (The promote controller/overlay/scrim/chrome-dim remain wired but are
    // never driven; _promote sits at 0.)
    widget.showing?.value = playing;
    if (playing) widget.loading.value = false; // frames are up — drop the pill
  }

  /// Any key while promoted eases the trailer back into the window (still
  /// playing) — observe-only, so the key also does its normal job (e.g. DPAD
  /// still moves the grid). Mirrors the Home board's takeover-dismiss.
  bool _onTakeoverKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_promote.value <= 0.02) return false;
    _promote.animateBack(0.0, duration: _collapseDuration);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final streams = _held;
    if (streams == null || !streams.hasPlayable) return const SizedBox.shrink();
    if (streams.playUrl != _backdropUrl) {
      _backdropUrl = streams.playUrl;
      _backdropKey = GlobalKey();
    }
    // imageUrl null: while resolving/buffering the rail's own still (underneath
    // this layer) shows through the ambient window, and the video fades in over
    // it — no second still, no hard pop.
    final video = HeroTrailerBackdrop(
      key: _backdropKey,
      imageUrl: null,
      videoUrl: streams.playUrl,
      audioUrl: streams.audioUrl,
      enabled: true,
      imageBlurSigma: 0,
      videoBlurSigma: 0,
      startDelay: const Duration(milliseconds: 200),
      ambientVolume: widget.volume.value,
      onPlayingChanged: _onPlaying,
    );

    // Captured once at build: the AnimatedBuilder below runs per frame during
    // the promote tween, and a token lookup there would be per-tick work.
    final app = AppThemeScope.of(context);

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fullW = constraints.maxWidth;
          final fullH = constraints.maxHeight;
          if (!fullW.isFinite || !fullH.isFinite || fullW <= 0 || fullH <= 0) {
            return const SizedBox.shrink();
          }
          final fullRect = Offset.zero & Size(fullW, fullH);
          return Stack(
            fit: StackFit.expand,
            children: [
              AnimatedBuilder(
                animation: _promote,
                // RepaintBoundary: each video frame invalidates only the
                // texture's own layer, not the scrim/pill/overlay around it —
                // and UI repaints never re-record the video. Matches the Home
                // hero layer.
                child: RepaintBoundary(child: video),
                builder: (context, child) {
                  final t = _promoteT;
                  // Full-stage: the video owns the whole canvas from frame one
                  // (the host's veils above it supply the tint).
                  final rect = widget.fullStage
                      ? fullRect
                      : Rect.lerp(widget.railRect, fullRect, t)!;
                  final radius =
                      widget.fullStage ? 0.0 : lerpDouble(14.0, 0.0, t)!;
                  // Windowed render: the fixed full-size surface scaled by the
                  // FittedBox into the (rail-box) rect — the video never re-fits,
                  // only its paint transform changes. (Fullscreen takeover is
                  // disabled, so `t` stays 0 and `rect` is always the rail box.)
                  final surface = Positioned.fromRect(
                    rect: rect,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: fullW,
                          height: fullH,
                          child: child,
                        ),
                      ),
                    ),
                  );
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      surface,
                      // Legibility scrim over the promoted video — baked into a
                      // gradient's alpha (never an Opacity layer) so it costs no
                      // per-frame saveLayer on weak TV GPUs.
                      if (t > 0.001)
                        Positioned.fromRect(
                          rect: rect,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  app.fade(app.seeAll.bg, 0.30 * t),
                                  app.fade(app.seeAll.bg, 0.06 * t),
                                  app.fade(app.seeAll.bg, 0.42 * t),
                                ],
                                stops: const [0.0, 0.5, 1.0],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              // "Trailer" loading pill — pinned to the ambient window's corner.
              // Full-stage mode drops it: the host's TRAILER/AMBIENT chip pair
              // owns the status corner.
              if (!widget.fullStage)
                Positioned.fromRect(
                  rect: widget.railRect,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: ValueListenableBuilder<bool>(
                        valueListenable: widget.loading,
                        builder: (_, loading, __) =>
                            _TrailerLoadingPill(visible: loading),
                      ),
                    ),
                  ),
                ),
              // Fullscreen takeover identity — the kinetic lower-third. Reads
              // the held meta (not the raw notifier) so it survives and fades
              // out with the graceful collapse.
              if (_heldMeta != null)
                _TakeoverInfo(item: _heldMeta!, promote: _promote),
            ],
          );
        },
      ),
    );
  }
}

/// The takeover's kinetic lower-third — an exact port of the Home board's
/// [_buildTakeoverInfoOverlay]: while the film owns the screen its identity sits
/// bottom-left — a growing accent bar, a whispered kicker, a big uppercase
/// title, a `year · runtime · ★rating` line and the genres, each rising in a
/// staggered cascade timed to the mask-open ([t] 0→1). Purely informational
/// (IgnorePointer); every field degrades to nothing when absent.
class _TakeoverInfo extends StatelessWidget {
  final StremioMeta item;
  final Animation<double> promote;
  const _TakeoverInfo({required this.item, required this.promote});

  static const Color _accentLight = Color(0xFFC4B5FD);

  @override
  Widget build(BuildContext context) {
    // Everything below is built ONCE per title — the per-frame AnimatedBuilder
    // at the end only wraps these in cheap Opacity/Transform, never rebuilds the
    // text or a full-screen save layer (the Home board's rule for weak TV GPUs).
    final app = AppThemeScope.of(context);
    final rating = item.imdbRating;
    final runtime = item.runtimeDisplay;
    final genres = item.genres;

    final meta = <Widget>[];
    void sep() {
      if (meta.isNotEmpty) meta.add(_metaDot(app));
    }

    if (item.year != null && item.year!.isNotEmpty) {
      meta.add(_metaText(app, item.year!));
    }
    if (runtime != null && runtime.isNotEmpty) {
      sep();
      meta.add(_metaText(app, runtime));
    }
    if (rating != null) {
      sep();
      meta.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 17, color: app.home.focus),
          const SizedBox(width: 4),
          _metaText(app, rating.toStringAsFixed(1)),
        ],
      ));
    }

    final kicker = Text(
      'NOW PLAYING  ·  OFFICIAL TRAILER',
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 4,
        color: _accentLight,
        shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
      ),
    );
    final title = Text(
      item.name.toUpperCase(),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.poppins(
        fontSize: 46,
        fontWeight: FontWeight.w800,
        height: 0.98,
        letterSpacing: -0.5,
        color: app.core.tx,
        shadows: const [
          Shadow(color: Colors.black87, blurRadius: 18, offset: Offset(0, 3)),
        ],
      ),
    );
    final genresLine = (genres == null || genres.isEmpty)
        ? const SizedBox.shrink()
        : Text(
            genres.take(3).join('   •   ').toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
              color: app.fade(app.core.tx, 0.6),
              shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
            ),
          );

    final metaRow =
        meta.isEmpty ? null : Row(mainAxisSize: MainAxisSize.min, children: meta);
    final hasGenres = genres != null && genres.isNotEmpty;

    return AnimatedBuilder(
      animation: promote,
      builder: (context, __) {
        final t = Curves.easeInOutCubic.transform(promote.value);
        if (t <= 0.001) return const SizedBox.shrink();
        double seg(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
        double eo(double x) {
          final u = 1 - x;
          return 1 - u * u * u;
        }

        Widget rise(Widget w, double a, double b, {double dist = 14}) {
          final p = seg(a, b);
          return Opacity(
            opacity: p,
            child: Transform.translate(
              offset: Offset(0, (1 - eo(p)) * dist),
              child: w,
            ),
          );
        }

        final accentP = eo(seg(0.42, 0.72));
        final slideP = eo(seg(0.42, 0.78));

        return IgnorePointer(
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(52, 0, 48, 54),
              child: IntrinsicHeight(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Transform(
                      alignment: Alignment.bottomCenter,
                      transform: Matrix4.diagonal3Values(1, accentP, 1),
                      child: Container(
                        width: 5,
                        decoration: BoxDecoration(
                          borderRadius: app.shape.br(4),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [app.home.chromeAccent, _accentLight],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Transform.translate(
                      offset: Offset(-46 * (1 - slideP), 0),
                      child: Opacity(
                        opacity: seg(0.42, 0.6),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              rise(kicker, 0.44, 0.6, dist: 8),
                              const SizedBox(height: 12),
                              rise(title, 0.5, 0.8),
                              if (metaRow != null) ...[
                                const SizedBox(height: 14),
                                rise(metaRow, 0.66, 0.9, dist: 12),
                              ],
                              if (hasGenres) ...[
                                const SizedBox(height: 10),
                                rise(genresLine, 0.76, 1.0, dist: 10),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _metaText(AppTheme app, String s) => Text(
        s,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: app.fade(app.core.tx, 0.9),
          shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
        ),
      );

  Widget _metaDot(AppTheme app) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: app.fade(app.core.tx, 0.45),
            shape: BoxShape.circle,
          ),
        ),
      );
}

/// The Home hero's "Trailer" pill, themed to the rail's purple. Slides + fades
/// in while a trailer resolves/buffers; a TickerMode keeps the spinner idle (no
/// ticker) during the 99% of browsing it spends hidden.
class _TrailerLoadingPill extends StatelessWidget {
  final bool visible;
  const _TrailerLoadingPill({required this.visible});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, -0.25),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        child: TickerMode(
          enabled: visible,
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
            decoration: BoxDecoration(
              // Glassy page ink — fade 0.8 pins the legacy 0xCC alpha.
              color: app.fade(app.seeAll.bg, 0.8),
              borderRadius: app.shape.brPill,
              border: Border.all(color: app.seeAll.accentBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: app.fade(app.seeAll.accent, 0.18),
                  blurRadius: 18,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(app.seeAll.accent2),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  'Trailer',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: app.fade(app.core.tx, 0.85),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
