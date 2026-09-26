import '../../../services/mdblist/mdblist_list_source.dart';

class ListsSearchState {
  final String query;
  final List<MdblistListChoice> results;
  final bool searching;
  final String? error;

  const ListsSearchState.idle()
    : query = '',
      results = const [],
      searching = false,
      error = null;

  ListsSearchState({
    required this.query,
    List<MdblistListChoice> results = const [],
    this.searching = false,
    this.error,
  }) : results = List.unmodifiable(results);
}
