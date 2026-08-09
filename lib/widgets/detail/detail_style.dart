import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_light.dart';
import '../../theme/app_texture.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/platform_util.dart';
import 'theme/detail_theme.dart';

/// Which shape a details-page layout should draw itself in.
///
/// Resolved from platform + geometry, never width alone: a full-bleed landscape
/// treatment breaks on an 834×1112 tablet, and a landscape phone is a phone.
enum DetailSize { tv, desktop, tabletPortrait, phone }

/// The one resolver. Every layout uses it so breakpoints can't drift apart.
///
/// `shortSide` is deliberately `min(w, h)` — using `size.width` would classify
/// an 800×400 landscape phone as a desktop.
DetailSize resolveDetailSize({required bool isTelevision, required Size size}) {
  if (isTelevision) return DetailSize.tv;
  final shortSide = math.min(size.width, size.height);
  final portrait = size.height >= size.width;
  if (shortSide <= 560) return DetailSize.phone;
  if (portrait && shortSide < 900) return DetailSize.tabletPortrait;
  return DetailSize.desktop;
}

extension DetailSizeX on DetailSize {
  bool get isTv => this == DetailSize.tv;
  bool get isPhone => this == DetailSize.phone;

  /// Layouts that pick between a side-by-side and a stacked arrangement.
  bool get isWide => this == DetailSize.tv || this == DetailSize.desktop;

  /// Compact-height surfaces (a TV is only ~540 logical px tall).
  bool get isTight => this == DetailSize.tv || this == DetailSize.phone;

  double get gutter => switch (this) {
    DetailSize.tv => 34,
    DetailSize.desktop => 30,
    DetailSize.tabletPortrait => 22,
    DetailSize.phone => 16,
  };
}

/// Bottom-anchored scrim for identity over artwork.
///
/// A **legibility floor, not a look**: artwork can be anything, and stops
/// picked against a dark backdrop wash out completely over a bright one. The
/// identity band sits on ≥0.55 alpha of the theme's OWN ground whatever the
/// image — which is also what lets a light theme scrim upward into paper
/// rather than into ink.
LinearGradient detailIdentityScrim(DetailTheme t) => LinearGradient(
  begin: Alignment.bottomCenter,
  end: Alignment.topCenter,
  colors: [
    t.ground,
    t.ground.withValues(alpha: 0.92),
    t.ground.withValues(alpha: 0.64),
    t.ground.withValues(alpha: 0.38),
  ],
  stops: const [0.06, 0.42, 0.68, 1.0],
);

/// Top-half scrim for layouts that split art and content (Stage).
LinearGradient detailStageScrim(DetailTheme t) => LinearGradient(
  begin: Alignment.bottomCenter,
  end: Alignment.topCenter,
  colors: [
    t.ground,
    t.ground.withValues(alpha: 0.86),
    t.ground.withValues(alpha: 0.40),
    t.ground.withValues(alpha: 0.16),
  ],
  stops: const [0.04, 0.48, 0.76, 1.0],
);

/// Which of the two legibility floors a site needs.
enum DetailScrimKind {
  /// The identity band — bottom-anchored, for a title sitting on artwork.
  identity,

  /// The split-layout variant, for a layout whose art fills the top half.
  stage,
}

/// The legibility floor, expressed in the app theme's scrim GRAMMAR.
///
/// The five detail layouts all paint the same bottom-anchored gradient, which
/// is why every theme's hero reads the same however the palette changes — a
/// fade, a frosted band and a hard plate are three different products, and
/// until now the app only had the fade.
///
/// **Under `ScrimStyle.bottomGradient`, which is the legacy pin and what every
/// pre-`ThemeSpec` theme resolves to, this is exactly the `DecoratedBox` the
/// five call sites shipped** — same gradient function, same stops, same
/// `DetailTheme` ground. The other three grammars are reachable only from a
/// spec.
///
/// The style comes from the APP theme and the colour from the DETAIL theme,
/// which is deliberate: those are two settings, and a user who has pinned a
/// details theme different from the app theme gets that theme's ink under the
/// app's grammar rather than a surprise third combination.
class DetailScrim extends StatelessWidget {
  final DetailScrimKind kind;
  const DetailScrim({super.key, this.kind = DetailScrimKind.identity});

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    final light = AppThemeScope.of(context).light;
    final ground = t.ground;
    final vignette = light.vignetteFor(PlatformUtil.isTelevision);

