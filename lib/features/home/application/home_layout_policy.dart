/// The stored style narrowed to what an off-TV Home can render.
///
/// Phones, tablets and desktop draw exactly two layouts — Classic and
/// Spotlight; the other six are DPAD stage layouts whose focus topology has
/// no touch equivalent. The stored pref is shared with TV and is **never
/// rewritten** here: a fresh install carries the TV default `'canvas'`, which
/// this maps to Classic for display, selection and dispatch alike — while a
/// TV signing into the same account keeps its Canvas.
String effectiveOffTvHomeStyle(String raw) =>
    raw == 'spotlight' ? 'spotlight' : 'classic';

/// Whether an off-TV Home should stay in the Spotlight shell while its
/// content is being resolved.
///
/// A freshly mounted Home has no hero yet. Falling back to Classic solely for
/// that loading window paints its persistent search bar before the first
/// catalog arrives, then replaces the whole page with Spotlight. Keep the
/// selected shell during loading; once loading finishes, a genuinely missing
/// hero still falls back to Classic so CW/favourites-only homes remain useful.
bool shouldUseOffTvSpotlightShell({
  required String rawStyle,
  required bool loading,
  required bool hasHero,
}) => effectiveOffTvHomeStyle(rawStyle) == 'spotlight' && (loading || hasHero);

/// Any non-Classic style uses the shared stage navigation topology.
///
/// A single active rail, identified by key, has a focused cell owning the hero
/// stage. Focus routing, rail switching, favourites and style-change teardown
/// are shared; painting differs. Favourites remain first-class rails, so they
/// do not force a Classic fallback. Loading shows the brand stage; the board's
/// empty-state guards handle a home with no content.
bool isHomeStageLayout(String style) => style != 'classic';

/// Catalog trailers need a visible stage; Mosaic disables them.
/// Live channel previews remain available on every stage layout.
bool homeStageWantsAmbient(String style) => switch (style) {
  'canvas' ||
  'promenade' ||
  'deck' ||
  'atrium' ||
  'tonight' ||
  'spotlight' => true,
  _ => false,
};

/// Layouts whose edge-to-edge artwork continues behind the app shell.
bool homeStagePublishesShellArt(String style) => switch (style) {
  // Spotlight's hero IS the ground, edge to edge, so lighting the shell
  // behind the rail continues the board rather than cutting across it.
  'canvas' || 'promenade' || 'spotlight' => true,
  _ => false,
};

/// Layouts where the shelf can recede and the video can own the frame.
/// Atrium uses a column, Tonight uses panels, and Mosaic has no video stage.
bool homeStageTheaterEligible(String style) => switch (style) {
  'canvas' || 'promenade' || 'deck' || 'spotlight' => true,
  _ => false,
};
