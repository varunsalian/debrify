/// Specials do not prevent completion of the regular series. Unknown/empty
/// season inventories must not make a series appear completed.
bool isSeriesFullyWatched(
  Map<int, Iterable<int>> seasons,
  Map<String, double> progress,
) {
  final regular = seasons.entries.where((e) => e.key > 0).toList();
  return regular.isNotEmpty &&
      regular.every(
        (season) =>
            season.value.isNotEmpty &&
            season.value.every(
              (episode) => (progress['${season.key}-$episode'] ?? 0) >= 100,
            ),
      );
}
