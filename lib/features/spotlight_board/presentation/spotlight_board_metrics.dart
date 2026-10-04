import 'package:debrify/utils/wide_touch_scale.dart';

/// Card metrics as FRACTIONS of the space the board is actually GIVEN.
///
/// The reference is 1920 wide and its posters are 260 with a 40 gap — a pitch
/// of 300. Expressed as absolute logical pixels those only match a panel whose
/// logical width happens to be exactly half of 1920; on anything else the
/// cards come out the wrong size relative to the screen, which is precisely
/// how "a bit big, and less space between them" happens.
///
/// Proportions hold everywhere. The divisors are the raw 1920-scale numbers.
///
/// Measured against the board's own constraints rather than
/// `MediaQuery.sizeOf`, because those differ: tvOS reports a full-screen size
/// while the shell insets the content for overscan safe area (and, under
/// non-pill sidebar styles, for the rail). Sizing off the screen makes every
/// card proportionally too large for the region it is drawn in — a 260-wide
/// card in a 1920 screen becomes a 260-wide card in a ~1800 visible band.
/// The presentation tier — the SIZE axis, chosen from the board's own width
/// but only ever leaving `wide` when the input is not a remote. A narrow TV
/// (UI scale, odd panel) keeps the wide presentation with proportionally
/// smaller cards, so the DPAD ladder never targets widgets that don't exist.
enum SpotlightBoardTier { compact, mid, wide }

class SpotlightBoardMetrics {
  final double w;
  final bool dpad;
  final SpotlightBoardTier tier;

  SpotlightBoardMetrics(this.w, {this.dpad = true})
    : tier = dpad
          ? SpotlightBoardTier.wide
          : w < 600
          ? SpotlightBoardTier.compact
          : w < 1100
          ? SpotlightBoardTier.mid
          : SpotlightBoardTier.wide;

  bool get compact => tier == SpotlightBoardTier.compact;

  /// The type scale for the wide TOUCH tiers — the same correction the
  /// Showcase detail page applies (see `ShowcaseMetrics.k`).
  ///
  /// The wide hero's fixed values (identity type, the logo slot, the
  /// identity/dots insets' non-overlap share) are 960-canvas numbers, and a
  /// TV's logical width IS ~960. A tablet reaches the same layout at its real
  /// width — 1366 on an iPad Pro — where those absolutes render at ~70% of
  /// their designed proportion. Exactly 1.0 on TV (every shipped pixel keeps)
  /// and on compact (its absolutes are phone-measured, not derived); the
  /// formula lives in [wideTouchScale], shared with the detail page.
  double get k => (dpad || compact) ? 1.0 : wideTouchScale(w);

  /// Compact values are MEASURED off the Apple TV phone app on the reference
  /// device (see dev/design/mockups/spotlight_responsive_mockup/, re-measured
  /// 2026-08-16 for the home_rows_mockup pass): gutter 4.8%, posters 25.7%
  /// with 3.4% gaps — three cards and a real sliver of the fourth, the peek
  /// that says "this scrolls". The earlier 24.3%/4.6% pairing spent the
  /// difference on gaps and read smaller than the reference next to it.
  /// Mid is the tablet tier — the TV fractions with the posters bumped for
  /// fingers. Wide is the TV mock's 1920-scale table, byte-for-byte what
  /// shipped.
  double get gutter => compact ? w * 0.048 : w * (84 / 1920);
  double get poster => switch (tier) {
    SpotlightBoardTier.compact => w * 0.257,
    SpotlightBoardTier.mid => w * 0.16,
    SpotlightBoardTier.wide => w * (260 / 1920),
  };
  double get posterH => poster * (390 / 260);

  /// Landscape title-card width. Sized so a 16:9 card keeps roughly
  /// two-thirds of the poster row's height — at the poster's own width a
  /// wide card is barely half as tall and the whole rail reads shrunken.
  /// TV shows ~3.4 cards per band, tablet ~2.6, phone ~1.7 with a peek
  /// (user-tuned 2026-08: the first pass a step smaller read too timid).
  double get wideCardW => switch (tier) {
    SpotlightBoardTier.compact => w * 0.50,
    SpotlightBoardTier.mid => w * 0.33,
    SpotlightBoardTier.wide => w * (470 / 1920),
  };
  double get gap => switch (tier) {
    SpotlightBoardTier.compact => w * 0.034,
    SpotlightBoardTier.mid => w * 0.026,
    SpotlightBoardTier.wide => w * (40 / 1920),
  };

  /// Card corner radius. 7 is the TV mock's number, moved here from the
  /// card's hardcode; compact grows it the way every phone card idiom does.
  double get radius => switch (tier) {
    SpotlightBoardTier.compact => 10.0,
    SpotlightBoardTier.mid => 8.0,
    SpotlightBoardTier.wide => 7.0,
  };

  /// What the focus effect paints OUTSIDE the resting card, which the row
  /// reserves so the lift lands on ground instead of on the headings.
  ///
  /// The card grows about its centre, so half of the 10% goes upward, and
  /// `ParallaxFocus` rises it a further 7. Reserving that much means nothing
  /// OPAQUE ever reaches the title above.
  ///
  /// The shadow reaches 9 higher still (25 of blur less its 16 of downward
  /// offset) and is deliberately NOT reserved: it is a soft blur whose far
  /// edge is invisible, and paying for it would push every row apart by more
  /// than the reference puts between them.
  ///
  /// Zero on compact: nothing there ever focuses or hovers, so the lift
  /// never fires and the reservation would just be dead air between rows.
  double liftUpFor(double cardHeight) => compact ? 0 : cardHeight * 0.05 + 7;

  /// Downward the rise works in our favour, so only the growth is reserved.
  double liftDownFor(double cardHeight) => compact ? 0 : cardHeight * 0.05;
  double get title => compact ? 19.0 : w * (26 / 1920);
  double get caption => compact ? 12.0 : w * (21 / 1920);

  /// The caption strip below the art — compact only; wide overlays it on the
  /// card. It reserves two lines because the second carries useful playback
  /// context (season/episode) and ratings. The compact renderer used to
  /// reserve and paint only the title, silently dropping that metadata even
  /// though the same card showed it in the wide layout.
  double get captionBlock => compact ? 40.0 : 0;
}
