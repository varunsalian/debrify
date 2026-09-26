import '../../../services/mdblist/mdblist_list_source.dart';
import '../../../services/mdblist/mdblist_models.dart';
import '../../../services/mdblist/mdblist_service.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import 'lists_search_repository.dart';

/// Borrows existing services and their retry/cache/credential behavior. No
/// provider owns or disposes those process-lifetime services.
class MdblistSearchRepository implements ListsSearchRepository {
  final ProfileSessionOwner owner;
  final MdblistService service;
  final MdblistListSource source;

  const MdblistSearchRepository({
    required this.owner,
    required this.service,
    required this.source,
  });

  @override
  bool get enabled => kMdblistEnabled;

  @override
  bool get isCurrent => owner == ProfileSessionMemory.captureOwner();

  Future<T> _inCapturedScope<T>(Future<T> Function() operation) {
    final scope = owner.scope;
    return scope == null
        ? operation()
        : ProfileRuntime.withCapturedScope(scope, operation);
  }

  @override
  Future<bool> isAuthenticated() => isCurrent
      ? _inCapturedScope(service.isAuthenticated)
      : Future.value(false);

  @override
  Future<MdblistResult<List<MdblistListChoice>>> search(String query) =>
      isCurrent
      ? _inCapturedScope(() => source.searchListsResult(query))
      : Future.value(
          const MdblistResult.failure(MdblistResultKind.unauthenticated),
        );
}