    // Corner darkening across the whole frame, where the look asks for one.
    // Composed with the scrim rather than replacing it: they answer different
    // questions — the scrim protects a specific band of text, the vignette
    // pulls the eye off the edges of the image. A static gradient, so it costs
    // the same on every platform.
    if (vignette > 0) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _scrim(t, light, ground),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.1,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: vignette),
                  ],
                  stops: const [0.45, 1.0],
                ),
              ),
            ),
          ),
        ],
      );
    }
    return _scrim(t, light, ground);
  }

  Widget _scrim(DetailTheme t, LightTokens light, Color ground) {
    switch (light.scrim) {
      case ScrimStyle.bottomGradient:
        return DecoratedBox(decoration: BoxDecoration(gradient: _gradient(t)));

      case ScrimStyle.plate:
        // A hard slab across the band the copy occupies. The one grammar that
        // guarantees a contrast ratio whatever the image is — which is why it
        // is the TV fallback for `blurBand` too.
        return Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: light.scrimExtent,
            child: ColoredBox(
              color: ground.withValues(alpha: light.scrimStrength),
            ),
          ),
        );

      case ScrimStyle.fullDim:
        // No localised treatment at all: the whole image steps back so the
        // copy can sit anywhere on it.
        return ColoredBox(
          color: ground.withValues(alpha: light.scrimStrength * 0.6),
        );

      case ScrimStyle.blurBand:
        // The copy sits on BLURRED artwork rather than on a darkened copy of
        // it. On TV there is no blur — `BackdropFilter` is a saveLayer per
        // frame — so the band degrades to the plate, which is the same
        // promise (guaranteed contrast) at a raster cost of zero.
        if (PlatformUtil.isTelevision) {
          return Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: light.scrimExtent,
              child: ColoredBox(
                color: ground.withValues(alpha: light.scrimStrength),
              ),
            ),
          );
        }
        return Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: light.scrimExtent,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: ColoredBox(
                  // Much lighter than the plate: the blur is doing the
                  // legibility work, and a heavy tint on top of it just looks
                  // like a plate that cost a saveLayer.
                  color: ground.withValues(alpha: light.scrimStrength * 0.45),
                ),
              ),
            ),
          ),
        );
    }
  }

  LinearGradient _gradient(DetailTheme t) => switch (kind) {
    DetailScrimKind.identity => detailIdentityScrim(t),
    DetailScrimKind.stage => detailStageScrim(t),
  };
}

/// Section label ("SUMMARY", "MORE LIKE THIS").
///
/// A widget rather than a function so it can read the theme — its case,
/// tracking, size and family are all per-theme.
class DetailSlab extends StatelessWidget {
  final String text;
  const DetailSlab(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    final label = Text(
      t.slabStyle.letterSpacing == null ? text : text.toUpperCase(),
      style: t.slabStyle,
    );
    // A theme that declares a rule gets one under every section heading; the
    // rest stay a bare label.
    if (t.dividerGradient == null) return label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        label,
        const SizedBox(height: 5),
        Container(
          height: 1,
          decoration: BoxDecoration(gradient: t.dividerGradient),
        ),
      ],
    );
  }
}

/// Chip used for genres.
class DetailPill extends StatelessWidget {
  final String text;
  const DetailPill(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: t.brBtn,
        border: Border.all(color: t.hair),
      ),
      child: Text(text, style: TextStyle(fontSize: 11.5, color: t.tx2)),
    );
  }
}

