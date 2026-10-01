import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/mdblist/mdblist_list_source.dart';
import '../../../services/mdblist/mdblist_models.dart';
import '../data/lists_search_repository.dart';
import '../models/search_session.dart';
import '../models/lists_search_state.dart';
import 'search_providers.dart';

final listsSearchProvider = NotifierProvider.autoDispose
    .family<ListsSearchController, ListsSearchState, SearchSession>(
      ListsSearchController.new,
      retry: (count, error) => null,
    );

class ListsSearchController extends Notifier<ListsSearchState> {
  ListsSearchController(this.session);

  final SearchSession session;
  late ListsSearchRepository _repository;
  int _generation = 0;

  @override
  ListsSearchState build() {
    _repository = ref.watch(listsSearchRepositoryProvider(session));
    ref.onDispose(() => _generation++);
    return const ListsSearchState.idle();
  }

  bool _accepts(int generation) =>
      ref.mounted && generation == _generation && _repository.isCurrent;

  void clear() {
    _generation++;
    state = const ListsSearchState.idle();
  }

  /// True only for an accepted completion. Presentation may then reconcile
  /// focus; a superseded/disposed request must never dispatch a UI effect.
  Future<bool> search(String query) async {
    if (!_repository.enabled || !_repository.isCurrent) return false;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clear();
      return false;
    }
    final generation = ++_generation;
    state = ListsSearchState(query: trimmed, searching: true);
    final connected = await _repository.isAuthenticated();
    if (!_accepts(generation)) return false;
    if (!connected) {
      state = ListsSearchState(
        query: trimmed,
        error: 'Connect MDBList in Settings to search public lists.',
      );
      return true;
    }
    MdblistResult<List<MdblistListChoice>> result;
    try {
      result = await _repository.search(trimmed);
    } catch (_) {
      result = const MdblistResult.failure(MdblistResultKind.transientFailure);
    }
    if (!_accepts(generation)) return false;
    state = ListsSearchState(
      query: trimmed,
      results: result.data ?? const [],
      error: result.isUsable ? null : _failureMessage(result),
    );
    return true;
  }

  String _failureMessage(
    MdblistResult<List<MdblistListChoice>> result,
  ) => switch (result.kind) {
    MdblistResultKind.unauthenticated =>
      'Your MDBList connection has expired. Reconnect it in Settings.',
    MdblistResultKind.denied =>
      'MDBList denied this list search for the connected account.',
    MdblistResultKind.rateLimited =>
      result.retryAfter == null
          ? 'MDBList rate limit reached. Try again later.'
          : 'MDBList rate limit reached. Try again in '
                '${(result.retryAfter!.inSeconds / 60).ceil().clamp(1, 9999)} minutes.',
    MdblistResultKind.malformedResponse =>
      'MDBList returned an unreadable list-search response. Try again.',
    MdblistResultKind.notFound =>
      'MDBList list search is currently unavailable.',
    MdblistResultKind.conflict =>
      'MDBList could not complete this list search. Try again.',
    MdblistResultKind.disabled =>
      'MDBList list search is disabled for this build.',
    MdblistResultKind.transientFailure =>
      'MDBList is not responding right now. Try again shortly.',
    MdblistResultKind.success || MdblistResultKind.partial => '',
  };
}
