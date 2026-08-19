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
enum _CwKind { local, trakt, simkl, iptv }

/// A leading "Continue Watching" board row (local or Trakt). Carries its own
/// header, focus nodes, per-item progress lookup, and open / quick-play
/// handlers so the local and Trakt sources render through one row builder.
class _CwRow {
  final String rowId;
  final String title; // e.g. 'Continue Watching' or 'Trakt Movies'
  final String? tag; // 'Movies' / 'Series' pill, or null
  final _CwKind kind;
  final List<StremioMeta> items;
  final List<FocusNode> nodes;
  final double? Function(StremioMeta) progressOf;

  /// Subtle 'S2 · E5' label for series cards (null for movies / when unknown).
  final String? Function(StremioMeta) episodeOf;
  final void Function(StremioMeta) onOpen;
  final void Function(StremioMeta) onQuickPlay;

  /// Takes the title off THIS row's source and reloads it. Long-press (hold-OK
  /// on TV) offers it next to Play — see [_SearchScreenState._openCwCardMenu].
  final Future<void> Function(StremioMeta) onRemove;

  /// Opens the "See All" grid for this row's source, or null to hide the link.
  final VoidCallback? onSeeAll;

  const _CwRow({
    required this.rowId,
    required this.title,
    required this.tag,
    required this.kind,
    required this.items,
    required this.nodes,
    required this.progressOf,
    required this.episodeOf,
    required this.onOpen,
    required this.onQuickPlay,
    required this.onRemove,
    this.onSeeAll,
  });
}

/// A reserved-but-not-yet-loaded Trakt row: a header above a strip of static
/// poster placeholders (see [_SearchScreenState._buildTraktSkeletonRow]) that
/// hold the Trakt slot open while its fetch runs. Static — nothing animates
/// while the CPU is busy loading (see [ShimmerBox]).
class _TraktSkeletonRow extends StatelessWidget {
  final Widget header;
  final double posterW;
  final double cellH;
  final double rowH;

