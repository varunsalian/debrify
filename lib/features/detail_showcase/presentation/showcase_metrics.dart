import 'package:debrify/utils/wide_touch_scale.dart';
import 'package:flutter/material.dart';

/// Card metrics as FRACTIONS of the viewport.
///
/// The mock is 1920 wide; absolute logical pixels derived from it only land
/// correctly on a panel whose logical width is exactly 960. Anywhere else the
/// cards come out the wrong size relative to the screen and the gaps close up
/// — which is exactly what "a bit big, with less space between them" is.
/// The divisors below are the raw 1920-scale numbers from the mock.
class ShowcaseMetrics {
  final double w;

  /// Compact — the phone presentation, chosen by [DetailShowcase] from its
  /// own width AND input (never by width alone: a narrow TV keeps the wide
  /// presentation so the DPAD ladder's widgets all exist). Compact values are
  /// measured off the Apple TV phone app on the reference device — see
  /// dev/design/mockups/spotlight_responsive_mockup/.
  final bool compact;

  /// The INPUT axis, carried so [k] can tell a wide tablet from a TV. False
  /// everywhere the metrics come from the MediaQuery fallback, which keeps
  /// every caller outside the Showcase page at the shipped TV numbers.
  final bool touch;

  const ShowcaseMetrics(this.w, {this.compact = false, this.touch = false});

  /// The type-and-control scale for the wide TOUCH tier.
  ///
  /// The wide tier's fixed values — every `_t` literal, the pill heights, the
  /// guide and DYK cards — are 960-canvas numbers, and a TV's logical width IS
  /// ~960 (the scaled surface). A tablet hits the same tier at its real width:
  /// an iPad Pro lands at 1366, where those fixed values render at ~70% of
  /// their designed proportion — 10.5pt plot text and a 30pt primary pill on a
  /// touch device. Scaling them by w/960 restores the mock's proportions
  /// exactly, and because the proportional values (`w * x/1920`) already track
  /// width, text and cards grow TOGETHER rather than drifting apart.
  ///
  /// Exactly 1.0 on TV (dpad keeps every shipped pixel) and on compact (its
  /// absolutes are hand-measured off the Apple phone app, not derived).
  /// The formula lives in [wideTouchScale], shared with the Home Spotlight
  /// board so the two surfaces can never be retuned apart.
  ///
  /// Radii follow one rule: a radius k-scales exactly when its box does —
  /// capsules (radius = height/2) and the k-sized cards/chips scale, while
  /// boxes sized proportionally off `w` keep their shipped radii.
  double get k => (compact || !touch) ? 1.0 : wideTouchScale(w);

  /// From the space actually GIVEN, not from the screen.
  ///
  /// tvOS reports a full-screen size while the shell insets the content for
  /// overscan safe area, so `MediaQuery.sizeOf` overstates the drawable width
  /// and every card comes out proportionally too large for the band it sits
  /// in. Prefers a [ShowcaseMetricsScope] installed by the page (which knows
  /// both the LayoutBuilder width and the input axis); the MediaQuery
  /// subtraction is the fallback for callers outside the Showcase page.
  factory ShowcaseMetrics.of(BuildContext c) {
    final scoped = c.dependOnInheritedWidgetOfExactType<ShowcaseMetricsScope>();
    if (scoped != null) return scoped.metrics;
    final mq = MediaQuery.of(c);
    final w = mq.size.width - mq.padding.horizontal;
    return ShowcaseMetrics(w > 0 ? w : mq.size.width);
  }

  double get gutter => compact ? w * 0.048 : w * (84 / 1920);
  double get title => compact ? 19.0 : w * (26 / 1920);

  /// Compact: the integrated episode card — 62% of the width, the still on
  /// top and a caption plate inside the same rounded rect. Wide: the 1920-
  /// scale mock table, caption below bare art.
  double get epCell => compact ? w * 0.62 : w * (456 / 1920);
  double get stillW => compact ? epCell : w * (432 / 1920);
  double get stillH => stillW * (243 / 432);
  double get epGap => compact ? w * 0.035 : w * (46 / 1920);

  /// The compact card's caption plate: eyebrow, title, 3-line synopsis,
  /// runtime + kebab footer, plus padding.
  double get epPlate => compact ? 128.0 : 0;

  double get circle => compact ? w * 0.23 : w * (250 / 1920);
  double get castGap => compact ? w * 0.04 : w * (52 / 1920);

  double get srcW => compact ? w * 0.75 : w * (560 / 1920);
  double get srcH => w * (132 / 1920);
  double get srcGap => compact ? w * 0.03 : w * (26 / 1920);

  double get poster => compact ? w * 0.243 : w * (260 / 1920);
  double get posterH => poster * (390 / 260);
  double get posterGap => compact ? w * 0.046 : w * (40 / 1920);

  /// Parents Guide category card (wide rail only — compact renders accordion
  /// rows at full width instead). Fixed on the 960 canvas, like the source
  /// cards — [k]-scaled so a tablet keeps the proportion.
  double get guideW => 170.0 * k;
  double get guideH => 76.0 * k;

  /// Did You Know reading card.
  double get dykW => compact ? w * 0.72 : 250.0 * k;
  double get dykH => compact ? 168.0 : 136.0 * k;
}

/// The page's metrics, computed once by [DetailShowcase] from its
/// LayoutBuilder width and input axis, and read by every band through
/// [ShowcaseMetrics.of].
class ShowcaseMetricsScope extends InheritedWidget {
  final ShowcaseMetrics metrics;

  const ShowcaseMetricsScope({
    super.key,
    required this.metrics,
    required super.child,
  });

  @override
  bool updateShouldNotify(ShowcaseMetricsScope old) =>
      old.metrics.w != metrics.w ||
      old.metrics.compact != metrics.compact ||
      old.metrics.touch != metrics.touch;
}

/// Kept for callers that only need the page margin.
const double kShowcaseGutter = 42;
