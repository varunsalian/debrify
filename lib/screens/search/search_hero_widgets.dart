part of '../search_screen.dart';

class _HeroSpotlight extends StatefulWidget {
  final StremioMeta item;
  final String? background;
  final String? description;
  final bool isTelevision;
  final double height;
  final int artworkCacheWidth;
  final int? artworkCacheHeight;

  /// IMDb rating to show in the meta line (resolved by the host from the item
  /// or its enriched /meta details, since catalog list items often omit it).
  final double? rating;

  /// Runtime label ("2h 47m") for the meta line — resolved by the host from the
  /// item or its enriched /meta details (catalog rows usually omit it).
  final String? runtime;

  /// Title-treatment artwork URL (Cinemeta `logo`) — rendered in place of the
  /// text title when present, with the text as loading/error fallback. Resolved
  /// by the host from the item or its enriched /meta details.
  final String? logo;

  /// Compact layout for the Search tab: smaller title, single-line plot and
  /// tighter spacing so the whole spotlight fits a short strip without pushing
  /// the results off-screen.
  final bool compact;

  /// True on the TV Home hero when the ambient trailer plays in a blended region
  /// on the RIGHT (see [_HeroTrailerLayer]). The spotlight then keeps its
  /// backdrop and text (no crossfade) but caps the identity block at the
  /// region's left edge so the title and the crisp trailer sit side by side.
  final bool boxedTrailer;

  /// Dominant color of the focused title's poster (host-extracted, debounced).
  /// Blended softly into the scrim + an ambient glow so the whole hero takes
  /// on the title's mood. Null = neutral (no tint yet / colorless art).
  final ValueListenable<Color?>? tint;

  /// Host-driven "a trailer is on its way" flag — shows the corner pill from
  /// resolve-start until frames land (or the attempt dies).
  final ValueListenable<bool>? trailerLoading;

  /// Host-driven "trailer frames are on screen" flag. The trailer video plays
  /// in the board layer BENEATH this spotlight (see [_HeroTrailerLayer]), so
  /// the static backdrop image fades out on this signal to reveal it — that
  /// fade IS the image→video crossfade. The Ken Burns drift also freezes
  /// while hidden (no point re-rasterising an invisible layer every frame).
  final ValueListenable<bool>? trailerShowing;

  /// Host-driven "an IPTV favourite has taken the boxed video region" signal
  /// (see [_HeroLiveLayer]). [item]/[background]/[tint] all belong to the
  /// previously-focused CATALOG title — once an unrelated live channel is
  /// playing in the region, this spotlight's colour field and identity block
  /// (title/meta/plot, all about that stale catalog title) fade out rather
  /// than sit there describing something that isn't playing. Null outside
  /// Home (no IPTV favourites row to trigger it).
  final ValueListenable<bool>? liveTakeover;

  const _HeroSpotlight({
    required this.item,
    required this.background,
    required this.description,
    required this.isTelevision,
    required this.height,
    required this.artworkCacheWidth,
    required this.artworkCacheHeight,
    this.rating,
    this.runtime,
    this.logo,
    this.compact = false,
    this.boxedTrailer = false,
    this.tint,
    this.trailerLoading,
    this.trailerShowing,
    this.liveTakeover,
  });

  @override
  State<_HeroSpotlight> createState() => _HeroSpotlightState();
}

