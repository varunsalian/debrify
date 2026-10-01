import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/hero_metadata_presentation.dart';
import '../../../models/metadata_preferences.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../widgets/home/home_theme.dart';
import '../models/home_card_metadata.dart';
import 'home_card_metadata_view.dart';
import 'home_hero_surface.dart';
import 'home_hero_transitions.dart';
import 'home_hero_tint_surface.dart';
import 'home_hero_title_art.dart';
import 'home_hero_identity.dart';
import '../../../ui/core/trailer_indicators.dart';

/// The Stremio-style spotlight. Reflects the currently focused board title —
/// backdrop bleeding in from the right behind a left/bottom scrim, with title,
/// meta line and a short synopsis.
class HomeHeroSpotlight extends StatefulWidget {
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
  /// on the RIGHT (see [HomeHeroTrailerLayer]). The spotlight then keeps its
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
  /// in the board layer BENEATH this spotlight (see [HomeHeroTrailerLayer]), so
  /// the static backdrop image fades out on this signal to reveal it — that
  /// fade IS the image→video crossfade. The Ken Burns drift also freezes
  /// while hidden (no point re-rasterising an invisible layer every frame).
  final ValueListenable<bool>? trailerShowing;

  /// Host-driven "an IPTV favourite has taken the boxed video region" signal
  /// (see the live hero layer). [item]/[background]/[tint] all belong to the
  /// previously-focused CATALOG title — once an unrelated live channel is
  /// playing in the region, this spotlight's colour field and identity block
  /// (title/meta/plot, all about that stale catalog title) fade out rather
  /// than sit there describing something that isn't playing. Null outside
  /// Home (no IPTV favourites row to trigger it).
  final ValueListenable<bool>? liveTakeover;

  const HomeHeroSpotlight({
    super.key,
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
  State<HomeHeroSpotlight> createState() => _HomeHeroSpotlightState();
}

class _HomeHeroSpotlightState extends State<HomeHeroSpotlight>
    with TickerProviderStateMixin {
  StremioMeta? _hostBaseline;
  StremioMeta get _originalMetadata => _hostBaseline ??= _buildHostBaseline();

  StremioMeta _buildHostBaseline() => mergeHeroMetadata(
    widget.item,
    StremioMeta(
      id: widget.item.id,
      type: widget.item.type,
      name: widget.item.name,
      background: widget.background,
      description: widget.description,
      runtime: widget.runtime,
      logo: widget.logo,
      imdbRating: widget.rating,
    ),
  );

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
  void didUpdateWidget(HomeHeroSpotlight oldWidget) {
    if (!identical(oldWidget.item, widget.item) ||
        oldWidget.background != widget.background ||
        oldWidget.description != widget.description ||
        oldWidget.runtime != widget.runtime ||
        oldWidget.logo != widget.logo ||
        oldWidget.rating != widget.rating) {
      _hostBaseline = null;
    }
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.trailerShowing, widget.trailerShowing)) {
      oldWidget.trailerShowing?.removeListener(_onHeroCoverChanged);
      widget.trailerShowing?.addListener(_onHeroCoverChanged);
    }
    if (!identical(oldWidget.liveTakeover, widget.liveTakeover)) {
      oldWidget.liveTakeover?.removeListener(_onHeroCoverChanged);
      widget.liveTakeover?.addListener(_onHeroCoverChanged);
    }
    if (oldWidget.boxedTrailer != widget.boxedTrailer) _syncMotionGates();
    if (oldWidget.item.id != widget.item.id && _textOk) {
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
  Widget build(BuildContext context) =>
      HomeCardMetadataView(original: _originalMetadata, builder: _buildHero);

  Widget _buildHero(BuildContext context, HomeCardMetadataState metadata) {
    final app = AppThemeScope.of(context);
    final item = metadata.presented;
    final transitions = HomeHeroTransitions(
      boxedTrailer: widget.boxedTrailer,
      showing: widget.trailerShowing,
      liveTakeover: widget.liveTakeover,
    );
    final background = metadata.usesProvider(MetadataCategory.backgrounds)
        ? item.background
        : widget.background;
    final description = metadata.usesProvider(MetadataCategory.information)
        ? item.description
        : widget.description;
    final isTelevision = widget.isTelevision;
    final height = widget.height;
    final rating = widget.rating;
    final compact = widget.compact;
    final scheme = Theme.of(context).colorScheme;
    final hasBackgroundArtwork = background != null && background.isNotEmpty;
    final allowPosterFallback =
        !metadata.usesProvider(MetadataCategory.backgrounds) ||
        metadata.effectivePreferences.fallback;
    final bg = hasBackgroundArtwork
        ? background
        : (allowPosterFallback ? item.poster ?? '' : '');
    final runtime = metadata.usesProvider(MetadataCategory.information)
        ? item.runtime
        : widget.runtime;
    // Chip-grammar meta line (type · year · runtime · genres, then the IMDb
    // mark) — replaces the oldWidget bordered type pill + star line for the flatter
    // OTT look. Facts-first order on purpose: the line ellipsizes from the
    // END when the identity block is narrow (boxed-trailer mode caps it at
    // the region's left edge), so the tail must be the part that reads fine
    // truncated. "MOVIE · 2023 · 1h 58m · Action · Adv…" still looks whole;
    // the oldWidget genre-first order chopped the year off instead ("…").
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
              ? homeHeroTrailerRegionRect(cons.maxWidth, height)
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
                transitions.fadeForLiveTakeover(
                  buildHomeHeroMoodField(
                    boxedTrailer: widget.boxedTrailer,
                    base: app.home.bg,
                    surface: scheme.surface,
                    tint: widget.tint,
                  ),
                ),
              if (bg.isNotEmpty && artRegion != null)
                // Region-anchored key art: cover-crop + the same eased feathers
                // the trailer uses, so still art and live video dissolve into the
                // field identically. No ShaderMask on this path (one less
                // saveLayer than full-bleed) — the bottom feather melts it into
                // the rows. Fades out while the trailer plays: the video occupies
                // this exact rect in the overlay above.
                Positioned.fromRect(
                  rect: artRegion,
                  child: transitions.fadeBackdropForTrailer(
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
                            buildHomeHeroArtFeathers(
                              base: app.home.bg,
                              tint: widget.tint,
                            ),
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
                transitions.fadeBackdropForTrailer(
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
              transitions.fadeIdentityForTrailer(
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
              transitions.fadeForLiveTakeover(
                transitions.fadeIdentityForTrailer(
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
                            final region = homeHeroTrailerRegionRect(
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
                              child: buildHomeHeroIdentity(
                                context,
                                titleArt: _buildTitleArt(metadata),
                                metaParts: metaParts,
                                rating: rating,
                                description: description,
                                compact: compact,
                                isTelevision: isTelevision,
                                cascade: _cascade,
                                fadeMeta: transitions.fadeMetaForTrailer,
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
                        HomeHeroTrailerLoadingPill(visible: loading),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// The hero's title — see [HomeHeroTitleArt] for the image-first grammar.
  Widget _buildTitleArt(HomeCardMetadataState metadata) {
    return HomeHeroTitleArt(
      title: metadata.presented.name,
      logoUrl: metadata.usesProvider(MetadataCategory.backgrounds)
          ? metadata.presented.logo
          : widget.logo,
      compact: widget.compact,
      isTelevision: widget.isTelevision,
    );
  }
}