/// The house focus ring: an in-bounds FOREGROUND border.
///
/// Never a spread shadow — those paint a filled rect behind the child, which
/// bleeds through the translucent glass surfaces as a solid gold block, and
/// they paint outside bounds, forcing rails to un-clip.
class DetailFocusRing extends StatelessWidget {
  final bool focused;
  final BorderRadius? radius; // null → circle
  final Widget child;

  /// The surface the ring is drawn ON, when it is a known fill.
  ///
  /// A filled primary button can be the same colour as the theme's cursor —
  /// Noir is white on white — and the ring vanishes. Passing the fill lets the
  /// theme pick a colour that contrasts with it.
  final Color? on;

  const DetailFocusRing({
    super.key,
    required this.focused,
    required this.child,
    this.radius,
    this.on,
  });

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    // `isTelevision`, so the Apple TV port gets the same policy — see the
    // note in theme/app_texture.dart.
    final tv = PlatformUtil.isTelevision;
    // An outward ring cannot be a foreground decoration — it has to be drawn
    // outside the child's bounds, which only a non-layout-affecting overlay
    // can do. Signal's offset is 0, so Signal keeps the in-bounds path exactly.
    if (t.focusOffset > 0) {
      final o = t.focusOffset;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          if (focused)
            Positioned(
              left: -o,
              top: -o,
              right: -o,
              bottom: -o,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: radius == null
                        ? BoxShape.circle
                        : BoxShape.rectangle,
                    borderRadius: radius == null
                        ? null
                        : BorderRadius.circular(radius!.topLeft.x + o),
                    border: Border.all(
                      color: on == null ? t.focus : t.focusOn(on!),
                      width: t.focusWidthFor(tv),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }
    return AnimatedContainer(
      // Snap on TV (house idiom): a ring fade per DPAD move repaints every
      // element in flight while a held key surfs the rail.
      duration: tv ? Duration.zero : const Duration(milliseconds: 140),
      foregroundDecoration: BoxDecoration(
        shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius,
        // focusWidthFor floors the width on TV: Vault and Cinemascope both ask
        // for 1px, which is invisible at three metres.
        border: focused
            ? Border.all(
                color: on == null ? t.focus : t.focusOn(on!),
                width: t.focusWidthFor(tv),
              )
            : null,
      ),
      child: child,
    );
  }
}

/// Consumes a directional key at a region's edge so the DPAD cursor stops there
/// instead of escaping to whatever is geometrically nearest.
///
/// A non-focusable ancestor sees the key on its way up from the focused child,
/// before app-level shortcuts turn it into a traversal move.
class DetailEdgeTrap extends StatelessWidget {
  final bool trapLeft;
  final bool trapRight;
  final bool trapUp;
  final bool trapDown;

  /// Invoked instead of dead-stopping, when the edge is a sanctioned crossing.
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  final Widget child;

  const DetailEdgeTrap({
    super.key,
    required this.child,
    this.trapLeft = false,
    this.trapRight = false,
    this.trapUp = false,
    this.trapDown = false,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
  });

