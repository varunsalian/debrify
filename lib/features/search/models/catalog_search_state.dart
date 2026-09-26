import 'catalog_search_row.dart';

class CatalogSearchState {
  final String query;
  final bool searching;
  final int failures;
  final List<CatalogSearchRow> rows;

  const CatalogSearchState({
    this.query = '',
    this.searching = false,
    this.failures = 0,
  }) : rows = const [];

  const CatalogSearchState._({
    required this.query,
    required this.searching,
    required this.failures,
    required this.rows,
  });

  CatalogSearchState copyWith({
    bool? searching,
    int? failures,
    List<CatalogSearchRow>? rows,
  }) => CatalogSearchState._(
    query: query,
    searching: searching ?? this.searching,
    failures: failures ?? this.failures,
    rows: rows == null ? this.rows : List.unmodifiable(rows),
  );
}

enum CatalogSearchCompletion { accepted, failed, stale }
