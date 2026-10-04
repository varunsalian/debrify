class EpisodesPanelAuth {
  /// Whether a Trakt account is connected. This screen is reachable from
  /// Discover/catalog without Trakt, so the Trakt-only episode menu (mark
  /// watched/unwatched, rate) is only offered when this is true.
  bool traktAuthenticated = false;

  /// Whether Simkl is connected, for watched-action destinations and options.
  bool simklAuthenticated = false;

  bool mdblistAuthenticated = false;

  // MDBList can acknowledge a completed scrobble just before the player route
  // finishes popping, and its watched snapshot can trail that acknowledgement
  // briefly. Keep only the newest mutation refresh, wait until this panel's
  // route is visible, then perform one consistency retry. Without this, the
  // pre-stop refresh could leave a completed episode showing its old local
  // progress until the detail page was reopened.
  int mdblistRefreshToken = 0;
}
