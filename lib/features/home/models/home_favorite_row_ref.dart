/// The kinds of leading saved-content rows. Render order (Watchlist Movies,
/// Watchlist Series, Playlist, Debrify TV, Stremio TV, IPTV) is defined by
/// the Home row projection, the single source of truth for rendering
/// and the index-based DPAD focus wiring.
enum HomeFavoriteKind {
  watchlistMovies,
  watchlistSeries,
  iptv,
  debrify,
  stremio,
  playlist,
}

/// One visible favourites-family row: a singleton [kind] row ([list] == -1),
/// or — for `kind == HomeFavoriteKind.iptv` with [list] >= 0 — the IPTV custom-list
/// row at that index of the Home IPTV list snapshot. Value-equal so
/// rebuilt ref lists compare cleanly.
class HomeFavoriteRowRef {
  final HomeFavoriteKind kind;
  final int list;
  const HomeFavoriteRowRef(this.kind, [this.list = -1]);

  bool get isIptvList => list >= 0;

  @override
  bool operator ==(Object other) =>
      other is HomeFavoriteRowRef && other.kind == kind && other.list == list;

  @override
  int get hashCode => Object.hash(kind, list);
}