  const _TraktSkeletonRow({
    required this.header,
    required this.posterW,
    required this.cellH,
    required this.rowH,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        SizedBox(
          height: rowH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.hardEdge,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 13),
            itemCount: 6,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Center(
                  child: _SkeletonPoster(width: posterW, height: cellH),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A poster-shaped static placeholder matching the board's poster radius. Thin
/// wrapper that sizes a [ShimmerBox].
class _SkeletonPoster extends StatelessWidget {
  final double width;
  final double height;

  const _SkeletonPoster({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, height: height, child: const ShimmerBox());
  }
}

/// [_StremioCard] plus DPAD arrow navigation. The card owns SELECT, its
/// focus visuals and ensureVisible; this ancestor [Focus] catches the arrows
/// the card ignores (left/right within the row, up/down to adjacent rows or
/// the search field) and reports focus to drive the hero.
class _BoardCell extends StatelessWidget {
  final StremioMeta item;
  final bool isTelevision;
  final FocusNode focusNode;
  final int column;
  final List<FocusNode> rowNodes;
  final bool hasBoundSource;

  /// 0..1 watched fraction — draws a bottom progress bar when non-null (used by
  /// the Continue Watching row). Null on regular catalog rows.
  final double? progress;

  /// Subtle 'S2 · E5' badge for a Continue Watching series card, or null.
  final String? episodeLabel;

  /// Long-press quick-play (mobile/desktop). Null hides the shortcut — used to
  /// mirror the catalog tiles' long-press-to-play when quick-play is available.
  final VoidCallback? onQuickPlay;

  /// Long-press (and hold-OK on TV) opens a menu instead of playing. Set on
  /// Continue Watching cards, where the press has to offer removal too; takes
  /// precedence over [onQuickPlay] when both are given.
  final VoidCallback? onLongPress;
  final VoidCallback onFocused;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onOpen;

  /// Called when DPAD-right focus nears this row's last card, so the next page
  /// can be prefetched before the user runs out of cards. Null on rows that
  /// don't paginate (e.g. Continue Watching).
  final VoidCallback? onNearEnd;

  /// Shared-element tag forwarded to the card (see [_StremioCard.heroTag]).
  final String? heroTag;

  /// Forwarded to [_StremioCard.ringColor] (Canvas cells use white).
  final Color? ringColor;

  /// Cell shape + the art that fills it. Defaults are the 2:3 poster every
  /// row uses; Promenade's strip passes 16/9 with a derived wide still.
  final double aspectRatio;
  final String? artUrl;

  /// Dim applied to this cell while it is NOT focused (Promenade's strip).
  final Color? restVeil;

  /// HELD up/down — fired on the first key REPEAT instead of [onUp]/[onDown].
  /// Tonight uses it to escape a long Continue queue in one gesture rather
  /// than one row at a time. Null keeps a held key doing what a tapped one
  /// does (the fast-scroll every rail relies on).
  final VoidCallback? onUpHold;
  final VoidCallback? onDownHold;

  /// Horizontal overrides. Null keeps the row grammar (LEFT walks back along
  /// [rowNodes] and hands off to the sidebar at column 0; RIGHT walks forward
  /// and prefetches). Mosaic's GRID must override both — its leftmost cell is
  /// not column 0, so without this the sidebar would be unreachable from
  /// every row but the first — and Tonight's queue overrides them too.
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const _BoardCell({
    required this.item,
    required this.isTelevision,
    required this.focusNode,
    required this.column,
    required this.rowNodes,
    required this.hasBoundSource,
    this.progress,
    this.episodeLabel,
    this.onQuickPlay,
    this.onLongPress,
    required this.onFocused,
    required this.onUp,
    required this.onDown,
    required this.onOpen,
    this.onNearEnd,
    this.heroTag,
    this.ringColor,
    this.onLeft,
    this.onRight,
    this.aspectRatio = 2 / 3,
    this.artUrl,
    this.restVeil,
    this.onUpHold,
    this.onDownHold,
  });

  KeyEventResult _handleArrows(FocusNode node, KeyEvent event) {
    // Act on key-down AND key-repeat (held DPAD). If we let a repeat fall
    // through as `ignored`, Flutter's default geometric traversal fires and
    // jumps focus into an adjacent row — so only key-ups are passed on.
    if (!isTelevision || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (onLeft != null) {
        onLeft!();
      } else if (column > 0) {
        rowNodes[column - 1].requestFocus();
      } else {
        // First card in the row — leave to the sidebar (no leading tile now).
        MainPageBridge.focusTvSidebar?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      // Prefetch the next page a few cards before the end so DPAD users never
      // hit a wall on a catalog that still has more.
      if (column >= rowNodes.length - 6) onNearEnd?.call();
      if (onRight != null) {
        onRight!();
      } else if (column < rowNodes.length - 1) {
        rowNodes[column + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (event is KeyRepeatEvent && onUpHold != null) {
        onUpHold!();
      } else {
        onUp();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (event is KeyRepeatEvent && onDownHold != null) {
        onDownHold!();
      } else {
        onDown();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (has) {
        if (has) onFocused();
      },
      onKeyEvent: _handleArrows,
      child: _StremioCard(
        item: item,
        isTelevision: isTelevision,
        focusNode: focusNode,
        hasBoundSource: hasBoundSource,
        ringColor: ringColor,
        progress: progress,
        episodeLabel: episodeLabel,
        onQuickPlay: onQuickPlay,
        onLongPress: onLongPress,
        onOpen: onOpen,
        heroTag: heroTag,
        aspectRatio: aspectRatio,
        artUrl: artUrl,
        restVeil: restVeil,
      ),
    );
  }
}

/// Hero flight for poster→detail-backdrop: always show the POSTER side of the
/// pair (the `from` hero on push, the `to` hero on pop), so the artwork the
/// user tapped is what grows into / shrinks out of the detail page — never a
/// half-loaded backdrop.
Widget _posterFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final Hero posterHero =
      (direction == HeroFlightDirection.push
              ? fromHeroContext.widget
              : toHeroContext.widget)
          as Hero;
  // The shuttle renders in the root overlay, outside any Material — wrap so a
  // text placeholder (missing poster art) can't render unstyled mid-flight.
  return Material(type: MaterialType.transparency, child: posterHero.child);
}

/// Metahub title-logo URL derived synchronously from an IMDb id (same trick
/// the hero uses) — lets the Canvas identity show studio title art without
/// waiting for /meta enrichment. Null when the item has no IMDb-shaped id.
String? _metahubLogoUrl(StremioMeta item) {
  final tt = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
  return tt == null ? null : 'https://images.metahub.space/logo/medium/$tt/img';
}

/// Metahub 16:9 still, derived the same synchronous way — catalog items carry
/// a poster but rarely a backdrop, and the wide-cell layouts (Promenade's
/// strip, Tonight's queue) need landscape art the moment a rail paints, not
/// after /meta enrichment. Null when the item has no IMDb-shaped id.
String? _metahubBackgroundUrl(StremioMeta item) {
  final tt = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
  return tt == null
      ? null
      : 'https://images.metahub.space/background/medium/$tt/img';
}

/// Best available wide art for a 16:9 cell: whatever the item already carries,
/// then the derived metahub still, then the poster (cover-cropped) so a cell
/// is never empty.
String? _wideArtUrl(StremioMeta item) =>
    _firstNonEmpty(item.background, _metahubBackgroundUrl(item)) ??
    _firstNonEmpty(item.poster, null);

/// Whether [enriched] describes the same title as [item]. Raw id equality is
/// not enough: an addon can list a title as `tmdb:603` while the /meta
/// record — fetched via the IMDb id the addon supplied — comes back as
/// `tt0133093`. Compare canonical IMDb identity too, or valid enrichment
/// gets rejected and Canvas loses its backdrop/description/rating.
bool _sameCanvasTitle(StremioMeta item, StremioMeta enriched) {
  if (enriched.id == item.id) return true;
  final itTt = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
  final enTt =
      enriched.imdbId ?? (enriched.id.startsWith('tt') ? enriched.id : null);
  return itTt != null && itTt == enTt;
}

/// First non-empty of two optional strings (merge helper: enriched field
/// wins only when it actually carries a value).
String? _firstNonEmpty(String? a, String? b) =>
    (a != null && a.isNotEmpty) ? a : ((b != null && b.isNotEmpty) ? b : null);

/// One Canvas rail — a Continue Watching row ([cw] non-null, with its
/// position among the CW rows in [cwIndex]), a favourites-family rail
/// ([favKind] non-null: IPTV / Debrify TV / Stremio TV / Playlist / an IPTV
/// custom-list row), or a catalog section ([sectionIndex] into
/// `_sections`/`_rowNodes`).
class _CanvasRail {
  final _CwRow? cw;
  final int cwIndex;
  final _FavRowRef? favKind;
  final int? sectionIndex;
  final int traktSkeletonIndex;
  const _CanvasRail({
    this.cw,
    this.cwIndex = -1,
    this.favKind,
    this.sectionIndex,
    this.traktSkeletonIndex = -1,
  });
}

/// What the Canvas stage should show while a FAVOURITES cell has focus —
/// favourites aren't StremioMeta, so the hero pipeline can't describe them;
/// this lightweight override carries the focused item's own art + name
/// instead (null = a catalog/CW item owns the stage as usual).
/// Paints the four corner "wedges" that make a rectangle read as a rounded
/// card — the area between the rect and its rounded inset, filled with the
/// page ink. Used instead of a ClipRRect wherever the box contains the
/// underlay trailer: a clip would introduce a saveLayer over the punch hole
/// and break its BlendMode.clear against the translucent surface, while a
/// plain fill painted ABOVE the hole is the proven pattern.
class _CornerWedges extends CustomPainter {
  final double radius;
  final Color color;
  const _CornerWedges({required this.radius, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect),
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius))),
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CornerWedges old) =>
      old.radius != radius || old.color != color;
}

/// What a stage board resolved for this frame (see
/// [_SearchScreenState._resolveStageRail]) — the rail list, which one is
/// active, its identity key, its items and its focus nodes.
class _StageRailView {
  final List<_CanvasRail> rails;
  final int index;
  final _CanvasRail rail;
  final String key;
  final List<StremioMeta> items;
  final List<FocusNode> nodes;
  const _StageRailView({
    required this.rails,
    required this.index,
    required this.rail,
    required this.key,
    required this.items,
    required this.nodes,
  });
}

/// The identity block a stage shows while a FAVOURITES cell has focus.
/// Favourites aren't StremioMeta, so the logo/meta/synopsis pipeline has
/// nothing true to say about them — this is the favourite's own name and
/// source line, in the same type as the catalog identity above it.
class _StageFavIdentity extends StatelessWidget {
  final _CanvasFavFocus fav;
  final bool centered;

  const _StageFavIdentity({required this.fav, this.centered = false});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fav.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: app.core.tx,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
            height: 1.1,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 14)],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          fav.subtitle,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: app.fade(app.core.tx, 0.6),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

/// What Tonight's big card says about the focused entry. Derived per focus —
/// the OK hint has to tell the truth: a part-watched title resumes, a catalog
/// title opens, a favourite is watched.
class _TonightCardInfo {
  /// What OK actually does — never what the layout wishes it did. Continue
  /// Watching cards open their detail page on OK across the whole app, and
  /// Tonight keeps that grammar rather than diverging.
  final String action;

  /// What a HELD OK does, when that differs (resume, or the card menu).
  final String? holdAction;
  final String? episode;
  final double? progress;
  const _TonightCardInfo({
    required this.action,
    this.holdAction,
    this.episode,
    this.progress,
  });
}

/// The caption block on Tonight's card: title art, what you are about to do,
/// the episode, how much is left and the progress bar. Everything is driven
/// by listenables so a DPAD move repaints this block alone.
class _TonightCardCaption extends StatelessWidget {
  final ValueListenable<StremioMeta?> item;
  final ValueListenable<StremioMeta?> enriched;
  final ValueListenable<_CanvasFavFocus?> fav;
  final ValueListenable<_TonightCardInfo?> info;

  const _TonightCardCaption({
    required this.item,
    required this.enriched,
    required this.fav,
    required this.info,
  });

  /// Minutes left from a '60 min'-shaped runtime and a 0..1 progress.
  static String? _timeLeft(String? runtime, double? progress) {
    if (runtime == null || progress == null || progress <= 0) return null;
    final m = RegExp(r'(\d+)').firstMatch(runtime);
    if (m == null) return null;
    final total = int.tryParse(m.group(1)!);
    if (total == null || total <= 0) return null;
    final left = ((1 - progress.clamp(0.0, 1.0)) * total).round();
    return left <= 0 ? null : '$left min left';
  }

  @override
  Widget build(BuildContext context) {
    // Hoisted: `fav` fires on every focus move across the Tonight rail.
    final tx = AppThemeScope.of(context).core.tx;
    return ValueListenableBuilder<_CanvasFavFocus?>(
      valueListenable: fav,
      builder: (context, favFocus, _) {
        if (favFocus != null) {
          return _block(
            context,
            hold: null,
            titleWidget: Text(
              favFocus.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tx,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 12)],
              ),
            ),
            line: favFocus.subtitle,
            action: 'Watch',
            progress: null,
          );
        }
        return ValueListenableBuilder<StremioMeta?>(
          valueListenable: item,
          builder: (context, it, _) => ValueListenableBuilder<StremioMeta?>(
            valueListenable: enriched,
            builder: (context, en, _) =>
                ValueListenableBuilder<_TonightCardInfo?>(
                  valueListenable: info,
                  builder: (context, nfo, _) {
                    final it0 = it;
                    if (it0 == null) return const SizedBox.shrink();
                    final enr = (en != null && _sameCanvasTitle(it0, en))
                        ? en
                        : null;
                    final logo =
                        _firstNonEmpty(enr?.logo, it0.logo) ??
                        _metahubLogoUrl(it0);
                    final runtime = _firstNonEmpty(enr?.runtime, it0.runtime);
                    final left = _timeLeft(runtime, nfo?.progress);
                    final parts = <String>[
                      if (nfo?.episode != null) nfo!.episode!,
                      if (left != null) left else if (runtime != null) runtime,
                      if (nfo?.episode == null && left == null)
                        (it0.type == 'series' ? 'SERIES' : 'MOVIE'),
                    ];
                    return _block(
                      context,
                      hold: nfo?.holdAction,
                      titleWidget: logo != null
                          ? ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 46,
                                maxWidth: 300,
                              ),
                              child: CachedNetworkImage(
                                imageUrl: logo,
                                fit: BoxFit.contain,
                                alignment: Alignment.bottomLeft,
                                memCacheWidth: 400,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (_, __) =>
                                    const SizedBox(height: 46),
                                errorWidget: (_, __, ___) =>
                                    _fallbackTitle(it0.name),
                              ),
                            )
                          : _fallbackTitle(it0.name),
                      line: parts.join('  ·  '),
                      action: nfo?.action ?? 'Open',
                      progress: nfo?.progress,
                    );
                  },
                ),
          ),
        );
      },
    );
  }

  static Widget _fallbackTitle(String name) => Text(
    name,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: Colors.white,
      fontSize: 22,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.3,
      shadows: [Shadow(color: Colors.black54, blurRadius: 12)],
    ),
  );

  Widget _block(
    BuildContext context, {
    required Widget titleWidget,
    required String line,
    required String action,
    required String? hold,
    required double? progress,
  }) {
    final app = AppThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        titleWidget,
        const SizedBox(height: 12),
        Row(
          children: [
            Flexible(
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: app.fade(app.core.tx, 0.74),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 16),
            if (hold != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: app.fade(app.core.tx, 0.30)),
                  borderRadius: app.shape.br(20),
                ),
                child: Text(
                  'HOLD  $hold',
                  style: TextStyle(
                    color: app.fade(app.core.tx, 0.72),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: app.core.tx.withValues(alpha: 0.92),
                borderRadius: app.shape.br(20),
              ),
              child: Text(
                'OK  $action',
                style: const TextStyle(
                  color: Color(0xFF12101F),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
        if (progress != null && progress > 0) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: app.shape.br(3),
            child: SizedBox(
              height: 5,
              child: ColoredBox(
                color: app.core.tx.withValues(alpha: 0.22),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One row of Tonight's Continue queue: a 16:9 still, the title, the episode
/// and a progress bar. Carries the same focus grammar and the same hold-OK
/// menu as a Continue Watching card, so nothing is lost by laying the row out
/// horizontally instead of as a poster.
class _TonightQueueRow extends StatefulWidget {
  final StremioMeta item;
  final double height;

  /// Width of the still. Capped by the row's width upstream — see
  /// [_SearchScreenState._tonightQueueList].
  final double thumbWidth;
  final FocusNode focusNode;
  final String? episode;
  final double? progress;

  /// Mirrors the board cards' bookmark mark — a title with a source already
  /// bound plays without picking one, and that is worth seeing here too.
  final bool hasBoundSource;
  final VoidCallback onFocused;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final VoidCallback onUp;
  final VoidCallback onDown;

  /// Held DOWN — see [_BoardCell.onDownHold]. Null keeps a held key stepping
  /// one row at a time.
  final VoidCallback? onDownHold;
  final VoidCallback onLeft;

  const _TonightQueueRow({
    required this.item,
    required this.height,
    required this.thumbWidth,
    required this.focusNode,
    required this.episode,
    required this.progress,
    required this.hasBoundSource,
    required this.onFocused,
    required this.onOpen,
    required this.onLongPress,
    required this.onUp,
    required this.onDown,
    this.onDownHold,
    required this.onLeft,
  });

  @override
  State<_TonightQueueRow> createState() => _TonightQueueRowState();
}

class _TonightQueueRowState extends State<_TonightQueueRow>
    with SingleTickerProviderStateMixin {
  bool _focused = false;
  bool _keyDown = false;
  bool _holdFired = false;
  bool _holding = false;

  /// Same 500ms hold-OK the Continue Watching cards use.
  static const _holdDuration = Duration(milliseconds: 500);
  late final AnimationController _holdController = AnimationController(
    vsync: this,
    duration: _holdDuration,
  );

  @override
  void initState() {
    super.initState();
    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _holdFired = true;
        setState(() => _holding = false);
        _holdController.reset();
        widget.onLongPress();
      }
    });
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  void _cancelHold() {
    _holdController.reset();
    if (_holding && mounted) setState(() => _holding = false);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      if (isActivateKey(event.logicalKey) ||
          event.logicalKey == LogicalKeyboardKey.space) {
        final wasPress = _keyDown && !_holdFired;
        _keyDown = false;
        _holdFired = false;
        _cancelHold();
        if (wasPress) widget.onOpen();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) {
        _keyDown = true;
        _holdFired = false;
        setState(() => _holding = true);
        _holdController.forward(from: 0);
      }
      // Swallow auto-repeat while held.
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.onUp();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (event is KeyRepeatEvent && widget.onDownHold != null) {
        widget.onDownHold!();
      } else {
        widget.onDown();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onLeft();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      // Nothing to the right of the queue — swallow it so Flutter's geometric
      // traversal can't wander into the rail below.
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final h = widget.height;
    final thumbW = widget.thumbWidth;
    final art = _wideArtUrl(widget.item);
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f) {
          _keyDown = false;
          _holdFired = false;
          _cancelHold();
        } else {
          widget.onFocused();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: widget.onOpen,
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          height: h,
          decoration: BoxDecoration(
            color: app.fade(app.core.tx, _focused ? 0.10 : 0.045),
            borderRadius: app.shape.br(10),
            border: Border.all(
              color: _focused ? app.core.tx : app.fade(app.core.tx, 0.06),
              width: _focused ? 2.5 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: app.shape.br(9),
            child: Row(
              children: [
                SizedBox(
                  width: thumbW,
                  height: h,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Color(0xFF171426)),
                      if (art != null && art.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: art,
                          fit: BoxFit.cover,
                          memCacheWidth: 420,
                          fadeInDuration: HomeTheme.imageFadeIn(true),
                          fadeOutDuration: HomeTheme.imageFadeOut(true),
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      if (widget.hasBoundSource)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Icon(
                            Icons.bookmark_rounded,
                            size: 15,
                            color: app.core.tx,
                            shadows: const [
                              Shadow(color: Colors.black, blurRadius: 6),
                            ],
                          ),
                        ),
                      if (_holding) const ColoredBox(color: Color(0x730A0810)),
                      if (_holding)
                        Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: AnimatedBuilder(
                              animation: _holdController,
                              builder: (context, _) =>
                                  CircularProgressIndicator(
                                    value: _holdController.value,
                                    strokeWidth: 2.5,
                                    color: app.core.tx,
                                    backgroundColor: Colors.white24,
                                  ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: app.core.tx,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                          ),
                        ),
                        if (widget.episode != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            widget.episode!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: app.fade(app.core.tx, 0.56),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (widget.progress != null) ...[
                          const SizedBox(height: 9),
                          ClipRRect(
                            borderRadius: app.shape.br(2),
                            child: SizedBox(
                              height: 4,
                              child: ColoredBox(
                                // 0.18 vanished against the row's own panel,
                                // so the fill read as a dash floating in
                                // space rather than a bar with a track.
                                color: app.core.tx.withValues(alpha: 0.28),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: widget.progress!.clamp(0.0, 1.0),
                                  heightFactor: 1,
                                  child: const ColoredBox(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
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

/// One row of Tonight's Continue Watching queue: which CW rail it came from
/// and which column within it (so the cell's FocusNode, progress, episode
/// label and open/remove actions all come from the row's own contract).
class _TonightQueueEntry {
  final _CanvasRail rail;
  final int col;
  const _TonightQueueEntry({required this.rail, required this.col});
}

class _CanvasFavFocus {
  final String? art;
  final BoxFit fit;
  final String title;
  final String subtitle;
  const _CanvasFavFocus({
    required this.art,
    this.fit = BoxFit.cover,
    required this.title,
    required this.subtitle,
  });
}

/// Canvas stage floor + full-bleed key art for the settled hero item. Sits
/// BELOW the underlay punch hole; the AnimatedSwitcher fade wraps only this
/// sibling, never the engine, so the hole's BlendMode.clear is untouched.
/// Metahub backdrop URLs that came back 404 this session — the same
/// memo the title-logo art keeps, for the same reason: without it every
/// focus on a title with no derived still re-requests a known-dead URL.
///
/// Bounded: a long session browsing paginated catalogs would otherwise keep
/// every miss for the life of the process. A full clear is fine — the cost of
/// forgetting is one re-request per title, exactly what the memo saves.
final Set<String> _deadBackdropUrls = <String>{};
const int _kDeadBackdropMemoMax = 512;

void _rememberDeadBackdrop(String url) {
  if (_deadBackdropUrls.length >= _kDeadBackdropMemoMax) {
    _deadBackdropUrls.clear();
  }
  _deadBackdropUrls.add(url);
}

class _CanvasArtLayer extends StatelessWidget {
  final ValueListenable<StremioMeta?> item;
  final ValueListenable<StremioMeta?> enriched;
  final int cacheWidth;
  final int cacheHeight;

  /// Non-null while a favourites cell has focus: its art overrides the hero
  /// pipeline's (contain-fit logos render centred over the floor instead of
  /// being cover-stretched across the canvas).
  final ValueListenable<_CanvasFavFocus?> fav;

  const _CanvasArtLayer({
    required this.item,
    required this.enriched,
    required this.fav,
    required this.cacheWidth,
    required this.cacheHeight,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return ValueListenableBuilder<StremioMeta?>(
      valueListenable: item,
      builder: (context, it, _) => ValueListenableBuilder<StremioMeta?>(
        valueListenable: enriched,
        builder: (context, en, _) => ValueListenableBuilder<_CanvasFavFocus?>(
          valueListenable: fav,
          builder: (context, fav, _) {
            // Enrichment merged over the catalog item: matched by canonical
            // IMDb identity (ids can differ in form), and a sparse /meta
            // record can't erase a backdrop the catalog already carried.
            final enr = (it != null && en != null && _sameCanvasTitle(it, en))
                ? en
                : null;
            // WIDE art first. The old chain fell straight from "no backdrop"
            // to the POSTER, which a 16:9 box has to crop to a horizontal
            // slice — on a title whose poster is a row of character portraits
            // that reads as several unrelated images stacked in one card. The
            // metahub still (derived synchronously from the IMDb id, exactly
            // like the title logo) is a real landscape frame and exists for
            // most titles; the poster stays as the last resort, applied by the
            // error branch below so a 404 still lands on something.
            final wide = it == null
                ? null
                : _firstNonEmpty(enr?.background, it.background) ??
                      (_deadBackdropUrls.contains(
                            _metahubBackgroundUrl(it) ?? '',
                          )
                          ? null
                          : _metahubBackgroundUrl(it));
            final posterUrl = (it?.poster?.isNotEmpty ?? false)
                ? it!.poster
                : null;
            final bg = wide ?? posterUrl ?? '';
            final Widget art;
            final favArt = fav?.art;
            if (fav != null) {
              if (favArt == null || favArt.isEmpty) {
                art = const SizedBox.shrink(key: ValueKey('canvas-art-none'));
              } else if (fav.fit == BoxFit.contain) {
                art = Center(
                  key: ValueKey('canvas-fav-logo-$favArt'),
                  child: FractionallySizedBox(
                    widthFactor: 0.38,
                    heightFactor: 0.38,
                    child: CachedNetworkImage(
                      imageUrl: favArt,
                      fit: BoxFit.contain,
                      memCacheWidth: 480,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                );
              } else {
                art = CachedNetworkImage(
                  key: ValueKey(
                    'canvas-fav-art-$favArt-${cacheWidth}x$cacheHeight',
                  ),
                  imageUrl: favArt,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  memCacheWidth: cacheWidth,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                );
              }
            } else if (bg.isEmpty) {
              art = const SizedBox.shrink(key: ValueKey('canvas-art-none'));
            } else {
              // A derived metahub still can 404 (not every title has one).
              // Remember that so the next focus doesn't ask again, and fall
              // back to the poster in place rather than to an empty stage.
              final derived =
                  wide != null &&
                  wide != enr?.background &&
                  wide != it?.background;
              art = CachedNetworkImage(
                key: ValueKey('$bg-${cacheWidth}x$cacheHeight'),
                imageUrl: bg,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                memCacheWidth: wide != null ? cacheWidth : null,
                memCacheHeight: wide == null ? cacheHeight : null,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                errorWidget: (_, __, ___) {
                  if (derived) _rememberDeadBackdrop(bg);
                  if (posterUrl == null || bg == posterUrl) {
                    return const SizedBox.shrink();
                  }
                  return CachedNetworkImage(
                    imageUrl: posterUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    memCacheHeight: cacheHeight,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  );
                },
              );
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                // Opaque floor: the app shell can never show through a missing
                // or still-decoding backdrop.
                ColoredBox(color: app.home.bg),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  // AnimatedSwitcher's DEFAULT layout centres its children under
                  // LOOSE constraints, so a BoxFit.cover image sizes to its own
                  // aspect instead of the box. On Canvas the box is the whole
                  // 16:9 screen and it looked identical either way — but Atrium's
                  // art column is nearly square, and there the backdrop
                  // letterboxed with ink bands above and below it. Expand both
                  // the incoming and outgoing child so "cover" means the box.
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    fit: StackFit.expand,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  ),
                  child: art,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The Canvas stage's constant lighting: a left column scrim (identity
/// legibility), a bottom ramp (tabs/shelf legibility) and a bottom-left
/// "text pocket" — a soft radial wash under the identity block. Premium OTT
/// scrims are far heavier than they look (85-95% ink at the text baseline);
/// because the falloff is gradual and in the page's own ink colour it reads
/// as LIGHTING, never as a plate behind the text — bright art (snow, skies,
/// white key art) stays legible without the stage going flat. Painted ABOVE
/// both the idle art and the live video — plain gradient draws over the
/// punch hole, the same on-device-proven pattern as the region feathers.
/// How a stage lights its art. Every variant is a set of CONSTANT gradients
/// painted above the art AND the video — plain draws over the punch hole, the
/// on-device-proven pattern (never an Opacity wrapper, never a tween).
enum _StageScrimVariant {
  /// Canvas / Deck / Tonight: left column + bottom ramp + a bottom-left text
  /// pocket, seating an edge-anchored identity block.
  canvas,

  /// Promenade: symmetric — a bottom ramp for the strip, a centred pocket
  /// under the identity, and a light top wash so the trailer pill reads.
  centered,

  /// Atrium: the art is a COLUMN, so the only left lighting it needs is a
  /// narrow feather melting into the ink panel at the seam, plus a bottom
  /// ramp under the poster wall.
  seam,
}

class _CanvasScrims extends StatelessWidget {
  /// Theater mode: ALL the stage lighting fades — the left column scrim, the
  /// bottom ramp and the text pocket exist to seat text and shelf that have
  /// receded, so the video gets the truly clean frame (the logo, gliding to
  /// the top-left corner, carries its own art shadows).
  final bool theater;

  final _StageScrimVariant variant;

  const _CanvasScrims({
    this.theater = false,
    this.variant = _StageScrimVariant.canvas,
  });

  static const _canvasLayers = <Widget>[
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xF00D0B1A), Color(0xA80D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.32, 0.66],
        ),
      ),
    ),
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF50D0B1A), Color(0xC20D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.20, 0.50],
        ),
      ),
    ),
    // The text pocket: centred under the identity block (lower-left
    // quadrant), dissolving well before mid-screen so the art/video
    // keeps its glow everywhere else.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.72, 0.55),
          radius: 0.95,
          colors: [Color(0xCC0D0B1A), Color(0x000D0B1A)],
          stops: [0.12, 1.0],
        ),
      ),
    ),
  ];

  static const _centeredLayers = <Widget>[
    // Bottom ramp — deeper than Canvas's: the strip sits lower and the
    // identity stands directly on it.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF70D0B1A), Color(0xCC0D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.24, 0.56],
        ),
      ),
    ),
    // Centre pocket: the symmetric twin of Canvas's corner pocket, seating
    // the centred logo + meta without flattening the frame's edges.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, 0.30),
          radius: 0.78,
          colors: [Color(0xB80D0B1A), Color(0x000D0B1A)],
          stops: [0.10, 1.0],
        ),
      ),
    ),
    // A whisper at the top so the TRAILER pill never sits on bright sky.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x730D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.22],
        ),
      ),
    ),
  ];

  static const _seamLayers = <Widget>[
    // The seam: a narrow melt into the ink panel on the left. Short, so the
    // art keeps its width — the panel beside it already carries the text.
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xF20D0B1A), Color(0x8C0D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.07, 0.22],
        ),
      ),
    ),
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF50D0B1A), Color(0xCC0D0B1A), Color(0x000D0B1A)],
          stops: [0.0, 0.36, 0.76],
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final layers = switch (variant) {
      _StageScrimVariant.canvas => _canvasLayers,
      _StageScrimVariant.centered => _centeredLayers,
      _StageScrimVariant.seam => _seamLayers,
    };
    return AnimatedOpacity(
      opacity: theater ? 0.0 : 1.0,
      duration: theater
          ? const Duration(milliseconds: 900)
          : const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: Stack(fit: StackFit.expand, children: layers),
    );
  }
}

/// How a stage sets its identity block.
enum _StageIdentityVariant {
  /// Canvas / Deck / Tonight: bottom-left, one meta line, three-line synopsis.
  stage,

  /// Atrium: a narrow ink column — the meta breaks onto two lines (facts, then
  /// genres) so it can never overrun the column, and the synopsis gets a
  /// fourth line because there is room for it.
  narrow,

  /// Promenade: centred, no synopsis — the composition is the point.
  centered,

  /// Mosaic: a fixed-height band above the wall — logo and one meta line,
  /// left-aligned, no synopsis (the grid is the content; this is a caption).
  headline,
}

/// The height a [_StageIdentityVariant.narrow] block needs before its synopsis
/// is worth reserving: logo, two meta lines, the slot itself and the air
/// between them, at the current text scale. Below this the caller asks for
/// [_StageIdentityVariant.headline] instead of clipping.
double _stageNarrowIdentityH(BuildContext context) {
  final t = MediaQuery.textScalerOf(context);
  return 56 + 10 + t.scale(23) * 1.3 * 2 + 6 + 10 + 78;
}

/// Canvas identity block: logo title-art (held EMPTY while loading, text only
/// when there's no URL or it 404s — the C5 "no text→logo flash" rule) over a
/// quiet meta line with the gold IMDb mark and a three-line synopsis. While
/// the ambient trailer plays, meta + synopsis fade away and the LOGO HOLDS
/// THE STAGE (the classic hero's premium move); any DPAD move brings them
/// back with the lights.
class _CanvasIdentity extends StatelessWidget {
  final ValueListenable<StremioMeta?> item;
  final ValueListenable<StremioMeta?> enriched;

  /// True while ambient video owns the stage — drives the meta/synopsis fade.
  final ValueListenable<bool> trailerShowing;

  final _StageIdentityVariant variant;

  /// Width the block may occupy — the text column's real width, so the logo
  /// and synopsis are capped by geometry rather than by a guess.
  final double maxWidth;

  const _CanvasIdentity({
    required this.item,
    required this.enriched,
    required this.trailerShowing,
    this.variant = _StageIdentityVariant.stage,
    this.maxWidth = 430,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final centered = variant == _StageIdentityVariant.centered;
    final narrow = variant == _StageIdentityVariant.narrow;
    final headline = variant == _StageIdentityVariant.headline;
    final noSynopsis = centered || headline;
    // The stage variant is Canvas's, and Canvas never capped its title or
    // meta line — only the synopsis. Keep that exactly, or long logo-less
    // titles start ellipsising where they never used to.
    final capWidth = variant != _StageIdentityVariant.stage;
    Widget capped(Widget child) => capWidth
        ? ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          )
        : child;
    final cross = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final align = centered ? TextAlign.center : TextAlign.start;
    final double logoMaxW = centered
        ? 380
        : min(maxWidth, narrow ? 340 : (headline ? 360 : 300));
    final double logoMaxH = centered ? 66 : (headline ? _kMosaicLogoH : 56);
    // Fixed synopsis slot (see below) — 3 lines on a stage, 4 in a column.
    final int synLines = narrow ? 4 : 3;
    final double synSlot = narrow ? 78 : 58;

    return ValueListenableBuilder<StremioMeta?>(
      valueListenable: item,
      builder: (context, it, _) => ValueListenableBuilder<StremioMeta?>(
        valueListenable: enriched,
        builder: (context, en, _) {
          final it0 = it;
          if (it0 == null) return const SizedBox.shrink();
          // Enrichment merged over the catalog item FIELD BY FIELD: matched
          // by canonical IMDb identity (catalog ids can be tmdb:… while the
          // /meta record is tt…), and a sparse /meta response — it may carry
          // only a rating — can never erase what the catalog already knew.
          final enr = (en != null && _sameCanvasTitle(it0, en)) ? en : null;
          final logo =
              _firstNonEmpty(enr?.logo, it0.logo) ?? _metahubLogoUrl(it0);
          final rating = enr?.imdbRating ?? it0.imdbRating;
          final year = _firstNonEmpty(enr?.year, it0.year);
          final runtime = _firstNonEmpty(enr?.runtime, it0.runtime);
          final genres = (enr?.genres != null && enr!.genres!.isNotEmpty)
              ? enr.genres
              : it0.genres;
          final description = _firstNonEmpty(enr?.description, it0.description);
          final titleText = Text(
            it0.name,
            maxLines: narrow ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: TextStyle(
              color: app.core.tx,
              fontSize: headline ? _kStageHeadlineTitleSize : 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              height: 1.05,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 14)],
            ),
          );
          final genreText = (genres != null && genres.isNotEmpty)
              ? genres.take(2).join(' · ')
              : null;
          // The narrow column splits the line rather than ellipsising it.
          final metaParts = <String>[
            it0.type == 'series' ? 'SERIES' : 'MOVIE',
            if (year != null) year,
            if (runtime != null) runtime,
            if (!narrow && !headline && genreText != null) genreText,
          ];
          // Headline stands in for narrow on short columns, so it wraps the
          // genres the same way — in the facts row they would just be the
          // first thing ellipsised away.
          final wrapGenres = narrow || headline;
          final metaStyle = TextStyle(
            color: app.fade(app.core.tx, 0.7),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          );
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            // AnimatedSwitcher's DEFAULT layout centers its child — which
            // floated the whole identity block to mid-screen, off the left
            // scrim column it was designed to stand on. Pin it to the edge
            // the variant is anchored to.
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: centered
                  ? Alignment.bottomCenter
                  : Alignment.bottomLeft,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            ),
            child: Column(
              key: ValueKey('canvas-id-${it0.id}'),
              crossAxisAlignment: cross,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (logo != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: logoMaxW,
                      maxHeight: logoMaxH,
                    ),
                    child: CachedNetworkImage(
                      imageUrl: logo,
                      fit: BoxFit.contain,
                      alignment: centered
                          ? Alignment.bottomCenter
                          : Alignment.bottomLeft,
                      memCacheWidth: 480,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (_, __) => SizedBox(height: logoMaxH),
                      errorWidget: (_, __, ___) => capped(titleText),
                    ),
                  )
                else
                  capped(titleText),
                const SizedBox(height: 10),
                // Meta + synopsis fade while the ambient trailer plays; the
                // logo above stays. Sibling-above-the-hole opacity — the
                // on-device-proven overlay pattern (region feathers/chip).
                ValueListenableBuilder<bool>(
                  valueListenable: trailerShowing,
                  builder: (context, showing, kid) => AnimatedOpacity(
                    opacity: showing ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 480),
                    curve: Curves.easeOut,
                    child: kid,
                  ),
                  child: Column(
                    crossAxisAlignment: cross,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      capped(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: centered
                              ? MainAxisAlignment.center
                              : MainAxisAlignment.start,
                          children: [
                            if (rating != null) ...[
                              const Text(
                                'IMDb',
                                style: TextStyle(
                                  color: Color(0xFFF5C518),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                rating.toStringAsFixed(1),
                                style: TextStyle(
                                  color: app.fade(app.core.tx, 0.9),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  '·',
                                  style: TextStyle(
                                    color: app.fade(app.core.tx, 0.3),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                            Flexible(
                              child: Text(
                                metaParts.join('  ·  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: metaStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Narrow columns carry genres on their own line rather
                      // than ellipsising the facts away.
                      if (wrapGenres && genreText != null) ...[
                        const SizedBox(height: 6),
                        capped(
                          Text(
                            genreText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: metaStyle.copyWith(
                              color: app.fade(app.core.tx, 0.46),
                            ),
                          ),
                        ),
                      ],
                      // Fixed-height synopsis slot: the description usually
                      // lands ~300ms after the settle (/meta enrichment), and
                      // this block is BOTTOM-anchored — reserving the lines
                      // keeps the logo from jumping when the text arrives.
                      // Promenade has no synopsis at all, so it reserves
                      // nothing.
                      if (!noSynopsis) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: synSlot,
                          child: description != null
                              ? ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: maxWidth,
                                  ),
                                  child: Text(
                                    description,
                                    maxLines: synLines,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: app.fade(app.core.tx, 0.78),
                                      fontSize: 12.5,
                                      height: 1.5,
                                      fontWeight: FontWeight.w500,
                                      // Crisp, tight shadow — a seasoning under
                                      // the scrim, never a smear (big radii
                                      // read as muddy text on TV panels).
                                      shadows: const [
                                        Shadow(
                                          color: Color(0xBF000000),
                                          blurRadius: 3,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// The board's card focus chrome ([CardFocusRise]) moved to
// widgets/home/card_focus_rise.dart — the Discover stage's shelf wears the
// same grammar, and focus feel has to be tuned in exactly one place.

/// Stremio-style poster card: clean rounded poster with a soft shadow that
/// lifts on hover/focus. Deliberately minimal — no title band, no MOVIE/rating
/// chips — so the artwork carries the rail exactly like Stremio's board.
class _StremioCard extends StatefulWidget {
  final StremioMeta item;
  final bool isTelevision;
  final FocusNode focusNode;
  final bool hasBoundSource;

  /// Focus ring override (Canvas cells pass white). Null keeps the classic
  /// violet-on-TV grammar.
  final Color? ringColor;

  /// 0..1 watched fraction — draws a bottom progress bar when non-null.
  final double? progress;

  /// Subtle 'S2 · E5' badge for a Continue Watching series card, or null.
  final String? episodeLabel;

  /// Long-press quick-play (mobile/desktop). Null hides the shortcut.
  final VoidCallback? onQuickPlay;

  /// Long-press — and hold-OK on TV — opens a menu instead of playing. Wins
  /// over [onQuickPlay] when both are set (Continue Watching cards).
  final VoidCallback? onLongPress;
  final VoidCallback onOpen;

  /// Shared-element tag: when set, the poster flies into the detail page's
  /// backdrop on open (and back on pop). Unique per CELL, so a title showing
  /// on two rows never trips Hero's duplicate-tag assert.
  final String? heroTag;

  /// Cell shape. 2:3 everywhere except Promenade's wide strip (16/9) — only
  /// the box changes; focus feel, hold-OK, progress and badges are identical.
  final double aspectRatio;

  /// Art override. Null uses [item].poster (the row default); the wide cells
  /// pass a derived 16:9 still so a landscape box isn't filled with a
  /// centre-cropped poster.
  final String? artUrl;

  /// Dim while unfocused — see [CardFocusRise.restVeil].
  final Color? restVeil;

  const _StremioCard({
    required this.item,
    required this.isTelevision,
    required this.focusNode,
    required this.hasBoundSource,
    this.ringColor,
    this.progress,
    this.episodeLabel,
    this.onQuickPlay,
    this.onLongPress,
    required this.onOpen,
    this.heroTag,
    this.aspectRatio = 2 / 3,
    this.artUrl,
    this.restVeil,
  });

  @override
  State<_StremioCard> createState() => _StremioCardState();
}

class _StremioCardState extends State<_StremioCard>
    with SingleTickerProviderStateMixin {
  bool _focused = false;
  bool _hovered = false;
  bool _keyDown = false;
  bool get _active => _focused || _hovered;

  /// Hold-OK on TV (same 500ms as the IPTV channel row's hold-to-favourite) —
  /// only armed on cards that have an [_StremioCard.onLongPress] menu. A short
  /// press still opens the title. Driven by a controller so the focused card
  /// can show the hold filling, making an otherwise-invisible gesture
  /// discoverable.
  static const _holdDuration = Duration(milliseconds: 500);
  late final AnimationController _holdController = AnimationController(
    vsync: this,
    duration: _holdDuration,
  );
  bool _holdFired = false;
  bool _holding = false;

  bool get _holdEnabled => widget.isTelevision && widget.onLongPress != null;

  @override
  void initState() {
    super.initState();
    _holdController.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      _holdFired = true;
      if (mounted) setState(() => _holding = false);
      _holdController.reset();
      widget.onLongPress?.call();
    });
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  /// Abandon an in-flight hold (focus left, or the key came back up).
  void _cancelHold() {
    _holdController.reset();
    if (_holding && mounted) setState(() => _holding = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final item = widget.item;
    final wide = widget.aspectRatio > 1;
    final poster = widget.artUrl ?? item.poster;
    final isMovie = item.type.toLowerCase() == 'movie';
    final supportsWatched = isMovie || item.type.toLowerCase() == 'series';
    final movieId = item.effectiveImdbId ?? item.id;
    // Focus visuals (scale + shadow + ring on one curve) live in the shared
    // [CardFocusRise] so tuning lands once for every board card.
    final List<Widget> layers = [
      if (poster != null && poster.isNotEmpty)
        CachedNetworkImage(
          imageUrl: poster,
          fit: BoxFit.cover,
          // Decode board posters at a capped width — tiles are small,
          // full-res posters are the main memory churn while scrolling.
          // A wide cell is ~2.7x the width of a poster at the same height,
          // so it gets a proportionally larger cap rather than a blur.
          memCacheWidth: widget.isTelevision
              ? (wide ? 640 : 320)
              : (wide ? 860 : 480),
          // Short fade on TV (see HomeTheme.imageFadeIn): posters arriving
          // as hard-snapping rectangles was the last cheap tell at the card
          // level; memory-cached loads still land settled with no fade.
          fadeInDuration: HomeTheme.imageFadeIn(widget.isTelevision),
          fadeOutDuration: HomeTheme.imageFadeOut(widget.isTelevision),
          placeholder: (_, __) => _placeholder(item.name),
          // A derived wide still (MetaHub) can 404 where the poster exists —
          // cover-crop the poster into the wide cell before giving up on art.
          errorWidget: (_, __, ___) =>
              poster != item.poster &&
                  item.poster != null &&
                  item.poster!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: item.poster!,
                  fit: BoxFit.cover,
                  memCacheWidth: widget.isTelevision ? 320 : 480,
                  fadeInDuration: HomeTheme.imageFadeIn(widget.isTelevision),
                  fadeOutDuration: HomeTheme.imageFadeOut(widget.isTelevision),
                  placeholder: (_, __) => _placeholder(item.name),
                  errorWidget: (_, __, ___) => _placeholder(item.name),
                )
              : _placeholder(item.name),
        )
      else
        _placeholder(item.name),
      // A landscape still rarely carries its title the way poster art does,
      // and off TV there is no hero identity revealing the focused card —
      // so a wide TOUCH card labels itself. TV keeps clean cards: browsing
      // there puts every focused title's name in the hero (Promenade
      // grammar). Sits under the badges; the scrim keeps them readable too.
      if (wide && !widget.isTelevision) ...[
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              height: 52,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xB8000000)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          // Clear the CW episode badge and progress bar, which own the
          // bottom edge when present.
          bottom:
              (widget.episodeLabel != null ? 22.0 : 0.0) +
              (widget.progress != null ? 11.0 : 8.0),
          child: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: app.onGlass,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
              shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ),
      ],
      if (supportsWatched)
        Positioned(
          top: 7,
          right: 7,
          child: MovieWatchedBadge(
            imdbId: movieId,
            contentType: item.type,
            compact: true,
          ),
        ),
      if (widget.hasBoundSource)
        Positioned(
          top: 8,
          left: supportsWatched ? 8 : null,
          right: supportsWatched ? null : 8,
          child: Icon(
            Icons.bookmark_rounded,
            size: 18,
            color: app.core.tx,
            shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
          ),
        ),
      // Subtle season/episode badge for a Continue Watching series
      // card — sits just above the progress bar, bottom-left.
      if (widget.episodeLabel != null)
        Positioned(
          left: 6,
          bottom: widget.progress != null ? 11 : 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.66),
              borderRadius: app.shape.br(5),
            ),
            child: Text(
              widget.episodeLabel!,
              style: TextStyle(
                // On the glass, not the page — see AppTheme.onGlass.
                color: app.onGlass,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      // Continue Watching progress — a red bar pinned to the bottom of
      // the poster (Stremio-style, clipped to the rounded corners). A
      // faint dark track keeps it readable on bright posters.
      if (widget.progress != null)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: 5,
            color: Colors.black.withValues(alpha: 0.45),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: widget.progress!.clamp(0.0, 1.0),
              heightFactor: 1,
              child: const ColoredBox(color: _kCwProgressRed),
            ),
          ),
        ),
      // Hold-OK feedback: a dim scrim with a filling ring, shown only
      // while OK is actually held down (so it costs nothing at rest).
      if (_holding) _holdLayer(),
    ];

    final posterCard = CardFocusRise(
      active: _active,
      isTelevision: widget.isTelevision,
      ringColor: widget.ringColor,
      aspectRatio: widget.aspectRatio,
      restVeil: widget.restVeil,
      children: layers,
    );

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f) {
          // Focus left mid-press — disarm, so a stray key-up can't open a card
          // the user never pressed and a half-filled hold can't fire.
          _keyDown = false;
          _holdFired = false;
          _cancelHold();
        }
        if (f) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              // TV glides too (was a hard Duration.zero jump — the single
              // biggest "not native" tell). Kept SHORT (140ms): each held-DPAD
              // repeat retargets the in-flight scroll from the CURRENT offset,
              // and a short glide converges on the focused card fast enough
              // that motion never reads as trailing the keypress (200ms felt
              // laggy on-device).
              duration: widget.isTelevision
                  ? const Duration(milliseconds: 140)
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        if (isActivateKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space) {
          // Cards with a long-press menu (Continue Watching) tell a tap from a
          // hold; every other card keeps the plain press-to-open path.
          if (_holdEnabled) {
            if (event is KeyDownEvent) {
              _keyDown = true;
              _holdFired = false;
              setState(() => _holding = true);
              _holdController.forward(from: 0);
            } else if (event is KeyUpEvent) {
              // A press this card actually started, released before the hold
              // completed → open. A key-up with no matching key-down (focus
              // arrived mid-press) is swallowed.
              final wasPress = _keyDown && !_holdFired;
              _keyDown = false;
              _holdFired = false;
              _cancelHold();
              if (wasPress) widget.onOpen();
            }
            // Swallow auto-repeat while the key is held.
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent) {
            _keyDown = true;
            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            if (_keyDown) widget.onOpen();
            _keyDown = false;
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) {
          if (mounted) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _hovered = false);
        },
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          // Guarded because this card now sits UNDER a dialog: on TV remotes
          // where Select also emits a tap, picking a row in the long-press menu
          // pops it and lets that tap through to the card — which would open
          // the detail page on top of the play/removal the user actually asked
          // for. The dialog rows mark the key action; this drops its echo.
          onTap: () {
            if (DialogTapGuard.shouldIgnoreTap()) return;
            widget.onOpen();
          },
          // Touch/desktop counterpart of TV's hold-OK: the menu when there is
          // one, else the old long-press-to-play.
          onLongPress: widget.onLongPress ?? widget.onQuickPlay,
          behavior: HitTestBehavior.opaque,
          // No title beneath the poster — Stremio lets the artwork carry the
          // rail; the title lives on the hero (focused) and the detail page.
          //
          // RepaintBoundary so the focus pop (scale tween + shadow flip)
          // repaints only this card's layer, not the whole row viewport.
          child: RepaintBoundary(
            child: widget.heroTag == null
                ? posterCard
                : Hero(
                    tag: widget.heroTag!,
                    // Card-side shuttle covers BOTH directions (the backdrop hero
                    // defines none): the flight always shows the poster, growing
                    // into the detail backdrop on push and shrinking home on pop.
                    flightShuttleBuilder: _posterFlightShuttle,
                    child: posterCard,
                  ),
          ),
        ),
      ),
    );
  }

  /// Hold-OK feedback layer — a dim scrim with a filling ring, shown only
  /// while OK is actually held down (so it costs nothing at rest). Shared by
  /// the poster and wide layer sets.
  Widget _holdLayer() {
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.42),
          child: Center(
            child: SizedBox(
              width: 34,
              height: 34,
              child: AnimatedBuilder(
                animation: _holdController,
                builder: (_, __) => CircularProgressIndicator(
                  value: _holdController.value,
                  strokeWidth: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.22),
                  valueColor: const AlwaysStoppedAnimation(kStremioFocusRing),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(String title) {
    final app = AppThemeScope.of(context);
    return Container(
      // Subtle vertical gradient instead of a flat fill: while art loads the
      // tile reads as a designed surface, not a dead rectangle. Static —
      // no shimmer, so a board full of placeholders costs nothing per frame.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1D1B2E), Color(0xFF15141F), Color(0xFF100E18)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: app.fade(app.core.tx, 0.5),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// The "See All ›" affordance in a rail header — a mouse/tap entry to the
/// full-screen See-All screen, shown on desktop only. Kept understated (quiet
/// grey that brightens on hover, no accent fill) so it doesn't compete with the
/// posters. TV rails are chrome-free and paginate on scroll instead.
class _SeeAllLink extends StatefulWidget {
  final VoidCallback onTap;
  final bool compact;
  const _SeeAllLink({required this.onTap, this.compact = false});

  @override
  State<_SeeAllLink> createState() => _SeeAllLinkState();
}

class _SeeAllLinkState extends State<_SeeAllLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final color = _hover ? app.core.tx : app.fade(app.core.tx, 0.5);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: _hover ? app.fade(app.core.tx, 0.08) : Colors.transparent,
            borderRadius: app.shape.br(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.compact ? 'All' : 'See All',
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 17, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// The kinds of leading saved-content rows. Render order (Watchlist Movies,
/// Watchlist Series, Playlist, Debrify TV, Stremio TV, IPTV) is defined by
/// [_SearchScreenState._favRowKinds], the single source of truth for rendering
/// and the index-based DPAD focus wiring.
enum _FavKind {
  watchlistMovies,
  watchlistSeries,
  iptv,
  debrify,
  stremio,
  playlist,
}

/// One visible favourites-family row: a singleton [kind] row ([list] == -1),
/// or — for `kind == _FavKind.iptv` with [list] >= 0 — the IPTV custom-list
/// row at that index of [_SearchScreenState._iptvListRows]. Value-equal so
/// rebuilt ref lists compare cleanly.
class _FavRowRef {
  final _FavKind kind;
  final int list;
  const _FavRowRef(this.kind, [this.list = -1]);

  bool get isIptvList => list >= 0;

  @override
  bool operator ==(Object other) =>
      other is _FavRowRef && other.kind == kind && other.list == list;

  @override
  int get hashCode => Object.hash(kind, list);
}

/// One opted-in IPTV custom list shown as a Home row. [channels] are rebuilt
/// from the stored list metadata alone (no provider fetch) with their full
/// presentation fields — a list can hold VOD alongside live channels, and the
/// content type drives both the play routing and whether focus retunes the
/// hero live preview. [nodes] are owned here and reconciled by [listId]
/// across reloads (see [_SearchScreenState._loadIptvListRows]).
class _IptvListRow {
  final String listId;
  String title;
  List<IptvChannel> channels;
  final List<FocusNode> nodes = [];
  _IptvListRow(this.listId, this.title) : channels = const [];
}

/// Generic DPAD arrow-handling wrapper for a favourites-row card — the arrow
/// counterpart to [_BoardCell] for the IPTV / Debrify TV / Stremio TV rows.
/// Holds no focus itself — the inner [_ArtPoster] does; this only routes
/// left/right within the row and up/down out of it, matching the catalog
/// cards' navigation exactly.
class _FavArtCell extends StatelessWidget {
  final bool isTelevision;
  final int column;
  final List<FocusNode> rowNodes;
  final VoidCallback onUp;
  final VoidCallback onDown;

  /// Horizontal overrides — see [_BoardCell.onLeft]. Null keeps the row
  /// grammar.
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  /// Held up/down — see [_BoardCell.onUpHold].
  final VoidCallback? onUpHold;
  final VoidCallback? onDownHold;
  final Widget child;

  const _FavArtCell({
    required this.isTelevision,
    required this.column,
    required this.rowNodes,
    required this.onUp,
    required this.onDown,
    this.onLeft,
    this.onRight,
    this.onUpHold,
    this.onDownHold,
    required this.child,
  });

  KeyEventResult _handleArrows(FocusNode node, KeyEvent event) {
    // Act on key-down AND key-repeat (held DPAD). If we let a repeat fall
    // through as `ignored`, Flutter's default geometric traversal fires and
    // jumps focus into an adjacent row — so only key-ups are passed on.
    if (!isTelevision || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (onLeft != null) {
        onLeft!();
      } else if (column > 0) {
        rowNodes[column - 1].requestFocus();
      } else {
        MainPageBridge.focusTvSidebar?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (onRight != null) {
        onRight!();
      } else if (column < rowNodes.length - 1) {
        rowNodes[column + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (event is KeyRepeatEvent && onUpHold != null) {
        onUpHold!();
      } else {
        onUp();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (event is KeyRepeatEvent && onDownHold != null) {
        onDownHold!();
      } else {
        onDown();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleArrows,
      child: child,
    );
  }
}

/// Stremio-shaped artwork card for a favourite that has a real image (a Stremio
/// TV channel's now-playing poster, or an IPTV channel's logo). Shows the image
/// over a purple gradient — with a live-TV glyph fallback when it's missing or
/// fails to load — and the title below, matching [_StremioCard]'s size, corner
/// radius, hover/focus lift and selection ring so the row reads as one board.
class _ArtPoster extends StatefulWidget {
  final String? imageUrl;
  final String title;

  /// How the image fills the 2:3 tile — cover for posters, contain for logos.
  final BoxFit imageFit;

  /// Optional top-left badge text (e.g. a channel number) drawn over the tile.
  final String? badge;

  /// When true, a red "LIVE" pill is drawn top-right — signalling that this is a
  /// channel and the artwork is what's playing on it right now.
  final bool live;

  /// Optional resume-progress fraction (0..1). When set, a thin progress bar is
  /// drawn along the bottom edge of the poster (used by the Playlist row).
  final double? progress;
  final bool isTelevision;

  /// Focus ring override (Canvas favourites cells pass white); null keeps
  /// the classic violet-on-TV grammar.
  final Color? ringColor;
  final FocusNode focusNode;
  final VoidCallback onOpen;

  /// Fired when this card gains DPAD focus (TV only — see [_ArtPosterState]'s
  /// `onFocusChange`). The IPTV favourites rows use it to retune the hero's
  /// video region (boxed on classic, full-bleed on Canvas) to the focused
  /// channel's live stream; other favourites rows pass a clearing/stage
  /// callback so a live feed never lingers when focus moves off IPTV without
  /// passing through a catalog/CW card first.
  final VoidCallback? onFocused;

  const _ArtPoster({
    required this.imageUrl,
    required this.title,
    required this.isTelevision,
    required this.focusNode,
    required this.onOpen,
    this.imageFit = BoxFit.cover,
    this.badge,
    this.live = false,
    this.progress,
    this.ringColor,
    this.onFocused,
  });

  @override
  State<_ArtPoster> createState() => _ArtPosterState();
}

class _ArtPosterState extends State<_ArtPoster> {
  bool _focused = false;
  bool _hovered = false;
  bool _keyDown = false;
  bool get _active => _focused || _hovered;

  Widget _glyph() {
    final app = AppThemeScope.of(context);
    return Center(
      child: Icon(
        Icons.live_tv_rounded,
        size: 40,
        color: app.fade(app.home.chromeAccent, _active ? 1 : 0.85),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final url = widget.imageUrl;
    final hasImage = url != null && url.isNotEmpty;

    // Focus visuals (scale + shadow + ring on one curve) live in the shared
    // [CardFocusRise] so tuning lands once for every board card.
    final posterCard = CardFocusRise(
      active: _active,
      isTelevision: widget.isTelevision,
      ringColor: widget.ringColor,
      children: [
        // Base gradient — the fallback backdrop and the ground behind
        // any letterboxed (contain-fit) logo.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A1D5C), Color(0xFF1A1440), Color(0xFF0D0B1A)],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),
        if (hasImage)
          Padding(
            padding: widget.imageFit == BoxFit.contain
                ? const EdgeInsets.all(12)
                : EdgeInsets.zero,
            child: CachedNetworkImage(
              imageUrl: url,
              fit: widget.imageFit,
              memCacheWidth: widget.isTelevision ? 320 : 480,
              // Short fade on TV (see HomeTheme.imageFadeIn) — cached loads
              // land settled with no fade.
              fadeInDuration: HomeTheme.imageFadeIn(widget.isTelevision),
              fadeOutDuration: HomeTheme.imageFadeOut(widget.isTelevision),
              placeholder: (_, __) => _glyph(),
              errorWidget: (_, __, ___) => _glyph(),
            ),
          )
        else
          _glyph(),
        // Optional channel-number badge, top-left.
        if (widget.badge != null)
          Positioned(
            top: 10,
            left: 10,
            child: Text(
              widget.badge!,
              style: TextStyle(
                color: app.fade(app.core.tx, 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
        // "LIVE" pill, top-right — marks this as a channel currently
        // playing the shown artwork.
        if (widget.live)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: app.shape.br(6),
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
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: app.core.tx,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Resume-progress bar along the bottom edge (Playlist row).
        if (widget.progress != null && widget.progress! > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              height: 4,
              child: Stack(
                children: [
                  Container(color: Colors.black.withValues(alpha: 0.4)),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: widget.progress!,
                    child: Container(color: _kCwProgressRed),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f) _keyDown = false;
        if (f) {
          widget.onFocused?.call();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              // TV glides too (was a hard jump) — see _StremioCard: repeated
              // DPAD moves retarget the in-flight scroll, so held browsing
              // stays one continuous motion. Short on purpose; 200ms trailed
              // the keypress on-device.
              duration: widget.isTelevision
                  ? const Duration(milliseconds: 140)
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        if (isActivateKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space) {
          if (event is KeyDownEvent) {
            _keyDown = true;
            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            if (_keyDown) widget.onOpen();
            _keyDown = false;
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) {
          if (mounted) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _hovered = false);
        },
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onOpen,
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              posterCard,
              const SizedBox(height: _kArtTitleGap),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                maxLines: _kArtTitleMaxLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _active ? app.core.tx : app.fade(app.core.tx, 0.92),
                  fontSize: _kArtTitleFontSize,
                  fontWeight: FontWeight.w600,
                  height: _kArtTitleHeight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Catalog / Keyword segmented toggle.
class _ModeToggle extends StatelessWidget {
  final _Mode mode;
  final bool isTelevision;

  /// When true the two segments split the full available width (used when the
  /// toggle is stacked below the search box on narrow screens).
  final bool fullWidth;
  final ValueChanged<_Mode> onChanged;

  /// TV-only DPAD focus nodes for the segments (null off-TV, where the
  /// InkWell handles pointer taps and normal Tab traversal instead).
  final FocusNode? catalogNode;
  final FocusNode? keywordNode;

  /// Leave the toggle back to the search field (arrow-up, or arrow-left off the
  /// leftmost segment) / down into the board content.
  final VoidCallback? onLeaveToField;
  final VoidCallback? onLeaveToContent;

  const _ModeToggle({
    required this.mode,
    required this.isTelevision,
    required this.onChanged,
    this.fullWidth = false,
    this.catalogNode,
    this.keywordNode,
    this.onLeaveToField,
    this.onLeaveToContent,
  });

  /// DPAD handling for a focused segment: select switches mode, arrows move
  /// between the segments and out to the field (up/left) or content (down).
  KeyEventResult _handleSegmentKey(_Mode value, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
      onChanged(value);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      onLeaveToField?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      onLeaveToContent?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      switch (value) {
        case _Mode.keyword:
          catalogNode?.requestFocus();
        case _Mode.catalog:
          onLeaveToField?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      switch (value) {
        case _Mode.catalog:
          keywordNode?.requestFocus();
        case _Mode.keyword:
          break; // rightmost — nothing beyond
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    // With the keyword surface gated off for this profile there is no
    // choice to present — the toggle disappears rather than showing a
    // single working segment beside a dead one.
    if (!ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch)) {
      return const SizedBox.shrink();
    }
    final catalog = _segment(
      context,
      _Mode.catalog,
      'Catalog',
      Icons.grid_view_rounded,
    );
    final keyword = _segment(
      context,
      _Mode.keyword,
      'Keyword',
      Icons.bolt_rounded,
    );
    return Container(
      height: isTelevision ? 54 : 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: app.shape.br(14),
        border: Border.all(color: app.fade(app.core.tx, 0.08)),
      ),
      child: Row(
        mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
        children: fullWidth
            ? [Expanded(child: catalog), Expanded(child: keyword)]
            : [catalog, keyword],
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    _Mode value,
    String label,
    IconData icon,
  ) {
    final app = AppThemeScope.of(context);
    final on = mode == value;
    final node = switch (value) {
      _Mode.catalog => catalogNode,
      _Mode.keyword => keywordNode,
    };

    Widget content(bool focused) => AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.symmetric(horizontal: isTelevision ? 16 : 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? app.home.chromeAccent : Colors.transparent,
        borderRadius: app.shape.br(10),
        // A white ring shows the remote's DPAD position. Drawn whenever the
        // segment is focused — including the selected one, since focus lands
        // there first (its accent fill alone wouldn't signal focus moved).
        border: Border.all(
          color: focused ? app.fade(app.core.tx, 0.9) : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            // Scored against the fill, not hardcoded white: chromeAccent IS
            // the accent, and 17 of the 18 selectable themes have one where
            // white fails — Noir's and Frost's are pure #FFFFFF, so the
            // selected segment was a white label on a white bar. inkOn
            // returns white on legacy's #7B5CFF (4.36, over the threshold),
            // so this is a no-op today.
            color: on
                ? app.inkOn(app.home.chromeAccent)
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: isTelevision ? 14 : 13,
              fontWeight: FontWeight.w700,
              color: on
                  ? app.inkOn(app.home.chromeAccent)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    if (node == null) {
      return InkWell(
        onTap: () => onChanged(value),
        borderRadius: app.shape.br(10),
        child: content(false),
      );
    }

    // The wrapping Focus owns the keyboard/DPAD focus node; the InkWell stays
    // pointer-only (canRequestFocus:false) so it doesn't compete for focus.
    return Focus(
      focusNode: node,
      onKeyEvent: (n, event) => _handleSegmentKey(value, event),
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return InkWell(
            onTap: () => onChanged(value),
            borderRadius: app.shape.br(10),
            canRequestFocus: false,
            child: content(focused),
          );
        },
      ),
    );
  }
}

/// A pushable manual sources list for a catalog title/episode. Searches its own
/// torrent sources (own loading), renders them as [TorrentResultRow]s, and on
/// tap plays via the isolated service with the FULL source list + content
/// metadata (so the in-player Sources switcher + Continue Watching both work).
