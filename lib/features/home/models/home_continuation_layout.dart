/// Per-provider merged shelves retain the existing movies row identifiers.
class HomeContinuationLayout {
  const HomeContinuationLayout({
    this.local = false,
    this.trakt = false,
    this.simkl = false,
    this.mdblist = false,
  });

  final bool local;
  final bool trakt;
  final bool simkl;
  final bool mdblist;

  @override
  bool operator ==(Object other) =>
      other is HomeContinuationLayout &&
      local == other.local &&
      trakt == other.trakt &&
      simkl == other.simkl &&
      mdblist == other.mdblist;

  @override
  int get hashCode => Object.hash(local, trakt, simkl, mdblist);
}
