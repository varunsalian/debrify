import 'package:flutter/widgets.dart';

/// The geometry of the Discover STAGE shelf, published by the host down to
/// whatever is rendering the results.
///
/// One source of truth, deliberately: the host reserves the identity block's
/// clearance from exactly the numbers the shelf lays itself out with, so the
/// logo can never end up sitting on top of the posters (the Canvas board's
/// `shelfColumnH` lesson — derive the clearance, never guess it).
@immutable
class DiscoverShelfMetrics {
  /// Poster height. Width follows at 2:3.
  final double cardHeight;

  /// Horizontal padding at both ends of the shelf — matched to the filter
  /// line's own inset so the two read as one left margin.
  final double hPad;

  const DiscoverShelfMetrics({required this.cardHeight, required this.hPad});

  double get cardWidth => cardHeight * 2 / 3;

  /// Headroom for the focus scale (the board's rise grows cards 1.045 about
  /// their centre) plus a little air, so a focused poster's lift is never
  /// clipped by the viewport.
  static const double slack = 20;

  /// The gap under the shelf, before the screen edge.
  static const double tail = 20;

  /// The "12 / 312" position line above the posters, with its gap.
  static const double headHeight = 16;
  static const double headGap = 8;

  /// Full height of the shelf box the [DiscoverShelfScope] child occupies.
  double get boxHeight => cardHeight + slack;

  /// Everything the bottom column occupies, measured bottom-up — what the
  /// identity block above must clear.
  double get columnHeight => tail + boxHeight + headGap + headHeight;

  @override
  bool operator ==(Object other) =>
      other is DiscoverShelfMetrics &&
      other.cardHeight == cardHeight &&
      other.hPad == hPad;

  @override
  int get hashCode => Object.hash(cardHeight, hPad);
}

/// Marks the subtree as the Discover STAGE layout, and carries the shelf's
/// geometry to it.
///
/// Ambient rather than a constructor flag on purpose: Discover renders its
/// results through five different See-All screens (Continue Watching, Trakt,
/// Simkl, MDBList, addon catalogs), and every one of them delegates to the
/// shared [SeeAllPosterGrid] / skeleton. Threading a `stage:` bool through all
/// five is five chances for a new source to forget it; the host — the only
/// place that knows the pref — declares it once, here.
///
/// Absent (the default, and every non-Discover See-All page) → the poster grid.
class DiscoverShelfScope extends InheritedWidget {
  final DiscoverShelfMetrics metrics;

  const DiscoverShelfScope({
    super.key,
    required this.metrics,
    required super.child,
  });

  /// The shelf geometry for this subtree, or null when the caller should
  /// render its normal grid.
  static DiscoverShelfMetrics? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DiscoverShelfScope>()
      ?.metrics;

  @override
  bool updateShouldNotify(DiscoverShelfScope old) => old.metrics != metrics;
}
