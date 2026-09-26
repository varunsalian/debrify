import 'package:debrify/features/search/data/lists_search_repository.dart';
import 'package:debrify/services/mdblist/mdblist_list_source.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';

class FakeListsSearchRepository implements ListsSearchRepository {
  @override
  bool enabled = true;
  @override
  bool isCurrent = true;
  bool connected = true;
  int authCalls = 0;
  final queries = <String>[];
  Future<bool> Function()? authenticate;
  Future<MdblistResult<List<MdblistListChoice>>> Function(String)? fetch;

  @override
  Future<bool> isAuthenticated() {
    authCalls++;
    return authenticate?.call() ?? Future.value(connected);
  }

  @override
  Future<MdblistResult<List<MdblistListChoice>>> search(String query) {
    queries.add(query);
    return fetch?.call(query) ?? Future.value(const MdblistResult.success([]));
  }
}