  @override
  Widget build(BuildContext context) {
    if (!trapLeft && !trapRight && !trapUp && !trapDown) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final k = event.logicalKey;
        bool fire(bool trap, VoidCallback? cb) {
          if (!trap) return false;
          cb?.call();
          return true;
        }

        if (k == LogicalKeyboardKey.arrowLeft && fire(trapLeft, onLeft)) {
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowRight && fire(trapRight, onRight)) {
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowUp && fire(trapUp, onUp)) {
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowDown && fire(trapDown, onDown)) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

/// Per-episode FocusNodes owned by a layout, keyed by view generation.
///
/// Layouts must not borrow the engine's nodes — those are disposed and rebuilt
/// on every season change, so a retained tab or an outgoing subtree can hold a
/// dead one. Owning them here also fixes the subtler half of that problem:
/// disposal is deferred to after the frame, because a node swapped out during
/// build is still registered with the framework until the `Focus` widget's
/// `didUpdateWidget` runs, and disposing it first throws
/// "A FocusNode was used after being disposed".
class DetailCellNodes {
  final String debugPrefix;
  final Map<String, FocusNode> _live = {};
  int _generation = -1;

  DetailCellNodes(this.debugPrefix);

  FocusNode of(int generation, int season, int number) {
    if (generation != _generation) {
      _retire(_live.values.toList());
      _live.clear();
      _generation = generation;
    }
    final key = '$generation:$season-$number';
    return _live.putIfAbsent(
      key,
      () => FocusNode(debugLabel: '$debugPrefix-$key'),
    );
  }

  FocusNode? lookup(int generation, int season, int number) =>
      _live['$generation:$season-$number'];

  /// The first node that is actually mounted — layouts use this to hand focus
  /// into the collection without assuming an index exists.
  FocusNode? get firstMounted =>
      _live.values.where((n) => n.context != null).firstOrNull;

  void dispose() {
    for (final n in _live.values) {
      n.dispose();
    }
    _live.clear();
  }

  void _retire(List<FocusNode> nodes) {
    if (nodes.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final n in nodes) {
        n.dispose();
      }
    });
  }
}

/// Reveals the engine's landing episode even when it is far outside a lazy
/// list's built range.
///
/// `Scrollable.ensureVisible` needs the target's context, and a bounded lazy
/// list has not built an item 30 rows down — so a reveal that only fires when
/// the node happens to be mounted silently does nothing for a deep link or a
/// late-season resume.
///
/// Converges by FRACTION rather than by a guessed item extent: each attempt
/// re-reads the live `maxScrollExtent`, which grows more accurate as the list
/// builds, so repeated jumps close in on the target instead of landing on the
/// same wrong offset forever. Once the item mounts, `ensureVisible` places it
/// exactly. Never moves focus.
void revealDetailLanding({
  required ScrollController controller,
  required int index,
  required int itemCount,
  required BuildContext? Function() contextOf,
  double alignment = 0.3,
  int retries = 8,
}) {
  if (index < 0 || itemCount <= 0) return;
  void attempt(int left) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = contextOf();
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: alignment,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: Duration.zero,
        );
        return;
      }
      // hasClients goes false once the layout is disposed — this is also what
      // stops the retry chain rather than a mounted flag it cannot see.
      if (!controller.hasClients || left <= 0) return;
      final max = controller.position.maxScrollExtent;
      if (max <= 0) return;
      final frac = itemCount <= 1 ? 0.0 : index / (itemCount - 1);
      final target = (frac * max).clamp(0.0, max);
      if ((controller.offset - target).abs() > 1) {
        controller.jumpTo(target);
      } else if (left < retries) {
        // Converged on an offset the item still hasn't built at — nothing more
        // to gain from jumping again.
        return;
      }
      attempt(left - 1);
    });
  }

  attempt(retries);
}

/// A soft edge on a scroll region, so a row cut by the fold reads as "there is
/// more" rather than as a clipped element.
///
/// A painted gradient over a known ground colour, deliberately NOT a
/// [ShaderMask]: that forces a saveLayer every frame, which is exactly the
/// per-frame cost the TV budget rules out on a scrolling grid.
class DetailScrollFade extends StatelessWidget {
  final Widget child;
  final AxisDirection edge;
  final double extent;

  /// Required: a painted fade only works over a known OPAQUE surface, and a
  /// default would let a caller fade to a colour its ground never was.
  final Color ground;

  const DetailScrollFade({
    super.key,
    required this.child,
    required this.ground,
    this.edge = AxisDirection.down,
    this.extent = 28,
  });

