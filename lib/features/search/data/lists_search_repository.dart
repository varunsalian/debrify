import '../../../services/mdblist/mdblist_list_source.dart';
import '../../../services/mdblist/mdblist_models.dart';

abstract interface class ListsSearchRepository {
  bool get enabled;
  bool get isCurrent;
  Future<bool> isAuthenticated();
  Future<MdblistResult<List<MdblistListChoice>>> search(String query);
}
