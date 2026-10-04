class SpotlightBoardConstantsState {
  /// Start fetching the next shelf batch before touch scrolling reaches the
  /// hard end. TV has its own DPAD-at-last-shelf trigger in [_down].
  static const double touchLoadMoreThreshold = 600;

  /// The hero as a FRACTION of the board: the art reaches the bottom edge of
  /// the screen, and the first shelf sits ON it.
  ///
  /// Two things were wrong before. It was `540` logical pixels flat, and
  /// logical size differs per device — so one constant drew a hero at ~89% of
  /// an Android TV box and ~40% of an Apple TV. Same code, same number, a
  /// different design on each, and on tvOS a trailer playing in a slot half its
  /// intended height, which is why `cover` was discarding half the frame.
  ///
  /// And the target itself was wrong: ending the artwork above the first shelf
  /// leaves a band of flat grey under the cards at rest, which is exactly what
  /// "the poster is not full screen" describes. The ground is what you land on
  /// once you SCROLL — that is where the measured `rgb(28,28,28)` gutter came
  /// from, and it was taken from scrolled frames and applied to the resting one
  /// by mistake.
  static const double heroFraction = 1.0;

  /// Compact keeps the hero to ~64% of the board — the Apple phone measure —
  /// with the rows below it in flow rather than riding over the art.
  static const double heroFractionCompact = 0.64;

  /// How far the first shelf rides up over the hero's lower edge, as a
  /// fraction of the hero. Was 88 of 540, kept in proportion — with a
  /// full-height hero this is what puts the cards OVER the artwork rather than
  /// below it. Compact has no overlap: the hero fades into the ground and the
  /// first shelf starts ON the ground (the reference does exactly this).
  static const double shelfOverlapFraction = 88 / 540;

  /// True once the board is scrolled far enough that the pinned hero is
  /// effectively covered. Owns the trailer's lifecycle for SCROLLING, which
  /// touch and wheel produce without ever telling the cursor: DPAD descent
  /// goes through [_down] (which stops the trailer itself), but a swipe or a
  /// wheel just moves the list — and the backdrop being permanently mounted
  /// now, the video would keep decoding behind an opaque veil forever.
  bool scrolledAway = false;
}
