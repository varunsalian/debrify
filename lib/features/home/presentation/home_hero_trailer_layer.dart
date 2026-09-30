import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../models/youtube_resolved_streams.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../widgets/hero_trailer_backdrop.dart';
import 'home_hero_surface.dart';
import '../../../ui/core/trailer_indicators.dart';
import '../../../ui/core/spotlight_search_button.dart';

/// Full-board ambient trailer layer (TV Home board only). Sits ABOVE the hero +
/// rows as an [IgnorePointer] overlay and paints the trailer into a right-
/// anchored REGION of the hero band (see [homeHeroTrailerRegionRect]) — a live,
/// near-untouched picture beside the title, its edges slim-feathered into the
/// darkened stage. The region fades in
/// when a trailer starts resolving and out when it clears; the title/backdrop
/// underneath stay put (no crossfade-to-fullscreen), so the hero keeps its
/// identity. [HeroTrailerBackdrop] cover-fills the region (clipped), and a
/// [GlobalKey] pins the player element across rebuilds; it's replaced per URL so
/// each title still spins a fresh engine.
///
/// Any hero change tears the trailer down (the host nulls the listenable → the
/// video unmounts and the region fades out). A trailer that stops for content
/// playback drops on its own via [HeroTrailerBackdrop.onPlayingChanged](false).
class HomeHeroTrailerLayer extends StatefulWidget {
  final ValueListenable<YoutubeResolvedStreams?> trailer;

  /// The hero spotlight's height — sets the region's height (see
  /// [homeHeroTrailerRegionRect]).
  final double heroHeight;

  /// Ambient volume 0–100 (0 = play silently).
  final double volume;

  /// Host "a trailer is resolving/buffering" flag — the region fades in on it
  /// (so it's already there when frames land) and hosts the "Trailer" pill.
  final ValueListenable<bool> loading;

  /// Relayed [HeroTrailerBackdrop.onPlayingChanged] (host pill + lights-off
  /// veils).
  final ValueChanged<bool>? onPlayingChanged;

  /// Retained (unused) takeover hook — the fullscreen promote is gone in the
  /// boxed layout, but the host still wires a notifier; kept for compatibility.
  final ValueNotifier<double>? takeover;

  /// CANVAS mode: the region is the WHOLE board — the underlay hole (which
  /// simply follows this widget's laid-out rect) becomes the full canvas —
  /// and the boxed edge feathers are skipped; the Canvas stage paints its own
  /// scrims ABOVE this layer instead.
  final bool fullBleed;

  /// The HOST's TV verdict (probe-augmented — see main.dart), not
  /// `PlatformUtil.isTelevision`: the two can disagree on an Android TV whose
  /// warm-up probe failed, and the chip corner must follow the same authority
  /// as the layout it sits in.
  final bool isTelevision;

  const HomeHeroTrailerLayer({
    super.key,
    required this.trailer,
    required this.heroHeight,
    required this.volume,
    required this.loading,
    required this.isTelevision,
    this.onPlayingChanged,
    this.takeover,
    this.fullBleed = false,
  });

  @override
  State<HomeHeroTrailerLayer> createState() => _HomeHeroTrailerLayerState();
}

class _HomeHeroTrailerLayerState extends State<HomeHeroTrailerLayer> {
  /// Pins the backdrop's element so its engine/texture survive rebuilds.
  /// Replaced per trailer URL so each title still gets a fresh engine.
  GlobalKey _backdropKey = GlobalKey();
  String? _backdropUrl;

  /// The streams actually being rendered — mirrors `widget.trailer`. Held in
  /// state so a `setState` drives the video mount/unmount as titles change.
  YoutubeResolvedStreams? _held;

