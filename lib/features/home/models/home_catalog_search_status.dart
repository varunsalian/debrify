/// What Home needs to know about the screen's catalog search: while one is
/// active its results replace the board rows, and Home must not stomp them.
///
/// Home declares this contract; the Search feature implements it, so Home never
/// depends on Search's implementation.
abstract interface class HomeCatalogSearchStatus {
  bool get catalogSearching;
  String get catalogQuery;

  /// Addons that failed during the current catalog search.
  int get catalogFailures;

  /// Clears catalog-search results before the Home board is restored.
  void clearCatalogResults();

  /// Re-runs the catalog search for [query].
  Future<void> runCatalogSearch(String query);
}
