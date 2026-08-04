import '../../models/stremio_addon.dart';

/// Shared "Date Added" ordering for the tracker See-All grids.
///
/// Trakt and Simkl both stamp [StremioMeta.addedAtMs] from the row that put a
/// title in the user's list, so one comparator serves both — and the two grids
/// can't drift into ordering the same thing differently.
///
/// Undated items sink to the end in BOTH directions rather than leading the
/// "oldest" order, matching how the IMDb sorts treat unrated titles: a missing
/// value is unknown, not zero. Ties fall back to A–Z so the order is stable
/// across rebuilds (a list can hold many rows added in the same second).
int Function(StremioMeta, StremioMeta) byAddedDate({required bool newest}) {
  return (a, b) {
    final ta = a.addedAtMs, tb = b.addedAtMs;
    if (ta == null && tb == null) {
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
    if (ta == null) return 1;
    if (tb == null) return -1;
    final byDate = newest ? tb.compareTo(ta) : ta.compareTo(tb);
    if (byDate != 0) return byDate;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  };
}

/// Whether a loaded list can be ordered by date at all. Public/catalogue rows
/// (Trending, Popular, Simkl's best/premieres) carry no per-user date, so the
/// grids hide the option instead of offering one that reshuffles into A–Z.
bool hasAddedDates(List<StremioMeta> items) =>
    items.any((m) => m.addedAtMs != null);

/// Settle a remembered date sort against the list that has just loaded.
///
/// A Discover panel can never apply a stored date sort at mount: Trakt opens on
/// Continue Watching and Simkl on CW or Trending, none of which carry dates —
/// and the list switch that finally reaches a dated list resets the sort to
/// [natural]. Without this hand-off the preference is written to storage and
/// never once applied.
///
/// The remembered value is claimed only over [natural], so that reset is
/// honoured while a sort the user picked in the meantime is left alone. Either
/// way the deferral is spent: a stored preference restores itself once, it does
/// not keep overriding later choices.
({T sort, T? deferred}) settleDeferredSort<T>({
  required T? deferred,
  required T current,
  required T natural,
  required bool listHasDates,
}) {
  if (deferred == null || !listHasDates) {
    return (sort: current, deferred: deferred);
  }
  return (sort: current == natural ? deferred : current, deferred: null);
}