  /// True once the video is actually producing frames (not merely resolving /
  /// buffering). The edge-feathers fade in ONLY on this — so while a trailer
  /// loads the poster shows through the region untouched, and the tint dissolve
  /// appears together with the moving picture, never over a still. Reset on any
  /// trailer change so a new title starts clean.
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _held = widget.trailer.value;
    widget.trailer.addListener(_onTrailerChanged);
  }

  @override
  void didUpdateWidget(HomeHeroTrailerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.trailer, widget.trailer)) {
      oldWidget.trailer.removeListener(_onTrailerChanged);
      widget.trailer.addListener(_onTrailerChanged);
      // We render from _held (not the listenable directly), so re-sync it to
      // the new notifier's current value.
      _held = widget.trailer.value;
      _playing = false;
    }
  }

  @override
  void dispose() {
    widget.trailer.removeListener(_onTrailerChanged);
    super.dispose();
  }

  void _onTrailerChanged() {
    if (!mounted) return;
    // A new trailer arrives (or a null drops it). Either way the feathers go
    // back to hidden until THIS video reports frames — the new poster shows
    // through cleanly meanwhile.
    setState(() {
      _held = widget.trailer.value;
      _playing = false;
    });
  }

  void _onPlaying(bool playing) {
    // Relay to the host — drives the colour bleed under the rows and clears the
    // "Trailer" pill once frames are up.
    widget.onPlayingChanged?.call(playing);
    // Drive the feathers locally: they appear with the picture, not before.
    if (_playing != playing && mounted) setState(() => _playing = playing);
  }

  @override
  Widget build(BuildContext context) {
    final streams = _held;
    if (streams != null &&
        streams.hasPlayable &&
        streams.playUrl != _backdropUrl) {
      _backdropUrl = streams.playUrl;
      _backdropKey = GlobalKey();
    }
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boardH = constraints.maxHeight;
          final boardW = constraints.maxWidth;
          if (!boardH.isFinite ||
              boardH <= 0 ||
              !boardW.isFinite ||
              boardW <= 0) {
            return const SizedBox.shrink();
          }
          final heroH = widget.heroHeight.clamp(0.0, boardH);
          final region = widget.fullBleed
              ? (Offset.zero & Size(boardW, boardH))
              : homeHeroTrailerRegionRect(boardW, heroH);
          if (region == null) return const SizedBox.shrink();

          final hasVideo = streams != null && streams.hasPlayable;
          // Listening to `loading` keeps the region (and its pill) up through
          // the resolve gap so frames land inside it, not a pop.
          return ValueListenableBuilder<bool>(
            valueListenable: widget.loading,
            builder: (context, loading, _) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  // No region-level fade wrapper: it was redundant (`show`
                  // false implies streams == null — the video unmounts
                  // instantly regardless — and the feathers/pill carry their
                  // own fades), and the underlay trailer's punch-through hole
                  // must not sit under an Opacity (its saveLayer would break
                  // the BlendMode.clear against the translucent surface).
                  Positioned.fromRect(
                    rect: region,
                    child: _buildRegion(
                      hasVideo ? streams : null,
                      loading,
                      _playing,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// The trailer region — NO frame; the video cover-fills a right-anchored
  /// slab whose edges melt into the stage via SLIM neutral feathers (see
  /// [homeHeroTrailerVideoFeatherFrac] for the tuned balance: heavy feathers
  /// read as bleed, none at all read as a legacy boxed player). The right
  /// edge bleeds off screen.
  ///
  /// Under the feathers sits [homeHeroTrailerBrightnessLift] — a single flat
  /// low-alpha white fill that lifts the ambient video slightly (trailers
  /// are graded dark; a small lift keeps the region alive).
  ///
  /// Weak-TV safe: all overlays are constant fills/baked gradients (no
  /// per-frame ShaderMask / saveLayer), and in underlay mode they composite
  /// over the punch-through hole onto the native video. The video keeps its
  /// own RepaintBoundary so its texture updates never repaint the overlays
  /// or pill.
  ///
  /// [playing] gates the overlays: while the trailer only resolves/buffers
  /// the poster shows through the region untouched, then they fade in with
  /// the picture.
  Widget _buildRegion(
    YoutubeResolvedStreams? streams,
    bool loading,
    bool playing,
  ) {
    final app = AppThemeScope.of(context);
    return ClipRect(
      // Clip the cover-crop so the scaled-up video can't spill left over the
      // title text; the right side simply bleeds off the screen edge.
      child: Stack(
        fit: StackFit.expand,
        children: [
          // imageUrl null: the hero backdrop shows through the region while
          // resolving, and the video fades in over it — no black plate.
          if (streams != null)
            RepaintBoundary(
              child: HeroTrailerBackdrop(
                key: _backdropKey,
                imageUrl: null,
                videoUrl: streams.playUrl,
                audioUrl: streams.audioUrl,
                enabled: true,
                imageBlurSigma: 0,
                videoBlurSigma: 0,
                startDelay: const Duration(milliseconds: 300),
                ambientVolume: widget.volume,
                onPlayingChanged: _onPlaying,
              ),
            ),
          // Overlays on the picture, gated on [playing] so the poster
          // underneath is never touched while the trailer resolves:
          // the flat brightness lift first, then the SLIM neutral edge
          // feathers OVER it — so the melt still lands on the stage's true
          // near-black, not a lifted one.
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: playing ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOut,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: homeHeroTrailerBrightnessLift),
                  // Boxed-mode edge melts only — Canvas paints its own
                  // constant scrims above this whole layer instead.
                  if (!widget.fullBleed) ...[
                    // Left: melt into the darkened text zone.
                    homeHeroEdgeFeather(
                      Alignment.centerLeft,
                      Alignment.centerRight,
                      app.home.bg,
                      homeHeroTrailerVideoFeatherFrac,
                    ),
                    // Top: soften the upper edge into the hero.
                    homeHeroEdgeFeather(
                      Alignment.topCenter,
                      Alignment.bottomCenter,
                      app.home.bg,
                      0.10,
                    ),
                    // Bottom: melt down into the darkened rows.
                    homeHeroEdgeFeather(
                      Alignment.bottomCenter,
                      Alignment.topCenter,
                      app.home.bg,
                      0.20,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            top: _chipTop(context),
            right: _chipRight,
            child: HomeHeroTrailerLoadingPill(visible: loading),
          ),
          // Once frames are up the loading pill yields to the AMBIENT chip —
          // a quiet state affordance so the motion reads as intentional, not
          // a stray video. Same corner, so the two hand over in place.
          Positioned(
            top: _chipTop(context),
            right: _chipRight,
            child: HomeHeroAmbientChip(visible: playing && !loading),
          ),
        ],
      ),
    );
  }

  /// The status corner, per input. TV keeps the shipped 16/22 — it sits
  /// inside a SafeArea and owns the whole corner. The touch Spotlight shell
  /// (phone AND tablet — both float the search button over a full-bleed
  /// board) is `SafeArea(top: false)` — the shipped corner put the chip both
  /// UNDER the status bar and UNDER that button (the clipped "AMBIE…").
  /// Cleared to the button's left, vertically centred on it.
  double _chipTop(BuildContext context) =>
      widget.isTelevision ? 16.0 : MediaQuery.viewPaddingOf(context).top + 16.0;

  double get _chipRight => widget.isTelevision
      ? 22.0
      : SpotlightSearchButton.rightInset + SpotlightSearchButton.diameter + 12;
}
