import '../../models/mdblist_list_choice.dart';
import '../../models/stremio_addon.dart';
import 'mdblist_item_transformer.dart';
import 'mdblist_models.dart';
import 'mdblist_service.dart';

export '../../models/mdblist_list_choice.dart';

/// Loads MDBList lists into [StremioMeta] grids for the Discover / See-All view.
/// Pure data logic — no UI — so it can be shared by any screen that browses
/// MDBList lists. Stateless singleton, mirroring [TraktListSource].
///
/// Step 2 scope: the user's OWN lists only. Top/public lists and list search
/// are a later step (see project memory).
class MdblistListSource {
  final MdblistService service;

  MdblistListSource._(this.service);
  factory MdblistListSource.forTesting(MdblistService service) =>
      MdblistListSource._(service);
  static final MdblistListSource instance = MdblistListSource._(
    MdblistService.instance,
  );

  /// The user's own lists, ready to populate the "List" dropdown. Skips lists
  /// without a usable id. Returns [] when MDBList isn't connected or on error.
  Future<List<MdblistListChoice>> loadUserLists({bool strict = false}) async =>
      strict ? _completeDirectory(await service.fetchUserListsResult()) :
      _mapChoices(await service.fetchUserLists());

  /// MDBList's top/public lists (other users' popular lists). Same shape as
  /// [loadUserLists]; each choice carries its [MdblistListChoice.ownerName].
  Future<List<MdblistListChoice>> loadTopLists({bool strict = false}) async =>
      strict ? _completeDirectory(await service.fetchTopListsResult()) :
      _mapChoices(await service.fetchTopLists());

  Future<List<MdblistListChoice>> loadLikedLists({bool strict = false}) async =>
      strict ? _completeDirectory(await service.fetchLikedListsResult()) :
      _mapChoices(await service.fetchLikedLists());

  List<MdblistListChoice> _completeDirectory(
    MdblistResult<List<Map<String, dynamic>>> result,
  ) {
    if (!result.isComplete || result.data == null) {
      throw StateError('MDBList directory incomplete');
    }
    final choices = _mapChoices(result.data!);
    if (choices.length != result.data!.length) {
      throw const FormatException('MDBList directory identity missing');
    }
    return choices;
  }

  /// Searches MDBList's public lists by name. Same shape as the others.
  Future<List<MdblistListChoice>> searchLists(String query) async =>
      _mapChoices(await service.searchLists(query));

  /// Typed counterpart used by dedicated search surfaces that must distinguish
  /// a genuine empty result from auth, quota, transport, and parse failures.
  Future<MdblistResult<List<MdblistListChoice>>> searchListsResult(
    String query,
  ) async {
    final raw = await service.searchListsResult(query);
    final data = raw.data;
    if (data == null) {
      return MdblistResult.failure(
        raw.kind,
        statusCode: raw.statusCode,
        retryAfter: raw.retryAfter,
        headers: raw.headers,
      );
    }
    final mapped = _mapChoices(data);
    return raw.kind == MdblistResultKind.partial
        ? MdblistResult.partial(
            mapped,
            statusCode: raw.statusCode,
            headers: raw.headers,
          )
        : MdblistResult.success(
            mapped,
            statusCode: raw.statusCode,
            headers: raw.headers,
          );
  }

  List<MdblistListChoice> _mapChoices(List<Map<String, dynamic>> raw) {
    final out = <MdblistListChoice>[];
    for (final j in raw) {
      final choice = MdblistListChoice.fromJson(j);
      if (choice.id >= 0) out.add(choice);
    }
    return out;
  }

  /// One page for Home. `complete` describes the preview request, not whether
  /// the remote list has further pages; See All uses [loadListItems] instead.
  Future<({List<StremioMeta> items, bool failed, bool complete})> loadHomePreview(
    MdblistListChoice choice,
  ) async {
    final result = await service.fetchHomeListPreview(choice.id);
    return (
      items: _dedup(MdblistItemTransformer.transformItems(
        result.data?.items ?? const [],
      )),
      failed: !result.isSuccess,
      complete: result.isSuccess,
    );
  }

  /// Load all list pages for See All, keeping errors distinct from empty lists.
  Future<({List<StremioMeta> items, bool failed, bool complete})> loadListItems(
    MdblistListChoice choice, {
    bool forceRefresh = false,
  }) async {
    final result = await service.fetchListItemsResult(
      choice.id,
      forceRefresh: forceRefresh,
    );
    final data = result.data;
    if (data == null) {
      return (items: const <StremioMeta>[], failed: true, complete: false);
    }
    final movies = data['movies'];
    final shows = data['shows'];
    final metas = <StremioMeta>[
      if (movies is List) ...MdblistItemTransformer.transformItems(movies),
      if (shows is List) ...MdblistItemTransformer.transformItems(shows),
    ];
    return (
      items: _dedup(metas),
      failed: !result.isUsable,
      complete: result.isComplete,
    );
  }

  List<StremioMeta> _dedup(List<StremioMeta> metas) {
    final seen = <String>{};
    final out = <StremioMeta>[];
    for (final m in metas) {
      if (seen.add(m.imdbId ?? m.id)) out.add(m);
    }
    return out;
  }
}
