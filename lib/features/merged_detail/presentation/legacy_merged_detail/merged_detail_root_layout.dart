import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_ambient_still.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_body_layout.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_focus_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_rail_layout.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_trailer_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_trailer_state.dart';
import 'package:debrify/features/merged_detail/presentation/merged_detail_palette.dart';
import 'package:debrify/features/merged_detail/presentation/merged_trailer_playing_chip.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_details_service.dart';
import 'package:debrify/services/storage/detail_page_storage.dart';
import 'package:debrify/theme/app_theme_controller.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/shipped_themes.dart' show effectiveDetailTheme;
import 'package:debrify/theme/theme_core_resolver.dart';
import 'package:debrify/theme/theme_overrides.dart';
import 'package:debrify/utils/artwork_url.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:flutter/material.dart';

class MergedDetailRootLayout {
  final MergedDetailDependencies _deps;
  MergedDetailRootLayout(this._deps);
  StremioMeta get _item => _deps.presentedItem();
  String get _style => _deps.style();
  MetadataPreferences get metadataPreferences => _deps.metadataPreferences();
  bool get mounted => _deps.mounted();
  void Function(VoidCallback) get setState => _deps.setState;
  MergedDetailBodyLayout get _bo => _deps.parts.bodyLayout;
  MergedDetailFocusState get _f => _deps.parts.focusState;
  MergedDetailMetadataState get _m => _deps.parts.metadataState;
  MergedDetailRailLayout get _ri => _deps.parts.railLayout;
  MergedDetailResumeState get _r => _deps.parts.resumeState;
  MergedDetailTrailerActions get _tr => _deps.parts.trailerActions;
  MergedDetailTrailerState get _t => _deps.parts.trailerState;

  /// The look the alternate layouts are drawn in. Read synchronously from the
  /// warmed cache for the same reason as [_style] — the page resolves both in
  /// its first build, and an async read would repaint the whole thing.
  ///
  /// A GETTER, not a `late final`: selecting an app theme write-through
  /// mirrors into `detail_theme`, and a State-lifetime capture would leave an
  /// already-open details route on the stale look until reopened. Resolving
  /// per read keeps it a 20-entry const lookup — free — and an open route now
  /// restyles on its next rebuild. (Foundation item 2 of the theme rollout;
  /// the full `(app_theme, detail_theme, style)` resolution is step 5.)
  ///
  /// Classic is deliberately unthemed, so this is only consulted by the
  /// alternate bodies.
  ///
  /// Through [ThemeCoreResolver], not the registry directly: the user's token
  /// overrides are applied there, and a page that fetched its own core would be
  /// the one surface in the app still showing the unedited theme.
  DetailTheme get theme => ThemeCoreResolver.resolve(
    effectiveDetailTheme(DetailPageStorage.detailThemeCached),
    // Classic is deliberately unthemed, and the controller's own fast path says
    // so. Applying overrides here anyway would make this the one surface that
    // disagreed with it.
    AppThemeController.instance.isLegacy
        ? ThemeOverrides.none
        : AppThemeController.instance.overrides,
  );

  /// Whether this page should show sharp key art at rest at all. Showcase is
  /// the tvOS idiom and the only layout designed around real artwork; every
  /// other layout was drawn against the blurred wash and would lose its text
  /// legibility over a sharp one.
  bool get wantsSharpStill => _style == 'showcase' && !_f.bodyDeep;

  // ── Build ─────────────────────────────────────────────────────────────────

  /// Two-pane (compact info left | full-height episodes right) on TV + desktop
  /// — episodes get the whole column height, which is the point. Android TV is
  /// only ~540 logical px tall, so a full-width hero would swallow the screen;
  /// the left pane keeps info compact and scrollable instead. Mobile stacks.
  bool get wide =>
      _deps.isTelevision() || MediaQuery.of(_deps.context()).size.width >= 900;

  /// Compact-height screens (TV ~540 logical px): shrink type + spacing.
  bool get tight => MediaQuery.of(_deps.context()).size.height < 640;

  bool get isMovie => _item.type == 'movie';

