import 'package:flutter/material.dart';

import '../../utils/platform_util.dart';
import '../app_art.dart';
import '../app_theme.dart';
import '../app_theme_scope.dart';

/// What an image IS, for framing and grading purposes.
///
/// The §12 inventory found three constructors that serve two roles each (a
/// poster in one caller, a channel logo in another, switching on a `BoxFit`
/// flag). A treatment keyed on the SITE would mis-apply on all three — so the
/// role is a parameter, passed by the caller that knows.
enum ArtRole {
  /// A title's poster, portrait.
  poster,

  /// Hero / background / wide key art.
  backdrop,

  /// An episode thumbnail.
  still,

  /// A channel or addon logo — a light mark on transparency. Never framed,
  /// never graded: a logo is somebody's trademark.
  logo,

  /// A person's face. Never graded, on any platform or look.
  portrait,

  /// App assets and placeholders. Not title artwork.
  chrome,
}

/// Frames and grades artwork according to the theme.
///
/// The loudest single signal in the vocabulary, because it puts the theme on
/// the CONTENT rather than on the chrome — nobody mistakes a board of
/// warm-graded posters for a recolour of the furniture.
///
/// ## Grading is a hypothesis until the benchmark rules
///
/// The blend goes through `Image(color:, colorBlendMode:)`, which composites
/// inside the image's own paint rather than allocating a `saveLayer` per image
/// the way `ColorFiltered` does. That is the whole reason grading is
/// affordable in a scrolling shelf at all — and it is unproven until the
/// fling benchmark runs (plan D5). If it fails, [gradeInLists] flips to false
/// and grading survives only on the 24 hero-scale sites.
class ThemedArtwork extends StatelessWidget {
  /// The image. Built by the caller so this widget stays agnostic about
  /// `CachedNetworkImage` vs `Image.network` vs a provider.
  final Widget Function(BuildContext, (Color, BlendMode)? blend) builder;

  /// Anything that sits ON the artwork but is not artwork — a progress bar, a
  /// play glyph, a quality badge, a caption scrim.
  ///
  /// Separate from [builder] because the frame is a TREATMENT OF THE IMAGE and
  /// nothing else. `faded` masks its child with a gradient and `matted` insets
  /// it inside a mount; a caller that handed its whole `Stack` to [builder]
  /// would watch its progress bar dissolve at the bottom of the tile and its
  /// badges shrink into the mat. Chrome goes here and is painted above the
  /// frame, untouched.
  final Widget? overlay;

  final ArtRole role;

  /// True when this instance is inside a lazily-built scrolling list. The
  /// perf-sensitive case, and the one the benchmark gates.
  final bool inList;

  /// The site's own corner radius, before the theme's scale.
  final double radius;

  const ThemedArtwork({
    super.key,
    required this.builder,
    required this.role,
    required this.radius,
    this.overlay,
    this.inList = false,
  });

  /// The D5 kill switch, in one place.
  ///
  /// Flip to `false` and every list-bound image stops grading while heroes
  /// keep it — the exact degraded scope the plan names as the fallback. Left
  /// `true` pending the benchmark, and deliberately a `const` so the decision
  /// is greppable rather than buried in a pref.
  static const bool gradeInLists = true;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = PlatformUtil.isTelevision;
    final blend = _blend(app, tv);
    final framed = _framed(app, builder(context, blend), tv);
    if (overlay == null) return framed;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        framed,
        // Clipped to the ARTWORK's own radius, not left loose over it. Before
        // the split these layers sat inside the site's single outer
        // `ClipRRect` with the image; painting them outside one would let a
        // watched veil or a caption gradient square off the rounded corners
        // under Classic. The clip goes on the overlay alone so `matted`'s
        // mount — which is deliberately larger than the image — is untouched.
        Positioned.fill(
          child: ClipRRect(
            borderRadius: app.shape.brImg(radius),
            child: overlay!,
          ),
        ),
      ],
    );
  }

  (Color, BlendMode)? _blend(AppTheme app, bool tv) {
    switch (role) {
      // A logo is a trademark and a face is a person. Neither is mood.
      case ArtRole.logo:
      case ArtRole.portrait:
      case ArtRole.chrome:
        return app.art.blendForPortrait(tv);
      case ArtRole.poster:
      case ArtRole.backdrop:
      case ArtRole.still:
        if (inList && !gradeInLists) return null;
        return app.art.blendFor(tv);
    }
  }

  Widget _framed(AppTheme app, Widget art, bool tv) {
    // A logo sits on a plate or on nothing; it is never given the theme's
    // frame, because a rounded corner on a transparent mark clips the mark.
    if (role == ArtRole.logo || role == ArtRole.chrome) return art;

    switch (app.art.frame) {
      case ArtFrame.contained:
        return ClipRRect(borderRadius: app.shape.brImg(radius), child: art);

      case ArtFrame.bleed:
        // Runs to the edge with no boundary at all.
        return art;

      case ArtFrame.matted:
        // A print in a mount: the plate is the theme's raised surface, and the
        // mat is what separates the image from the page.
        return Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: app.core.pane,
            borderRadius: app.shape.brImg(radius + 3),
          ),
          child: ClipRRect(
            borderRadius: app.shape.brImg(radius * 0.6),
            child: art,
          ),
        );

      case ArtFrame.faded:
        // Masked so the image dissolves into the ground rather than ending at
        // an edge. A shader mask is a saveLayer, so on TV this degrades to the
        // contained frame — the look keeps its palette and loses one effect,
        // which is the same trade grain and glass make.
        if (tv) {
          return ClipRRect(borderRadius: app.shape.brImg(radius), child: art);
        }
        return ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Colors.black, Colors.transparent],
            stops: [0.0, 0.74, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: ClipRRect(
            borderRadius: app.shape.brImg(radius),
            child: art,
          ),
        );
    }
  }
}