class _HeroSpotlightState extends State<_HeroSpotlight>
    with TickerProviderStateMixin {
  // Slow, endless Ken Burns breathe on the backdrop — a pure bottom-anchored
  // zoom so a static poster reads as cinematic. It's a Transform on an
  // already-rasterised image (one saveLayer under the existing ShaderMask
  // re-rastered per frame), which is cheap; the long duration keeps the motion
  // barely-there.
  late final AnimationController _ken = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 22),
  );

  // Short cascade for the text block when the spotlighted TITLE changes: badge,
  // title, meta and plot slide-fade in with tiny staggers instead of hard-
  // swapping. One controller, small text region, ~260ms one-shot — cheap even
  // while DPAD focus is flying across a row.
  late final AnimationController _textFx = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1.0, // first build shows settled text; cascades start on change
  );

  // Motion gates, split so TV keeps the cheap effect without the dear one:
  //  • _textOk — the text cascade: transform + opacity over a small text
  //    block, fine everywhere INCLUDING TV (it was disabled there wholesale,
  //    which left the hero dead on the platform it was designed for).
  //  • _kenOk — the Ken Burns drift: re-rasterises the backdrop layer every
  //    frame while it runs, so on TV it's allowed only in boxed mode, where
  //    the target is a region-sized layer with NO ShaderMask saveLayer. The
  //    full-bleed masked path (Search-tab hero) stays still on TV.
  // Reduced-motion turns both off.
  bool _kenOk = true;
  bool _textOk = true;

  /// Whether video currently occupies the art's rect — a catalog trailer OR
  /// an IPTV live takeover. Both must freeze the Ken Burns drift: the live
  /// path in particular flips [trailerShowing] false (it *replaces* the
  /// trailer), so keying off the trailer alone would RESUME the drift under
  /// live video and re-raster the covered art layer every frame for nothing.
  bool get _artCovered =>
      widget.trailerShowing?.value == true ||
      widget.liveTakeover?.value == true;

  @override
  void initState() {
    super.initState();
    widget.trailerShowing?.addListener(_onHeroCoverChanged);
    widget.liveTakeover?.addListener(_onHeroCoverChanged);
  }

  /// Freeze the Ken Burns drift while video covers the image — its layer
  /// would otherwise keep re-rasterising every frame for nothing — and
  /// resume it (from where it left off) when the image comes back.
  void _onHeroCoverChanged() {
    if (!mounted || !_kenOk) return;
    if (_artCovered) {
      _ken.stop();
    } else if (!_ken.isAnimating) {
      _ken.repeat(reverse: true);
    }
  }

  void _syncMotionGates() {
    final reduced = MediaQuery.of(context).disableAnimations;
    _textOk = !reduced;
    _kenOk = !reduced && (!widget.isTelevision || widget.boxedTrailer);
    if (!_kenOk) {
      _ken.stop();
      // Land flat, not frozen mid-zoom (matters when reduced-motion flips
      // on while the drift is running).
      _ken.value = 0.0;
    } else if (!_ken.isAnimating && !_artCovered) {
      _ken.repeat(reverse: true);
    }
    if (!_textOk) _textFx.value = 1.0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionGates();
  }

  @override
  void didUpdateWidget(_HeroSpotlight old) {
    super.didUpdateWidget(old);
    if (!identical(old.trailerShowing, widget.trailerShowing)) {
      old.trailerShowing?.removeListener(_onHeroCoverChanged);
      widget.trailerShowing?.addListener(_onHeroCoverChanged);
    }
    if (!identical(old.liveTakeover, widget.liveTakeover)) {
      old.liveTakeover?.removeListener(_onHeroCoverChanged);
      widget.liveTakeover?.addListener(_onHeroCoverChanged);
    }
    if (old.boxedTrailer != widget.boxedTrailer) _syncMotionGates();
    if (old.item.id != widget.item.id && _textOk) {
      _textFx.forward(from: 0);
    }
  }

  @override
  void dispose() {
    widget.trailerShowing?.removeListener(_onHeroCoverChanged);
    widget.liveTakeover?.removeListener(_onHeroCoverChanged);
    _ken.dispose();
    _textFx.dispose();
    super.dispose();
  }

  /// Legibility wrapper for the left tint SCRIM and the identity TEXT: in
  /// [boxedTrailer] mode they must STAY while the trailer plays (only the
  /// backdrop image yields — see [_fadeBackdropForTrailer]), so this is a pass-
  /// through there. No-op too when the surface runs no trailers.
  Widget _maybeFadeForTrailer(Widget child) {
    final showing = widget.trailerShowing;
    if (showing == null || widget.boxedTrailer) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: showing,
      builder: (context, on, kid) => AnimatedOpacity(
        opacity: on ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOut,
        child: kid,
      ),
      child: child,
    );
  }

  /// Fades the backdrop IMAGE out while the trailer plays (boxedTrailer). The
  /// colour field beneath ([_trailerColorField]) takes its place, so the left of
  /// the hero becomes a rich tint wash instead of a cropped half-poster beside
  /// the trailer. Timing mirrors the 650ms crossfade the video uses internally.
  Widget _fadeBackdropForTrailer(Widget child) {
    final showing = widget.trailerShowing;
    if (showing == null || !widget.boxedTrailer) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: showing,
      builder: (context, on, kid) => AnimatedOpacity(
        opacity: on ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOut,
        child: kid,
      ),
      child: child,
    );
  }

  /// Boxed-mode counterpart of [_maybeFadeForTrailer] for the SECONDARY
  /// identity lines only (meta chips + plot): while the ambient trailer plays
  /// they fade away and the title/logo stays — the Netflix/Nuvio "logo holds
  /// the stage" move. Safe by construction: the identity block sits left of
  /// the trailer region, so this Opacity never covers the underlay's
  /// punch-through hole. Pass-through outside boxed mode (the full-block fade
  /// above already handles that layout).
  Widget _fadeMetaForTrailer(Widget child) {
    final showing = widget.trailerShowing;
    if (showing == null || !widget.boxedTrailer) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: showing,
      builder: (context, on, kid) => AnimatedOpacity(
        opacity: on ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOut,
        child: kid,
      ),
      child: child,
    );
  }

  /// An IPTV favourite has taken the boxed video region ([liveTakeover]) —
  /// unlike the catalog trailer, that video has NOTHING to do with [item], so
  /// its colour field / identity text must actually disappear rather than
  /// stay put (the invariant [_maybeFadeForTrailer]/[_fadeMetaForTrailer] rely
  /// on — "the text is still about what's playing" — doesn't hold here).
  /// No-op when the surface never runs IPTV favourites.
  Widget _fadeForLiveTakeover(Widget child) {
    final live = widget.liveTakeover;
    if (live == null) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: live,
      builder: (context, on, kid) => AnimatedOpacity(
        opacity: on ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOut,
        child: kid,
      ),
      child: child,
    );
  }

  /// The hero's colour STAGE (boxed mode): a diagonal wash in the focused
  /// title's extracted tint plus a soft glow leaning toward the art region —
  /// the left half of the Concept-5 hero. Always on (this IS the rest-state
  /// background now that the key art lives in the region on the right, not
  /// full-bleed), and the surface the idle art's tinted feathers melt into
  /// (mid value ~0.30 meets their 0.34) — no half-poster seam, ever. During
  /// playback the lights-off veil above quenches this to near-black so the
  /// video's slim neutral feathers match. Baked gradients only — no
  /// per-frame layer. Boxed mode only.
  Widget _heroMoodField(ColorScheme scheme) {
    if (!widget.boxedTrailer) return const SizedBox.shrink();
    final base = AppThemeScope.of(context).home.bg; // the board's own bg
    return IgnorePointer(
      // RepaintBoundary so this layer's repaint never bubbles up and
      // re-rasters the whole hero band (region art included). The colour used
      // to SNAP between settles — a one-frame hue jump across ~60% of the
      // screen. It now TWEENS, but only per settle: the tint changes on its
      // 350ms debounce (never per DPAD step), so this costs ~24 frames of
      // two-gradient repaint inside this boundary per rest — not a per-key
      // cost — and the room's lighting follows the art instead of jumping.
      child: RepaintBoundary(
        child: ValueListenableBuilder<Color?>(
          valueListenable:
              widget.tint ?? const AlwaysStoppedAnimation<Color?>(null),
          builder: (context, tint, __) {
            // Retargets from the CURRENT colour when the settle lands a new
            // one, so back-to-back settles blend instead of restarting.
            return TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: tint ?? scheme.surface),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              builder: (context, animTint, __) {
                final t = animTint ?? scheme.surface;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    // Diagonal tint field: brighter top-left, deeper foot.
                    // TRANSLUCENT washes (not opaque lerps) since the glass
                    // stage landed: the blurred art behind glows through the
                    // colour, which is what makes the hero read glossy.
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(base, t, 0.55)!.withValues(alpha: 0.55),
                        Color.lerp(base, t, 0.40)!.withValues(alpha: 0.36),
                        Color.lerp(base, t, 0.25)!.withValues(alpha: 0.20),
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                  child: DecoratedBox(
                    // Soft glow leaning toward the art region (right of centre)
                    // so the colour intensifies into it and the left stays calm
                    // for the title text.
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.55, -0.25),
                        radius: 1.3,
                        colors: [
                          Color.lerp(base, t, 0.62)!.withValues(alpha: 0.5),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Wraps one text-block line in its slice of the cascade: a quick fade plus
  /// a slight upward drift, offset by [from]..[to] of the controller.
  Widget _cascade(Widget child, double from, double to) {
    final curved = CurvedAnimation(
      parent: _textFx,
      curve: Interval(from, to, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, inner) => Transform.translate(
          offset: Offset(0, 10 * (1 - curved.value)),
          child: inner,
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final item = widget.item;
    final background = widget.background;
    final description = widget.description;
    final isTelevision = widget.isTelevision;
    final height = widget.height;
    final rating = widget.rating;
    final compact = widget.compact;
    final scheme = Theme.of(context).colorScheme;
    final hasBackgroundArtwork = background != null && background.isNotEmpty;
    final bg = hasBackgroundArtwork ? background : (item.poster ?? '');
    final runtime = widget.runtime;
    // Chip-grammar meta line (type · year · runtime · genres, then the IMDb
    // mark) — replaces the old bordered type pill + star line for the flatter
    // OTT look. Facts-first order on purpose: the line ellipsizes from the
    // END when the identity block is narrow (boxed-trailer mode caps it at
    // the region's left edge), so the tail must be the part that reads fine
    // truncated. "MOVIE · 2023 · 1h 58m · Action · Adv…" still looks whole;
    // the old genre-first order chopped the year off instead ("…").
    final metaParts = <String>[
      item.type == 'series' ? 'SERIES' : 'MOVIE',
      if (item.year != null && item.year!.isNotEmpty) item.year!,
      if (runtime != null && runtime.isNotEmpty) runtime,
      if (item.genres != null && item.genres!.isNotEmpty)
        item.genres!.take(2).join(' · '),
    ];

    return SizedBox(
      height: height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, cons) {
          // Concept-5 stage geometry: in boxed mode the key art lives in the
          // SAME right-anchored region the trailer plays in (identical eased
          // feathers, colour field on the left) — idle and playing are one
          // layout, so the art→video swap is a crossfade in place, no
          // geometry jump. Falls back to the classic full-bleed backdrop when
          // the band is too short for a region (and on the compact hero).
          final Rect? artRegion = widget.boxedTrailer
              ? _heroTrailerRegionRect(cons.maxWidth, height)
              : null;
          return Stack(
            // Clip so a long title/plot can never bleed out of the hero into the
            // row header below it (the overflow bug on the compact Search hero).
            clipBehavior: Clip.hardEdge,
            fit: StackFit.expand,
            children: [
              // Behind everything: the hero's always-on colour stage (boxed mode)
              // — the canvas the title text sits on, and the surface the region's
              // feathers melt into.
              if (widget.boxedTrailer)
                _fadeForLiveTakeover(_heroMoodField(scheme)),
              if (bg.isNotEmpty && artRegion != null)
                // Region-anchored key art: cover-crop + the same eased feathers
                // the trailer uses, so still art and live video dissolve into the
                // field identically. No ShaderMask on this path (one less
                // saveLayer than full-bleed) — the bottom feather melts it into
                // the rows. Fades out while the trailer plays: the video occupies
                // this exact rect in the overlay above.
                Positioned.fromRect(
                  rect: artRegion,
                  child: _fadeBackdropForTrailer(
                    RepaintBoundary(
                      child: ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Ken Burns on the region art too — TV's boxed stage
                            // included (the drift was full-bleed-only before, so
                            // the TV hero was completely static). Same controller
                            // and grammar as the full-bleed path: a pure bottom-
                            // anchored slow zoom on the unchanging image child,
                            // linear sampling so it glides instead of jittering.
                            // The enclosing ClipRect catches the paint-time
                            // overflow; the feathers above stay static so the
                            // region's edges never move; and the drift stops
                            // whenever video covers this exact rect — trailer OR
                            // IPTV live takeover (_onHeroCoverChanged) — so it
                            // never burns frames under video.
                            AnimatedBuilder(
                              animation: _ken,
                              builder: (context, child) {
                                final t = Curves.easeInOut.transform(
                                  _ken.value,
                                );
                                return Transform.scale(
                                  scale: 1.0 + 0.06 * t,
                                  alignment: Alignment.bottomCenter,
                                  filterQuality: FilterQuality.low,
                                  child: child,
                                );
                              },
                              child: CachedNetworkImage(
                                imageUrl: bg,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                memCacheWidth: hasBackgroundArtwork
                                    ? widget.artworkCacheWidth
                                    : null,
                                memCacheHeight: hasBackgroundArtwork
                                    ? null
                                    : widget.artworkCacheHeight,
                                fadeInDuration: HomeTheme.imageFadeIn(
                                  isTelevision,
                                ),
                                fadeOutDuration: HomeTheme.imageFadeOut(
                                  isTelevision,
                                ),
                                errorWidget: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                            _regionArtFeathers(scheme),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (bg.isNotEmpty && artRegion == null)
                // Fade the backdrop's lower third to transparent so it melts into
                // the page's own gradient instead of ending on a hard horizontal
                // edge (the "seam"). The board rows then read as one surface with
                // the hero rather than two stacked boxes.
                //
                // Isolated in a RepaintBoundary so the Ken Burns drift re-rasterises
                // only the backdrop layer each frame — the scrim gradient and title
                // text above it stay cached and don't repaint.
                //
                // The ClipRect is load-bearing: the Ken Burns Transform.scale is a
                // *paint-time* overflow (bottom-anchored, growing upward), which
                // Stack.clipBehavior never catches — the Stack only clips overflow
                // it detects at layout time. Without this, the zoomed backdrop
                // smears above the hero into the search header (the "bleed").
                //
                // The outer fade is the image→colour-field crossfade: while a
                // trailer plays the image yields (fades out) to reveal the tint
                // colour field beneath, so the left is a rich wash, not a cropped
                // half-poster. Timing mirrors the 650ms crossfade the video uses.
                _fadeBackdropForTrailer(
                  RepaintBoundary(
                    child: ClipRect(
                      child: ShaderMask(
                        shaderCallback: (rect) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white,
                            Colors.white,
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.55, 1.0],
                        ).createShader(rect),
                        blendMode: BlendMode.dstIn,
                        child: AnimatedBuilder(
                          animation: _ken,
                          // The image is the (unchanging) child, so only the Transform's
                          // matrix recomputes each frame — no widget/image rebuild.
                          builder: (context, child) {
                            final t = Curves.easeInOut.transform(_ken.value);
                            // Pure slow zoom, no pan. Two things keep it glassy-smooth:
                            //  • filterQuality: linear sampling — without it a slow
                            //    transform snaps to whole pixels, which reads as jitter
                            //    ("shaking") instead of a glide;
                            //  • a single bottom-anchored scale — the origin never moves,
                            //    so the bottom edge stays put (no bleed toward the cards)
                            //    and there's no second motion to fight the first.
                            return Transform.scale(
                              scale: 1.0 + 0.06 * t,
                              alignment: Alignment.bottomCenter,
                              filterQuality: FilterQuality.low,
                              child: child,
                            );
                          },
                          child: CachedNetworkImage(
                            imageUrl: bg,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            // Cap the hero backdrop decode so an oversized source doesn't
                            // decode at native res, but keep it generous — it's a single
                            // full-width image (crisp matters, and one instance is cheap;
                            // the memory win is the many small rail posters, not this).
                            memCacheWidth: hasBackgroundArtwork
                                ? widget.artworkCacheWidth
                                : null,
                            memCacheHeight: hasBackgroundArtwork
                                ? null
                                : widget.artworkCacheHeight,
                            errorWidget: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Top scrim — compact Search hero only. The hero sits directly under
              // the search bar, so even with the overflow clipped the backdrop's
              // top row starts at full brightness against the header. A short dark
              // gradient (page-coloured → transparent) melts the top edge into the
              // page, mirroring the bottom fade. The full Home hero has nothing
              // above it, so it's left untouched.
              if (compact)
                Align(
                  alignment: Alignment.topCenter,
                  child: FractionallySizedBox(
                    heightFactor: 0.28,
                    widthFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [app.home.bg, Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                ),
              // Left scrim for title/description legibility (vertical bands, so it
              // adds no horizontal seam). The bottom is handled by the image fade
              // above, letting the page background show through. The scrim leans
              // toward the focused title's dominant poster color (see [tint]) and
              // eases between titles, so the hero takes on each title's mood —
              // repaints only when the settled tint changes, never per frame.
              // Fades out with the text once the trailer covers the hero, so the
              // full-bleed video reads clean (no purposeless left-darkening).
              _maybeFadeForTrailer(
                ValueListenableBuilder<Color?>(
                  valueListenable:
                      widget.tint ?? const AlwaysStoppedAnimation<Color?>(null),
                  builder: (context, tintColor, _) {
                    return TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: tintColor ?? scheme.surface),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOut,
                      builder: (context, eased, __) {
                        // Blend gently — mood, not a paint job. Falls back to the
                        // neutral surface while no tint is known.
                        final base = Color.lerp(
                          scheme.surface,
                          eased ?? scheme.surface,
                          0.22,
                        )!;
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                base.withValues(alpha: 0.92),
                                base.withValues(alpha: 0.66),
                                base.withValues(alpha: 0.10),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.34, 0.66, 1.0],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              // LIGHTS OFF: while the trailer plays the hero canvas goes near-
              // neutral-dark — a deep veil over the colour field + key art,
              // sitting BELOW the identity block (the logo stays full-bright)
              // and below the trailer overlay's punch-through hole (which clears
              // every Flutter pixel under it in the region, veil included). With
              // the tint quenched here, the video's slim NEUTRAL feathers land
              // on a matching near-black — no colour anywhere near the picture;
              // the title art and the moving image are the only lit things on
              // stage.
              // Slow dim down, fast lights-up on any DPAD move. Paints nothing
              // when idle.
              if (widget.boxedTrailer && widget.trailerShowing != null)
                IgnorePointer(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: widget.trailerShowing!,
                    builder: (context, on, _) => AnimatedOpacity(
                      opacity: on ? 1.0 : 0.0,
                      duration: on
                          ? const Duration(milliseconds: 900)
                          : const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      // 96% — verified on-device: at 72% the warm mood field
                      // still glowed through beside the video ("you can still
                      // see colors"). Near-opaque bg kills the hue completely
                      // and lands flush with the video's neutral left feather.
                      child: const ColoredBox(color: Color(0xF50D0B1A)),
                    ),
                  ),
                ),
              // The whole identity block — badge, title, meta, plot — fades out once
              // the trailer covers the hero, so a full-bleed trailer plays clean
              // (and, separately, once an IPTV favourite takes the region — see
              // [_fadeForLiveTakeover]).
              // RepaintBoundary: text + logo raster stays cached when siblings
              // (pill, veils, fields) repaint, and vice versa.
              _fadeForLiveTakeover(
                _maybeFadeForTrailer(
                  RepaintBoundary(
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: LayoutBuilder(
                        builder: (context, cons) {
                          // Keep the identity block clear of the trailer (boxedTrailer):
                          // cap its width at the region's left edge (the text ends
                          // where the trailer's slim left feather begins, so the two
                          // blend rather than collide).
                          final defaultMax = isTelevision ? 640.0 : 520.0;
                          double maxTextW = defaultMax;
                          if (widget.boxedTrailer) {
                            final region = _heroTrailerRegionRect(
                              cons.maxWidth,
                              height,
                            );
                            if (region != null) {
                              maxTextW = (region.left - 24).clamp(
                                220.0,
                                defaultMax,
                              );
                            }
                          }
                          return Padding(
                            // The tall Concept-5 hero gets real air under the plot
                            // line before the fold; the compact strip keeps its
                            // tighter foot.
                            padding: EdgeInsets.fromLTRB(
                              24,
                              0,
                              24,
                              isTelevision ? (compact ? 22 : 34) : 16,
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: maxTextW),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _cascade(_buildTitleArt(), 0.08, 0.72),
                                  SizedBox(height: compact ? 6 : 10),
                                  // Meta chips + plot fade away while the ambient trailer
                                  // plays (boxed mode) — the title art above holds the
                                  // stage alone. Layout is opacity-only, so nothing
                                  // reflows when they go.
                                  _fadeMetaForTrailer(
                                    _cascade(
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              metaParts.join('  ·  '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.3,
                                                color: app.fade(
                                                  app.core.tx,
                                                  0.82,
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (rating != null) ...[
                                            if (metaParts.isNotEmpty) _dot(),
                                            _imdbChip(rating),
                                          ],
                                        ],
                                      ),
                                      0.2,
                                      0.85,
                                    ),
                                  ),
                                  if (description != null &&
                                      description.isNotEmpty) ...[
                                    SizedBox(height: compact ? 6 : 10),
                                    _fadeMetaForTrailer(
                                      _cascade(
                                        Text(
                                          description,
                                          maxLines: compact
                                              ? 1
                                              : (isTelevision ? 3 : 2),
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: compact
                                                ? 12.5
                                                : (isTelevision ? 14.5 : 13),
                                            height: compact ? 1.3 : 1.45,
                                            color: app.fade(app.core.tx, 0.72),
                                          ),
                                        ),
                                        0.32,
                                        1.0,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              // "Trailer loading" pill — top-right, above the scrims so it reads
              // against any backdrop. Purely informational (never focusable), and
              // rendered only while the host is actually fetching/starting a
              // trailer, so idle browsing shows nothing.
              if (widget.trailerLoading != null)
                Positioned(
                  top: 18,
                  right: 22,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: widget.trailerLoading!,
                    builder: (context, loading, __) =>
                        _HeroTrailerLoadingPill(visible: loading),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _dot() {
    final app = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          color: app.fade(app.core.tx, 0.4),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  /// The idle key-art's edge dissolve — three eased feather shapes, TINTED
  /// (lerped 0.34 toward the board bg) because at rest the art sits on the
  /// coloured mood field. The live video paints the same shapes but NEUTRAL
  /// and roughly half as wide (user call — heavy/tinted melt read as bleed
  /// over the picture): by the time they fade in, the lights-off veils have
  /// quenched the tint around the region, so slim near-black feathers land
  /// seamlessly. Recolours only when the settled tint changes — never per
  /// frame.
  Widget _regionArtFeathers(ColorScheme scheme) {
    // Hoisted out of the builder below: the tint notifier fires on every
    // ambient artwork change, and an inherited-widget walk per tint frame is
    // exactly the hot path this board cannot afford on a TV box.
    final base = AppThemeScope.of(context).home.bg; // the board's own bg
    return IgnorePointer(
      child: ValueListenableBuilder<Color?>(
        valueListenable:
            widget.tint ?? const AlwaysStoppedAnimation<Color?>(null),
        builder: (context, tint, __) {
          final melt = tint == null ? base : Color.lerp(base, tint, 0.34)!;
          return Stack(
            fit: StackFit.expand,
            children: [
              _heroEdgeFeather(
                Alignment.centerLeft,
                Alignment.centerRight,
                melt,
                _heroTrailerFeatherFrac,
              ),
              _heroEdgeFeather(
                Alignment.topCenter,
                Alignment.bottomCenter,
                melt,
                0.16,
              ),
              _heroEdgeFeather(
                Alignment.bottomCenter,
                Alignment.topCenter,
                melt,
                0.36,
              ),
            ],
          );
        },
      ),
    );
  }

  /// The hero's title — see [_HeroTitleArt] for the image-first grammar.
  Widget _buildTitleArt() {
    return _HeroTitleArt(
      title: widget.item.name,
      logoUrl: widget.logo,
      compact: widget.compact,
      isTelevision: widget.isTelevision,
    );
  }

  /// The gold IMDb mark + rating — the meta line's one piece of colour.
  Widget _imdbChip(double rating) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFF5C518),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'IMDb',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: Color(0xFF161616),
          ),
        ),
      ),
      const SizedBox(width: 5),
      Text(
        rating.toStringAsFixed(1),
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

/// Geometry of the Home hero's ambient-trailer REGION — a right-anchored slab
/// that fills the hero band's height and bleeds to the right screen edge, into
/// which the trailer is painted and lightly feathered (slim neutral melts at
/// its left/top/bottom edges — no hard frame, but the picture stays
/// essentially clear). Shared by [_HeroSpotlight] (which keeps its title text
/// clear of the region) and [_HeroTrailerLayer] (which paints the video) so
/// both agree on the rect. Origin is the hero band's own top-left.
///
/// Width-led: ~56% of the hero, so the title keeps the left ~44%. Returns null
/// for a band too short to read as a trailer (falls back to full-width text).
Rect? _heroTrailerRegionRect(double width, double heroH) {
  if (!width.isFinite || !heroH.isFinite || width <= 0 || heroH <= 0) {
    return null;
  }
  if (heroH < 170) return null; // too short — keep the full-width hero instead
  // Below this the region can't be both wide enough to read and leave room for
  // the title — and it also keeps the clamp() below well-formed (lower ≤ upper).
  if (width < 480) return null;
  final regionW = (width * 0.56).clamp(360.0, width);
  final left = width - regionW; // flush to the right screen edge
  return Rect.fromLTWH(left, 0, regionW, heroH);
}

/// Fraction of the region's width over which the IDLE key-art's left edge
/// dissolves into the hero (see [_regionArtFeathers]). The title text ends at
/// the region's left, so at rest it sits over the dark side of this feather.
const double _heroTrailerFeatherFrac = 0.34;

/// Fraction for the LIVE video's left-edge melt — deliberately about half the
/// idle art's [_heroTrailerFeatherFrac]. The balance (user-tuned): the old
/// full-width feathers read as bleed over the picture, but fully crisp edges
/// read as a legacy boxed player — a slim melt keeps the picture essentially
/// untouched while its edges still dissolve into the stage.
const double _heroTrailerVideoFeatherFrac = 0.16;

/// Slight brightness lift painted flat over the live ambient trailer —
/// trailers are graded dark and the ambient region has no other light on it.
/// Low-alpha white: lifts the mids/shadows a touch without visibly milking
/// the highlights. Works in BOTH engine modes: over the underlay hole it
/// alpha-blends onto the native video via the system compositor; over the
/// texture path it's an ordinary fill. Tune the alpha to taste (0 = off).
const Color _heroTrailerBrightnessLift = Color(0x14FFFFFF);

/// One edge-feather for the hero's art/trailer region: a gradient from opaque
/// [c] at [begin] dissolving to transparent by [frac]. EASED stops (not a
/// linear two-stop ramp — that reads as a hard "veil edge" where the fade
/// starts): dense at the covered edge, long soft tail into the picture, the
/// Nuvio/Netflix gradient recipe. Still one baked gradient fill — no shader
/// mask, no per-frame cost — shared by the idle key-art and the live trailer
/// (the trailer at roughly half the art's fractions, so the picture stays
/// essentially clear) so the two states dissolve alike at the handover.
Widget _heroEdgeFeather(Alignment begin, Alignment end, Color c, double frac) {
  return DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: begin,
        end: end,
        colors: [
          c,
          c.withValues(alpha: 0.86),
          c.withValues(alpha: 0.42),
          c.withValues(alpha: 0.13),
          c.withValues(alpha: 0.0),
        ],
        stops: [0.0, frac * 0.28, frac * 0.56, frac * 0.80, frac],
      ),
    ),
  );
}

/// Full-board ambient trailer layer (TV Home board only). Sits ABOVE the hero +
/// rows as an [IgnorePointer] overlay and paints the trailer into a right-
/// anchored REGION of the hero band (see [_heroTrailerRegionRect]) — a live,
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
/// The Spotlight shell's floating search button — a frosted circle over the
/// hero, mirroring the approved mock. Deliberately plain Material ink-free
/// (the board underneath is a photograph; a splash reads as damage).
class _SpotlightSearchButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SpotlightSearchButton({required this.onTap});

  /// The button's geometry, named so the trailer layer's status chips can
  /// clear it by DERIVATION — a bare 66 over there would silently regress
  /// the clipped-"AMBIE…" overlap the moment this button moved or grew.
  static const double rightInset = 14;
  static const double diameter = 40;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x8C1E1E20),
              border: Border.all(color: const Color(0x1FFFFFFF)),
            ),
            child: const Icon(
              Icons.search_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroTrailerLayer extends StatefulWidget {
  final ValueListenable<YoutubeResolvedStreams?> trailer;

  /// The hero spotlight's height — sets the region's height (see
  /// [_heroTrailerRegionRect]).
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

  const _HeroTrailerLayer({
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
  State<_HeroTrailerLayer> createState() => _HeroTrailerLayerState();
}

class _HeroTrailerLayerState extends State<_HeroTrailerLayer> {
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
  void didUpdateWidget(_HeroTrailerLayer old) {
    super.didUpdateWidget(old);
    if (!identical(old.trailer, widget.trailer)) {
      old.trailer.removeListener(_onTrailerChanged);
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
              : _heroTrailerRegionRect(boardW, heroH);
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
  /// [_heroTrailerVideoFeatherFrac] for the tuned balance: heavy feathers
  /// read as bleed, none at all read as a legacy boxed player). The right
  /// edge bleeds off screen.
  ///
  /// Under the feathers sits [_heroTrailerBrightnessLift] — a single flat
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
                  const ColoredBox(color: _heroTrailerBrightnessLift),
                  // Boxed-mode edge melts only — Canvas paints its own
                  // constant scrims above this whole layer instead.
                  if (!widget.fullBleed) ...[
                    // Left: melt into the darkened text zone.
                    _heroEdgeFeather(
                      Alignment.centerLeft,
                      Alignment.centerRight,
                      app.home.bg,
                      _heroTrailerVideoFeatherFrac,
                    ),
                    // Top: soften the upper edge into the hero.
                    _heroEdgeFeather(
                      Alignment.topCenter,
                      Alignment.bottomCenter,
                      app.home.bg,
                      0.10,
                    ),
                    // Bottom: melt down into the darkened rows.
                    _heroEdgeFeather(
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
            child: _HeroTrailerLoadingPill(visible: loading),
          ),
          // Once frames are up the loading pill yields to the AMBIENT chip —
          // a quiet state affordance so the motion reads as intentional, not
          // a stray video. Same corner, so the two hand over in place.
          Positioned(
            top: _chipTop(context),
            right: _chipRight,
            child: _HeroAmbientChip(visible: playing && !loading),
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
      : _SpotlightSearchButton.rightInset +
            _SpotlightSearchButton.diameter +
            12;
}

/// Live IPTV preview drawn directly inside the active Spotlight card.
///
/// [SpotlightBoard] mounts this only for the pointer-hovered card on desktop
/// or the DPAD-focused card on TV, so a shelf never opens more than one stream
/// while the user browses. Stremio-backed channels retain the same candidate
/// ladder as the full IPTV preview stage; plain M3U/Xtream channels open their
/// declared URL directly. Its audio follows the user's Home ambient-audio
/// setting, so the channel is audible without overriding an intentional mute.
class SpotlightIptvCardPreview extends StatefulWidget {
  final IptvChannel channel;
  final double ambientVolume;

  const SpotlightIptvCardPreview({
    super.key,
    required this.channel,
    required this.ambientVolume,
  });

  @override
  State<SpotlightIptvCardPreview> createState() =>
      _SpotlightIptvCardPreviewState();
}

class _SpotlightIptvCardPreviewState extends State<SpotlightIptvCardPreview> {
  String? _streamUrl;
  List<String>? _candidates;
  int _resolveTicket = 0;

  @override
  void initState() {
    super.initState();
    _resolve(notify: false);
  }

  @override
  void didUpdateWidget(SpotlightIptvCardPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A shelf can reorder/reload while its active card's State is retained.
    // Never carry the previous channel's stream (or a late candidate resolve)
    // into the card that inherited that State slot.
    if (!identical(oldWidget.channel, widget.channel)) _resolve();
  }

  @override
  void dispose() {
    _resolveTicket++;
    super.dispose();
  }

  void _resolve({bool notify = true}) {
    final channel = widget.channel;
    final ticket = ++_resolveTicket;
    _candidates = null;
    if (channel.contentType == 'series') {
      _setStreamUrl(null, notify: notify);
      return;
    }
    if (!StremioIptvService.isStremioChannelUrl(channel.url)) {
      _setStreamUrl(channel.url, notify: notify);
      return;
    }

    _setStreamUrl(null, notify: notify);
    StremioIptvService.instance.resolveCandidates(channel.url).then((found) {
      if (!mounted || ticket != _resolveTicket || found.isEmpty) return;
      _candidates = [for (final candidate in found) candidate.url];
      _setStreamUrl(_candidates!.first);
    });
  }

  void _setStreamUrl(String? value, {bool notify = true}) {
    if (_streamUrl == value) return;
    if (!notify) {
      _streamUrl = value;
      return;
    }
    setState(() => _streamUrl = value);
  }

  void _onPlaybackFailed() {
    final candidates = _candidates;
    final current = _streamUrl;
    if (candidates == null || current == null) return;
    final next = candidates.indexOf(current) + 1;
    if (next <= 0 || next >= candidates.length) {
      StremioIptvService.instance.invalidate(widget.channel.url);
      _setStreamUrl(null);
      return;
    }
    _setStreamUrl(candidates[next]);
  }

  @override
  Widget build(BuildContext context) {
    final url = _streamUrl;
    if (url == null) return const SizedBox.expand();
    final channel = widget.channel;
    return RepaintBoundary(
      child: HeroTrailerBackdrop(
        // A candidate-ladder step needs a fresh player; retaining a dead
        // engine would leave the logo visible forever after its replacement
        // URL was selected.
        key: ValueKey('spotlight-iptv-card-${channel.url}-$url'),
        imageUrl: null,
        videoUrl: url,
        enabled: true,
        live: true,
        httpHeaders: channel.playbackHeaders,
        imageBlurSigma: 0,
        videoBlurSigma: 0,
        // The short dwell filters a pointer sweep / held DPAD move without
        // making a deliberate card preview feel late.
        startDelay: const Duration(milliseconds: 300),
        ambientVolume: widget.ambientVolume,
        onPlaybackFailed: _onPlaybackFailed,
        firstFrameTimeout: StremioIptvService.isStremioChannelUrl(channel.url)
            ? const Duration(seconds: 12)
            : null,
      ),
    );
  }
}

/// The boxed hero video region's IPTV-favourite variant: plays a focused
/// favourite channel's live stream in the SAME right-anchored region
/// [_HeroTrailerLayer] uses for catalog trailers, via
/// [HeroTrailerBackdrop]'s `live: true` mode — the exact mechanism the IPTV
/// page's own inline channel preview uses
/// (IptvResultsView._buildPreviewStage). Painted as a sibling ABOVE
/// [_HeroTrailerLayer] in the host's Stack and shrinks to nothing when no
/// IPTV favourite has focus, so the catalog trailer shows through unchanged;
/// the two are mutually exclusive in practice because
/// [_SearchScreenState._setHeroLiveIptv] tears the catalog trailer down the
/// moment a live feed starts.
///
/// While the stream resolves/buffers, [_HeroSpotlight]'s idle key art (the
/// previously-focused catalog title's Cinemeta poster) still sits BENEATH
/// this layer — so as soon as [channel] is non-null this paints an opaque
/// floor of the channel's OWN art ([_HeroLiveFloor]) rather than leaving that
/// gap for the stale poster to show through.
class _HeroLiveLayer extends StatefulWidget {
  final ValueListenable<IptvChannel?> channel;
  final ValueListenable<String?> streamUrl;
  final double heroHeight;
  final double volume;
  final ValueChanged<bool>? onPlayingChanged;
  final VoidCallback? onPlaybackFailed;

  /// CANVAS mode — same contract as [_HeroTrailerLayer.fullBleed]: the region
  /// (and the underlay hole with it) becomes the whole board and the boxed
  /// edge feathers are skipped; the Canvas scrims above carry the lighting.
  final bool fullBleed;

  const _HeroLiveLayer({
    required this.channel,
    required this.streamUrl,
    required this.heroHeight,
    required this.volume,
    this.onPlayingChanged,
    this.onPlaybackFailed,
    this.fullBleed = false,
  });

  @override
  State<_HeroLiveLayer> createState() => _HeroLiveLayerState();
}

class _HeroLiveLayerState extends State<_HeroLiveLayer> {
  /// Pins the live backdrop's element so its engine/texture survive rebuilds;
  /// replaced per URL (channel switch, or a candidate-ladder step-down) so
  /// each stream still gets a fresh engine.
  GlobalKey _backdropKey = GlobalKey();
  String? _backdropUrl;
  IptvChannel? _channel;
  String? _url;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _channel = widget.channel.value;
    _url = widget.streamUrl.value;
    widget.channel.addListener(_onChannelChanged);
    widget.streamUrl.addListener(_onUrlChanged);
  }

  @override
  void didUpdateWidget(_HeroLiveLayer old) {
    super.didUpdateWidget(old);
    if (!identical(old.channel, widget.channel)) {
      old.channel.removeListener(_onChannelChanged);
      widget.channel.addListener(_onChannelChanged);
      _channel = widget.channel.value;
    }
    if (!identical(old.streamUrl, widget.streamUrl)) {
      old.streamUrl.removeListener(_onUrlChanged);
      widget.streamUrl.addListener(_onUrlChanged);
      _url = widget.streamUrl.value;
      _playing = false;
    }
  }

  @override
  void dispose() {
    widget.channel.removeListener(_onChannelChanged);
    widget.streamUrl.removeListener(_onUrlChanged);
    super.dispose();
  }

  void _onChannelChanged() {
    if (!mounted) return;
    setState(() => _channel = widget.channel.value);
  }

  void _onUrlChanged() {
    if (!mounted) return;
    setState(() {
      _url = widget.streamUrl.value;
      _playing = false;
    });
  }

  void _onPlaying(bool playing) {
    widget.onPlayingChanged?.call(playing);
    if (_playing != playing && mounted) setState(() => _playing = playing);
  }

  @override
  Widget build(BuildContext context) {
    final channel = _channel;
    if (channel == null) return const SizedBox.shrink();
    final url = _url;
    if (url != null && url != _backdropUrl) {
      _backdropUrl = url;
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
              : _heroTrailerRegionRect(boardW, heroH);
          if (region == null) return const SizedBox.shrink();
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fromRect(
                rect: region,
                child: _buildRegion(channel, url),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Same clip/feather/brightness-lift treatment as
  /// [_HeroTrailerLayerState._buildRegion], plus the channel-art floor and a
  /// LIVE/TUNING status chip in place of the trailer's TRAILER/AMBIENT pills.
  /// Unlike the catalog trailer (whose feathers only appear once playing —
  /// its OWN idle art beneath already carries them), the melt here is
  /// unconditional: the floor is opaque from the first frame this builds, so
  /// there's always something to feather.
  Widget _buildRegion(IptvChannel channel, String? url) {
    final app = AppThemeScope.of(context);
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Opaque floor: the channel's own art, so the previously-focused
          // catalog title's poster never shows through the resolve/buffer
          // gap. Crossfades out once real frames land.
          AnimatedOpacity(
            opacity: _playing ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeOut,
            child: _HeroLiveFloor(channel: channel),
          ),
          if (url != null)
            RepaintBoundary(
              child: HeroTrailerBackdrop(
                key: _backdropKey,
                imageUrl: null,
                videoUrl: url,
                enabled: true,
                live: true,
                imageBlurSigma: 0,
                videoBlurSigma: 0,
                startDelay: const Duration(milliseconds: 300),
                ambientVolume: widget.volume,
                onPlayingChanged: _onPlaying,
                onPlaybackFailed: widget.onPlaybackFailed,
                // Only a Stremio-addon favourite has a ladder to fall back
                // on — bound its wait so a dead candidate doesn't stall
                // forever. A plain M3U/Xtream favourite has just the one
                // URL, so give it an unbounded wait instead of abandoning an
                // otherwise-valid but slow-to-buffer stream (matches
                // IptvResultsView._buildPreviewStage's own timeout choice).
                firstFrameTimeout:
                    StremioIptvService.isStremioChannelUrl(channel.url)
                    ? const Duration(seconds: 12)
                    : null,
              ),
            ),
          IgnorePointer(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: _heroTrailerBrightnessLift),
                // Boxed-mode edge melts only — Canvas paints its own constant
                // scrims above this whole layer instead.
                if (!widget.fullBleed) ...[
                  _heroEdgeFeather(
                    Alignment.centerLeft,
                    Alignment.centerRight,
                    app.home.bg,
                    _heroTrailerVideoFeatherFrac,
                  ),
                  _heroEdgeFeather(
                    Alignment.topCenter,
                    Alignment.bottomCenter,
                    app.home.bg,
                    0.10,
                  ),
                  _heroEdgeFeather(
                    Alignment.bottomCenter,
                    Alignment.topCenter,
                    app.home.bg,
                    0.20,
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            top: 16,
            right: 22,
            child: _HeroLiveChip(playing: _playing),
          ),
        ],
      ),
    );
  }
}

/// The IPTV favourite's own art, filling the boxed region while its stream
/// resolves/buffers (and behind it, briefly, while frames settle) — the
/// channel's logo over the same purple gradient + live-tv glyph fallback
/// [_ArtPoster] uses for its card, so the region reads as "this channel is
/// tuning in" rather than an unrelated leftover poster.
class _HeroLiveFloor extends StatelessWidget {
  final IptvChannel channel;

  const _HeroLiveFloor({required this.channel});

  @override
  Widget build(BuildContext context) {
    final logo = channel.logoUrl;
    final hasLogo = logo != null && logo.isNotEmpty;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1D5C), Color(0xFF1A1440), Color(0xFF0D0B1A)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Center(
        child: hasLogo
            ? Padding(
                padding: const EdgeInsets.all(56),
                child: CachedNetworkImage(
                  imageUrl: logo,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => const _HeroLiveGlyph(),
                ),
              )
            : const _HeroLiveGlyph(),
      ),
    );
  }
}

class _HeroLiveGlyph extends StatelessWidget {
  const _HeroLiveGlyph();

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Icon(
      Icons.live_tv_rounded,
      size: 64,
      color: app.fade(app.home.chromeAccent, 0.85),
    );
  }
}

/// Small "LIVE"/"TUNING" status pill for the boxed hero region while an IPTV
/// favourite plays there — same glass-capsule language as
/// [_HeroTrailerLoadingPill]/[_HeroAmbientChip], with a red dot (matching
/// [_ArtPoster]'s own LIVE badge) instead of the trailer pills' amber one.
class _HeroLiveChip extends StatelessWidget {
  final bool playing;

  const _HeroLiveChip({required this.playing});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        // Glassy page ink — 0.8 of the opaque bg pins the legacy 0xCC alpha.
        color: app.fade(app.home.bg, 0.8),
        borderRadius: app.shape.brPill,
        border: Border.all(color: app.fade(app.core.tx, 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: _kCwProgressRed,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            playing ? 'LIVE' : 'TUNING',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: app.core.tx,
            ),
          ),
        ],
      ),
    );
  }
}

/// The hero's title, IMAGE-FIRST: the studio title-treatment art when a
/// `logo` URL is known, the plain text title only when it is genuinely
/// unavailable (no URL, or the fetch failed). While the art is in flight the
/// slot holds EMPTY — never the text — because text-flashing-then-swapping
/// to the image read as a glitch (the old behaviour). Failed URLs are
/// remembered for the session so revisiting a logo-less title shows its text
/// immediately instead of re-probing (and re-flashing empty) every time.
/// Bottom-left anchored in a fixed-height slot so successive titles sit on
/// one baseline as DPAD focus flies.
class _HeroTitleArt extends StatefulWidget {
  final String title;
  final String? logoUrl;
  final bool compact;
  final bool isTelevision;

  const _HeroTitleArt({
    required this.title,
    required this.logoUrl,
    required this.compact,
    required this.isTelevision,
  });

  @override
  State<_HeroTitleArt> createState() => _HeroTitleArtState();
}

class _HeroTitleArtState extends State<_HeroTitleArt> {
  /// Session-wide memo of logo URLs that 404'd (metahub simply has no art
  /// for many titles) — those heroes go straight to text with no empty beat
  /// and no repeat network probe on every DPAD revisit.
  static final Set<String> _deadLogoUrls = <String>{};

  Text _titleText(int maxLines) => Text(
    widget.title,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    // Poppins (rounded geometric) for the display title, airier and lighter
    // than Inter-w800/-1 tracking — closer to Stremio's hero. Body/metadata
    // stay on the Inter theme.
    style: GoogleFonts.poppins(
      fontSize: widget.compact
          ? (widget.isTelevision ? 24 : 20)
          : (widget.isTelevision ? 38 : 26),
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      height: 1.06,
      color: AppThemeScope.of(context).core.tx,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final logo = widget.logoUrl;
    final compact = widget.compact;
    final isTelevision = widget.isTelevision;
    if (logo == null || logo.isEmpty || _deadLogoUrls.contains(logo)) {
      // Known-no-art: the full two-line text title, exactly the old look.
      return _titleText(2);
    }
    final logoH = compact
        ? (isTelevision ? 46.0 : 38.0)
        : (isTelevision ? 76.0 : 58.0);
    return SizedBox(
      height: logoH,
      width: double.infinity,
      child: Align(
        alignment: Alignment.bottomLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isTelevision ? 320 : 280),
          child: CachedNetworkImage(
            imageUrl: logo,
            fit: BoxFit.contain,
            alignment: Alignment.bottomLeft,
            // Logos are wide PNGs (metahub ~800px) shown ~300px at most — cap
            // the decode like every other art surface.
            memCacheWidth: 480,
            fadeInDuration: HomeTheme.imageFadeIn(isTelevision),
            fadeOutDuration: HomeTheme.imageFadeOut(isTelevision),
            // Empty while loading AND on error: the error frame only shows
            // for the instant before errorListener rebuilds us onto the
            // full-size text path below (a slot-cramped one-line fallback
            // here would flash before that swap).
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
            errorListener: (_) {
              _deadLogoUrls.add(logo);
              if (mounted) setState(() {});
            },
          ),
        ),
      ),
    );
  }
}

/// The hero's "trailer is on its way" chip: the same quiet glass capsule as
/// [_HeroAmbientChip] (they hand over in place in the same corner), but with
/// three tiny amber equalizer bars dancing where the ambient dot will sit —
/// "sound and picture incoming", not a generic spinner (the old bordered
/// spinner-pill read dated). Deliberately quiet — a status whisper, never a
/// control — and cheap: no blur (weak-TV rule), the bars are a ~14px-wide
/// repaint inside their own RepaintBoundary, and the controller only runs
/// while [visible], so the 99% of browsing the chip spends hidden costs
/// nothing at all.
class _HeroTrailerLoadingPill extends StatefulWidget {
  final bool visible;

  const _HeroTrailerLoadingPill({required this.visible});

  @override
  State<_HeroTrailerLoadingPill> createState() =>
      _HeroTrailerLoadingPillState();
}

class _HeroTrailerLoadingPillState extends State<_HeroTrailerLoadingPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.visible) _wave.repeat();
  }

  @override
  void didUpdateWidget(_HeroTrailerLoadingPill old) {
    super.didUpdateWidget(old);
    if (widget.visible && !_wave.isAnimating) {
      _wave.repeat();
    } else if (!widget.visible && _wave.isAnimating) {
      // Freezing mid-wave is invisible: the chip itself is fading to 0.
      _wave.stop();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  /// One equalizer bar: bottom-anchored, height riding a phase-shifted sine
  /// so the three bars roll as a wave rather than pumping in unison.
  /// [color] is passed in, captured once at build — this runs per wave frame.
  Widget _bar(Color color, double t, double phase) {
    final f = 0.30 + 0.70 * (0.5 + 0.5 * sin(2 * pi * (t + phase)));
    return Container(
      width: 2.5,
      height: 11 * f,
      decoration: BoxDecoration(
        color: color, // the ambient dot's amber
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final visible = widget.visible;
    return IgnorePointer(
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -0.25),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          // RepaintBoundary: while resolving, the wave produces a frame per
          // vsync — without the boundary each one would dirty the ROUTE's
          // layer and repaint every non-isolated part of the screen for the
          // whole resolve window (measured with the old spinner).
          child: RepaintBoundary(
            child: Container(
              padding: const EdgeInsets.fromLTRB(11, 6, 12, 6),
              decoration: BoxDecoration(
                // Glassy page ink — fade 0.8 pins the legacy 0xCC alpha.
                color: app.fade(app.home.bg, 0.8),
                borderRadius: app.shape.brPill,
                border: Border.all(color: app.fade(app.core.tx, 0.16)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 13,
                    height: 11,
                    child: AnimatedBuilder(
                      animation: _wave,
                      builder: (context, _) {
                        final t = _wave.value;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _bar(app.home.highlight, t, 0.0),
                            _bar(app.home.highlight, t, 0.30),
                            _bar(app.home.highlight, t, 0.60),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'TRAILER',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: app.fade(app.core.tx, 0.62),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "AMBIENT" chip that replaces the loading pill once trailer frames are
/// on screen: a quiet glass pill with a slowly breathing amber dot — a state
/// affordance ("this motion is intentional"), never a control. Same corner and
/// idioms as [_HeroTrailerLoadingPill] (no blur; the pulse ticker is started/
/// stopped with [visible] — TickerMode can't gate it, the ticker belongs to
/// this State which sits above any wrapper — so it costs nothing while hidden;
/// the dot is a 6px repaint, trivia next to the video already playing beneath
/// it).
class _HeroAmbientChip extends StatefulWidget {
  final bool visible;

  const _HeroAmbientChip({required this.visible});

  @override
  State<_HeroAmbientChip> createState() => _HeroAmbientChipState();
}

class _HeroAmbientChipState extends State<_HeroAmbientChip>
    with SingleTickerProviderStateMixin {
  // Created EAGERLY in initState: on TV nothing else touches it, and a `late`
  // field first reached by dispose() would create its Ticker there — a
  // TickerMode ancestor lookup on a defunct context (debug assertion crash).
  late final AnimationController _pulse;

  /// TV never breathes: the pulse would tick + repaint at 60fps for the whole
  /// trailer, compositing over the underlay video every frame — continuous
  /// idle animation is exactly what the TV effects budget bans, and a static
  /// lit dot reads identically from the couch. Phones keep the breath.
  bool get _pulseOk => !PlatformUtil.isTelevision;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.visible && _pulseOk) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_HeroAmbientChip old) {
    super.didUpdateWidget(old);
    if (!_pulseOk) return;
    if (widget.visible && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.visible && _pulse.isAnimating) {
      // Freezing mid-breath is invisible: the chip itself is fading to 0.
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final visible = widget.visible;
    return IgnorePointer(
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -0.25),
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeOut,
          child: RepaintBoundary(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
              decoration: BoxDecoration(
                // Glassy page ink — fade 0.8 pins the legacy 0xCC alpha.
                color: app.fade(app.home.bg, 0.8),
                borderRadius: app.shape.brPill,
                border: Border.all(color: app.fade(app.core.tx, 0.16)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Builder(
                    builder: (context) {
                      final dot = SizedBox(
                        width: 6,
                        height: 6,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: app.home.highlight,
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x8CF59E0B),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      );
                      if (!_pulseOk) return dot; // TV: lit, still, free
                      return FadeTransition(
                        opacity: Tween<double>(begin: 0.45, end: 1.0).animate(
                          CurvedAnimation(
                            parent: _pulse,
                            curve: Curves.easeInOut,
                          ),
                        ),
                        child: dot,
                      );
                    },
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'AMBIENT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: app.fade(app.core.tx, 0.62),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One-shot entrance for a board row: fade in + rise ~10px, started after
/// [delayMs] so consecutive rows stagger. When [play] is false (row mounted
/// long after the board landed, reduced motion, or beyond the first screenful)
/// it renders the child directly with zero overhead. The controller runs once
/// and stays idle after — no sustained per-frame cost.
class _EntranceReveal extends StatefulWidget {
  final Widget child;
  final bool play;
  final int delayMs;

  const _EntranceReveal({
    super.key,
    required this.child,
    required this.play,
    this.delayMs = 0,
  });

  @override
  State<_EntranceReveal> createState() => _EntranceRevealState();
}

class _EntranceRevealState extends State<_EntranceReveal>
    with SingleTickerProviderStateMixin {
  AnimationController? _fx;
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    if (widget.play) {
      _fx = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      );
      if (widget.delayMs == 0) {
        _fx!.forward();
      } else {
        _delay = Timer(Duration(milliseconds: widget.delayMs), () {
          if (mounted) _fx?.forward();
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: land settled immediately.
    if (_fx != null && MediaQuery.of(context).disableAnimations) {
      _delay?.cancel();
      _fx!.value = 1.0;
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _fx?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fx = _fx;
    if (fx == null) return widget.child;
    final curved = CurvedAnimation(parent: fx, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, inner) => Transform.translate(
          offset: Offset(0, 12 * (1 - curved.value)),
          child: inner,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Small pill next to a catalog-row header marking it as Movies / Series / etc.
/// An optional leading [icon] lets a pill carry meaning beyond the label (e.g.
/// a star on the Debrify TV "Favorites" pill).
class _CategoryTag extends StatelessWidget {
  final String label;
  final IconData? icon;
  const _CategoryTag(this.label, {this.icon});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: app.fade(app.home.chromeAccent, 0.16),
        borderRadius: app.shape.br(8),
        border: Border.all(color: app.fade(app.home.chromeAccent, 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: const Color(0xFFB9A9FF)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFB9A9FF),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Where a Continue Watching row's entries live — drives the long-press menu's
/// wording, since "remove" means a different write per source (local store,
/// Trakt playback API, Simkl status/session, IPTV watch history).