  Widget build(BuildContext context) {
    // Establishes the dependency that makes an ALREADY OPEN detail route
    // re-theme when a token is edited. `_theme` reads the controller directly,
    // which is a plain field read and notifies nobody — without this line the
    // page you edited from would be the last one to change.
    AppThemeScope.of(context);
    // The backdrop is the one display-sized detail hero. Keep the model's
    // catalog URL intact for rails, but ask MetaHub for the large source here.
    final backdropUrl = highQualityArtworkUrl(
      MetadataDetailsService.backdrop(_item, metadataPreferences),
    );
    return PopScope(
      // While the trailer is fullscreen, Back closes it instead of leaving the
      // page — the same player stays alive and settles back into the backdrop.
      canPop: !_t.trailerForeground,
      onPopInvoked: (didPop) {
        if (!didPop) _tr.exitTrailerForeground();
      },
      child: Scaffold(
        backgroundColor: MergedDetailPalette.bg,
        body: Stack(
          children: [
            // Full-bleed backdrop → the Stremio "one lit surface" feel. When a
            // trailer is available and autoplay is on, it crossfades from this
            // static poster into a looping preview (OTT-style), and the
            // Trailer button promotes this same player to fullscreen in place.
            // Non-focusable and behind all content, so DPAD is unaffected.
            Positioned.fill(
              child: HeroTrailerBackdrop(
                key: _t.backdropKey,
                heroTag: _deps.heroTag(),
                imageUrl: backdropUrl,
                // Weak-TV GPU: sigma 0 swaps the runtime gaussian for a tiny
                // decode upscaled by cover-fit (visually equivalent under the
                // dark tint, zero per-frame filter cost), and drops the
                // per-frame blur pass over the ambient trailer video.
                imageBlurSigma: _deps.isTelevision() ? 0 : 42,
                // Showcase at rest is the reference's full-bleed key art; the
                // moment the body goes deep this reverts to the wash, which is
                // the field the bands' white text was tuned against.
                sharpStill: wantsSharpStill,
                // Sigma 8 was tuned for the classic layout, where the video
                // is an AMBIENT backdrop behind opaque panes. Showcase is the
                // reference's shape — the trailer IS the picture, playing in
                // the key-art frame — and blurring it is why it read as dim
                // mush next to the Apple app. Sharp for Showcase everywhere;
                // the other layouts keep their ambient blur.
                videoBlurSigma: _deps.isTelevision() || _style == 'showcase'
                    ? 0
                    : 8,
                // Dropped the moment the body walks past its hero: the
                // reference's trailer belongs to the key-art frame, and playing
                // one under a blurred field is a decoder held for nothing. It
                // also frees the process's single video output for whatever the
                // user opens next.
                videoUrl: _t.trailerAutoplayEnabled && !_f.bodyDeep
                    ? _t.trailerStreams?.playUrl
                    : null,
                audioUrl: _t.trailerAutoplayEnabled && !_f.bodyDeep
                    ? _t.trailerStreams?.audioUrl
                    : null,
                // Resolution and decoder startup already provide a natural
                // poster dwell. Do not stack an artificial wait on top of that.
                startDelay: Duration.zero,
                // Suspend at the Play press, before source/resume resolution.
                // The pipeline loader is a PopupRoute rather than a PageRoute,
                // so RouteAware.didPushNext cannot provide this lifecycle beat.
                enabled: _t.trailerAutoplayEnabled && !_r.playLaunching,
                ambientVolume: _t.trailerAmbientVolume,
                foreground: _t.trailerForeground,
                onRequestClose: _tr.exitTrailerForeground,
                onPlayingChanged: (playing) {
                  if (!mounted) return;
                  setState(() {
                    _t.trailerAmbientPlaying = playing;
                    _t.trailerResolving = false;
                  });
                },
              ),
            ),
            // Page content (tint + panes + back button). Fades out and stops
            // taking input while the trailer is foregrounded, revealing the
            // now-fullscreen, unblurred trailer beneath. ExcludeFocus matters
            // on TV: IgnorePointer only blocks pointers — without it, DPAD OK
            // would still activate the invisible Play/episode tiles under the
            // fullscreen trailer.
            Positioned.fill(
              child: ExcludeFocus(
                excluding: _t.trailerForeground,
                child: IgnorePointer(
                  ignoring: _t.trailerForeground,
                  child: AnimatedOpacity(
                    opacity: _t.trailerForeground ? 0 : 1,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeInOut,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Ambient still (Filmstrip): the focused episode's frame,
                        // painted over the backdrop art but under everything
                        // else. Inside this AnimatedOpacity so it fades away
                        // with the rest of the content when the trailer is
                        // promoted, and suppressed outright while it is —
                        // otherwise it would cover the fullscreen video.
                        if (_f.focusedStillUrl != null &&
                            !_t.trailerForeground &&
                            !_t.trailerAmbientPlaying)
                          Positioned.fill(
                            child: MergedAmbientStill(
                              url: _f.focusedStillUrl!,
                              isTelevision: _deps.isTelevision(),
                            ),
                          ),
                        // Darker tint so even a bright poster reads as a dark
                        // surface. Skipped for layouts that paint their own
                        // scrim — two stacked washes take the artwork to
                        // near-black, and a full-bleed layout is ABOUT the
                        // artwork. Those layouts keep a much lighter floor so
                        // a blown-out image still can't wash out the chrome.
                        // `shellTint: false` paints NOTHING here — not a
                        // lighter wash, none at all. A layout whose scrim is a
                        // specific angle cannot reach its spec while the shell
                        // is also laying a diagonal over the same artwork.
                        // Lifted entirely while the Showcase ambient trailer
                        // rolls off-TV: the reference plays its preview
                        // crystal clear in the key-art frame, and even this
                        // light floor reads as a haze over motion. The
                        // layout's own scrim (thinned the same way) keeps the
                        // identity text legible. Snapped, not tweened — same
                        // rule as the home hero's rolling scrims.
                        if (_bo.bodySpec.shellTint && !_tr.trailerClearView)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: _bo.bodySpec.ownScrim
                                    ? [
                                        MergedDetailPalette.bg.withValues(
                                          alpha: 0.10,
                                        ),
                                        MergedDetailPalette.bg.withValues(
                                          alpha: 0.24,
                                        ),
                                      ]
                                    : [
                                        MergedDetailPalette.bg.withValues(
                                          alpha: 0.60,
                                        ),
                                        MergedDetailPalette.bg.withValues(
                                          alpha: 0.88,
                                        ),
                                      ],
                              ),
                            ),
                          ),
                        // Flat editorial ground (Broadsheet). Painted here so
                        // it covers the artwork without ever becoming an
                        // ancestor of the trailer backdrop, and so it fades
                        // out with the content on promotion.
                        if (_bo.bodySpec.inkGround)
                          Positioned.fill(
                            child: ColoredBox(color: groundColor),
                          ),
                        // Ambient per-title color grade: a soft glow of the
                        // extracted accent in the upper-left, under the content,
                        // so the whole surface is subtly lit by the title's own
                        // color. Animates in when the accent resolves (no pop).
                        // A radial gradient fill is a single cheap paint — no
                        // blur, no layer — so it's safe on the weak TV GPU.
                        if (_bo.bodySpec.shellTint && !_tr.trailerClearView)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: TweenAnimationBuilder<Color?>(
                                duration: const Duration(milliseconds: 500),
                                tween: ColorTween(
                                  end: _m.accent.withValues(
                                    alpha: _bo.themedBody
                                        ? theme.washOpacity
                                        : 0.16,
                                  ),
                                ),
                                builder: (_, color, __) => DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      center: const Alignment(-0.7, -0.85),
                                      radius: 1.5,
                                      colors: [
                                        color ?? Colors.transparent,
                                        Colors.transparent,
                                      ],
                                      stops: const [0.0, 0.7],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        SafeArea(child: _bo.buildBody(backdropUrl)),
                        // Back button.
                        Positioned(
                          top: 0,
                          left: 0,
                          child: SafeArea(
                            child: Padding(
                              padding: EdgeInsets.all(
                                _deps.isTelevision() ? 20 : 8,
                              ),
                              child: _ri.circleButton(
                                Icons.arrow_back_rounded,
                                () => Navigator.of(context).maybePop(),
                                tooltip: 'Back',
                                focusNode: _f.backButtonFocusNode,
                                // Square themes (Noir, Concrete, Phosphor,
                                // Blueprint) cannot be forced into a circle.
                                theme: _bo.themedBody ? theme : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Small "trailer playing in background" hint — only while the
            // ambient trailer is actually playing and not promoted. Tapping it
            // brings the trailer forward (same as the Trailer button).
            if (_t.trailerAmbientPlaying && !_t.trailerForeground)
              Positioned(
                left: 0,
                bottom: 0,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(_deps.isTelevision() ? 20 : 12),
                    child: MergedTrailerPlayingChip(
                      onTap: _tr.playTrailer,
                      theme: _bo.themedBody ? theme : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The ground the shell paints when the body asks for a flat one.
  Color get groundColor =>
      _bo.themedBody ? theme.ground : const Color(0xFF0A0A0C);
}