  @override
  Widget build(BuildContext context) {
    final vertical = edge == AxisDirection.down || edge == AxisDirection.up;
    final fade = IgnorePointer(
      child: SizedBox(
        width: vertical ? null : extent,
        height: vertical ? extent : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: switch (edge) {
                AxisDirection.down => Alignment.bottomCenter,
                AxisDirection.up => Alignment.topCenter,
                AxisDirection.right => Alignment.centerRight,
                AxisDirection.left => Alignment.centerLeft,
              },
              end: switch (edge) {
                AxisDirection.down => Alignment.topCenter,
                AxisDirection.up => Alignment.bottomCenter,
                AxisDirection.right => Alignment.centerLeft,
                AxisDirection.left => Alignment.centerRight,
              },
              colors: [ground, ground.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: edge == AxisDirection.right ? null : 0,
          right: edge == AxisDirection.left ? null : 0,
          top: edge == AxisDirection.down ? null : 0,
          bottom: edge == AxisDirection.up ? null : 0,
          child: fade,
        ),
      ],
    );
  }
}

/// A region's own light — the wash a theme paints over its ground.
///
/// Painted as a decoration rather than a stacked overlay so it sits behind the
/// region's content without adding a layer to composite.
class DetailWash extends StatelessWidget {
  final Gradient? wash;
  final Widget child;

  const DetailWash({super.key, required this.wash, required this.child});

  @override
  Widget build(BuildContext context) => wash == null
      ? child
      : DecoratedBox(
          decoration: BoxDecoration(gradient: wash),
          child: child,
        );
}

/// Blueprint's 32px rule and the film grain some themes ask for.
///
/// Both are whole-page textures, so they are applied once at the body root
/// rather than by each layout. Grain is a foreground layer and is forced off on
/// TV by [DetailTheme.grainFor] — a per-frame blend over a full screen is not
/// something a 2 GB box should be asked to do.
///
/// ## The app-wide texture owns the page; this is the fallback
///
/// `AppTexture` (theme/app_texture.dart) paints the same two textures for the
/// whole app, above the root Navigator. Without a rule, a details page under a
/// grain theme would be grained TWICE — once by the shell and once here —
/// doubling the speck density and, on Blueprint, drawing the rule over itself.
///
/// The rule is: **whenever the APP theme declares a texture, it owns every
/// page, including this one**, and this widget stands down. When the app theme
/// declares none — which includes legacy, and is the common case — the details
/// page's own `detail_theme` texture paints here as it always has.
///
/// The consequence worth stating: a user on app-theme Blueprint and
/// detail-theme Sepia sees Blueprint's grid on the details page, not Sepia's
/// grain. That is deliberate. Grain and grid are properties of the PAGE, not
/// of a palette, and two whole-page textures fighting over one page is worse
/// than either of them winning. The details theme still owns everything else
/// it always did — its palette, geometry and type are untouched by this.
///
/// ## Both painters are the batched ones
///
/// The originals issued up to 3,000 `drawRect` calls per repaint. They now
/// come from `app_texture.dart`, which computes the speck field once into a
/// reused buffer and emits it as a single `drawRawPoints`.
class DetailAtmosphere extends StatelessWidget {
  final Widget child;

  const DetailAtmosphere({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    final tv = PlatformUtil.isAndroidTvCached;
    final grain = t.grainFor(tv);
    // The grid follows grain's platform policy here too.
    //
    // It did not before, and that was an inconsistency rather than a decision:
    // a full-screen 32px rule composited over a scrolling episode list is not
    // free on a 2 GB box, which is precisely why grain is gated. It also left
    // a hole in the ownership rule below — on TV the app-wide layer suppresses
    // itself, so no marker is installed, so this widget would have gone on
    // painting the very overlay the platform policy exists to prevent.
    //
    // Visible effect: Blueprint's details page loses its rule ON ANDROID TV
    // only. Every other platform, and every other theme, is unchanged.
    final grid = tv ? false : t.grid;
    if (!grid && grain <= 0) return child;
    if (AppTexturePainting.of(context)) return child;
    return CustomPaint(
      painter: grid ? GridPainter(t.hair) : null,
      // Grain takes the theme's own ink, so a light theme gets dark specks
      // rather than a white haze over its paper.
      foregroundPainter: grain > 0 ? GrainPainter(grain, t.tx) : null,
      child: child,
    );
  }
}

