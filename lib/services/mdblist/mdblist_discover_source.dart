import '../../models/advanced_search_selection.dart';
import '../../models/stremio_addon.dart';
import 'mdblist_continue_watching_service.dart';
import 'mdblist_discover_models.dart';
import 'mdblist_item_transformer.dart';
import 'mdblist_list_source.dart';
import 'mdblist_models.dart';
import 'mdblist_service.dart';

typedef MdblistContinueWatchingFetcher =
    Future<MdblistResult<MdblistContinueWatchingSnapshot>> Function({
      bool force,
    });

class MdblistDiscoverSource {
  final MdblistService service;
  final MdblistContinueWatchingFetcher _fetchContinueWatching;

  MdblistDiscoverSource._(this.service, this._fetchContinueWatching)
    : _observedAuthRevision = service.authRevision.value,
      _observedLibraryRevision = service.libraryRevision.value;

  factory MdblistDiscoverSource.forTesting(
    MdblistService service, {
    MdblistContinueWatchingFetcher? fetchContinueWatching,
  }) => MdblistDiscoverSource._(
    service,
    fetchContinueWatching ??
        ({bool force = false}) => MdblistContinueWatchingService.forTesting(
          service,
        ).fetch(force: force),
  );

  static final MdblistDiscoverSource instance = MdblistDiscoverSource._(
    MdblistService.instance,
    ({bool force = false}) =>
        MdblistContinueWatchingService.instance.fetch(force: force),
  );

  static const Duration _cacheTtl = Duration(minutes: 5);
  int _observedAuthRevision;
  int _observedLibraryRevision;
  int _generation = 0;
  int _libraryGeneration = 0;
  final Map<MdblistLibraryView, ({MdblistDiscoverPage page, DateTime at})>
  _libraryCache = {};
  final Map<MdblistListDirectory, ({MdblistDiscoverChoices data, DateTime at})>
  _directoryCache = {};
  ({MdblistDiscoverChoices data, DateTime at})? _recommendationCache;
  final Map<String, ({MdblistDiscoverPage page, DateTime at})> _choiceCache =
      {};
  final Map<String, MdblistDiscoverPage> _catalogCache = {};
  MdblistCatalogQuota? _catalogQuota;

  MdblistCatalogQuota? get catalogQuota {
    _ensureAccountScope();
    return _catalogQuota;
  }

  bool hasCachedCatalog(MdblistCatalogQuery query) {
    _ensureAccountScope();
    return _catalogCache.containsKey(query.normalized.cacheKey);
  }

  void _ensureAccountScope() {
    final auth = service.authRevision.value;
    if (auth != _observedAuthRevision) {
      resetProfileScope();
      return;
    }
    final library = service.libraryRevision.value;
    if (library != _observedLibraryRevision) {
      _observedLibraryRevision = library;
      _libraryGeneration++;
      _libraryCache.clear();
    }
  }

  bool _scopeChanged(int generation) {
    _ensureAccountScope();
    return generation != _generation;
  }

  bool _libraryScopeChanged(int generation, int libraryGeneration) {
    _ensureAccountScope();
    return generation != _generation || libraryGeneration != _libraryGeneration;
  }

  void invalidateListDirectories() {
    _directoryCache.remove(MdblistListDirectory.liked);
    _directoryCache.remove(MdblistListDirectory.top);
    _directoryCache.remove(MdblistListDirectory.curated);
    _directoryCache.remove(MdblistListDirectory.mine);
    _choiceCache.clear();
  }

  void resetProfileScope() {
    _observedAuthRevision = service.authRevision.value;
    _observedLibraryRevision = service.libraryRevision.value;
    _generation++;
    _libraryGeneration++;
    _libraryCache.clear();
    _directoryCache.clear();
    _recommendationCache = null;
    _choiceCache.clear();
    _catalogCache.clear();
    _catalogQuota = null;
  }

  bool _fresh(DateTime at) => DateTime.now().difference(at) < _cacheTtl;

  Future<MdblistDiscoverPage> loadLibrary(
    MdblistLibraryView view, {
    bool force = false,
  }) async {
    _ensureAccountScope();
    final cached = _libraryCache[view];
    if (!force && cached != null && _fresh(cached.at)) {
      return cached.page.copyWith(fromCache: true);
    }
    final generation = _generation;
    final libraryGeneration = _libraryGeneration;
    final loaded = view == MdblistLibraryView.continueWatching
        ? await _loadContinueWatching(force: force)
        : await _loadLibrarySnapshot(view);
    if (_libraryScopeChanged(generation, libraryGeneration)) {
      return const MdblistDiscoverPage(
        kind: MdblistResultKind.transientFailure,
      );
    }
    if (loaded.complete) {
      _libraryCache[view] = (page: loaded, at: DateTime.now());
      return loaded;
    }
    if (cached != null) {
      return cached.page.copyWith(
        kind: MdblistResultKind.partial,
        fromCache: true,
      );
    }
    return loaded;
  }

  Future<MdblistDiscoverPage> _loadContinueWatching({
    required bool force,
  }) async {
    final result = await _fetchContinueWatching(force: force);
    final snapshot = result.data;
    if (snapshot == null) return MdblistDiscoverPage(kind: result.kind);
    final items = <StremioMeta>[];
    final progress = <String, double>{};
    for (final item in [...snapshot.movies, ...snapshot.shows]) {
      final meta = _metaFromSelection(item.selection);
      items.add(meta);
      final percent = item.selection.mdblistProgressPercent;
      if (percent != null && percent > 0) {
        progress[item.selection.imdbId] = (percent / 100).clamp(0, 1);
      }
    }
    return MdblistDiscoverPage(
      items: _dedup(items),
      progressByImdb: progress,
      kind: result.kind,
    );
  }

  Future<MdblistDiscoverPage> _loadLibrarySnapshot(
    MdblistLibraryView view,
  ) async {
    if (view == MdblistLibraryView.watchlist) {
      final result = await service.fetchWatchlist();
      return _pageFromRows(result);
    }
    final bucket = switch (view) {
      MdblistLibraryView.history => 'watched',
      MdblistLibraryView.collection => 'collection',
      MdblistLibraryView.ratings => 'ratings',
      MdblistLibraryView.dropped => 'dropped',
      _ => throw StateError('Unsupported library snapshot: $view'),
    };
    if (view == MdblistLibraryView.dropped) {
      return _pageFromRows(
        await service.fetchSyncSnapshot(bucket, mediaType: 'show'),
      );
    }
    final results = await Future.wait([
      service.fetchSyncSnapshot(bucket, mediaType: 'movie'),
      service.fetchSyncSnapshot(bucket, mediaType: 'show'),
    ]);
    final movieResult = results[0];
    final showResult = results[1];
    final rows = <Map<String, dynamic>>[
      ...?movieResult.data,
      ...?showResult.data,
    ];
    final kind = movieResult.isSuccess && showResult.isSuccess
        ? MdblistResultKind.success
        : rows.isNotEmpty
        ? MdblistResultKind.partial
        : !movieResult.isSuccess
        ? movieResult.kind
        : showResult.kind;
    final items = _activityOrdered(
      _dedup(MdblistItemTransformer.transformItems(rows)),
    );
    return MdblistDiscoverPage(items: items, kind: kind);
  }

  Future<MdblistDiscoverChoices> loadRecommendationChoices({
    bool force = false,
  }) async {
    _ensureAccountScope();
    final cached = _recommendationCache;
    if (!force && cached != null && _fresh(cached.at)) {
      return MdblistDiscoverChoices(
        choices: cached.data.choices,
        kind: cached.data.kind,
        fromCache: true,
      );
    }
    final generation = _generation;
    final result = await service.fetchRecommendationSections();
    if (_scopeChanged(generation)) {
      return const MdblistDiscoverChoices(
        kind: MdblistResultKind.transientFailure,
      );
    }
    if (!result.isSuccess) {
      return cached == null
          ? MdblistDiscoverChoices(kind: result.kind)
          : MdblistDiscoverChoices(
              choices: cached.data.choices,
              kind: MdblistResultKind.partial,
              fromCache: true,
            );
    }
    final choices = <MdblistDiscoverChoice>[];
    for (final row in result.data!) {
      final id = _string(
        row['section'] ?? row['slug'] ?? row['id'] ?? row['name'],
      );
      if (id == null) continue;
      choices.add(
        MdblistDiscoverChoice(
          id: id,
          label: _recommendationLabel(
            id,
            _string(row['name'] ?? row['title'] ?? row['label']),
          ),
          kind: MdblistDiscoverChoiceKind.recommendation,
        ),
      );
    }
    final data = MdblistDiscoverChoices(choices: choices);
    _recommendationCache = (data: data, at: DateTime.now());
    return data;
  }

  Future<MdblistDiscoverChoices> loadDirectory(
    MdblistListDirectory directory, {
    bool force = false,
  }) async {
    _ensureAccountScope();
    final cached = _directoryCache[directory];
    if (!force && cached != null && _fresh(cached.at)) {
      return MdblistDiscoverChoices(
        choices: cached.data.choices,
        kind: cached.data.kind,
        fromCache: true,
      );
    }
    final generation = _generation;
    final result = switch (directory) {
      MdblistListDirectory.mine => service.fetchUserListsResult(),
      MdblistListDirectory.liked => service.fetchLikedListsResult(),
      MdblistListDirectory.top => service.fetchTopListsResult(),
      MdblistListDirectory.curated => service.fetchCuratedListsResult(),
      MdblistListDirectory.official => service.fetchOfficialListsResult(),
      MdblistListDirectory.external => service.fetchExternalListsResult(),
      MdblistListDirectory.searchResult => Future.value(
        const MdblistResult.success(<Map<String, dynamic>>[]),
      ),
    };
    final loaded = await result;
    if (_scopeChanged(generation)) {
      return const MdblistDiscoverChoices(
        kind: MdblistResultKind.transientFailure,
      );
    }
    if (!loaded.isComplete && cached != null) {
      return MdblistDiscoverChoices(
        choices: cached.data.choices,
        kind: MdblistResultKind.partial,
        fromCache: true,
      );
    }
    if (!loaded.isUsable) {
      return MdblistDiscoverChoices(kind: loaded.kind);
    }
    final choices = <MdblistDiscoverChoice>[];
    for (final row in loaded.data!) {
      final choice = _choiceFromRow(directory, row);
      if (choice != null) choices.add(choice);
    }
    final data = MdblistDiscoverChoices(choices: choices, kind: loaded.kind);
    if (loaded.isComplete) {
      _directoryCache[directory] = (data: data, at: DateTime.now());
    }
    return data;
  }

  Future<MdblistDiscoverPage> loadChoice(
    MdblistDiscoverChoice choice, {
    String? cursor,
    String? mediaType,
  }) async {
    _ensureAccountScope();
    final key = '${choice.kind.name}|${choice.id}|${mediaType ?? 'all'}';
    final cached = _choiceCache[key];
    if (cursor == null && cached != null && _fresh(cached.at)) {
      return cached.page.copyWith(fromCache: true);
    }
    final generation = _generation;
    final result = switch (choice.kind) {
      MdblistDiscoverChoiceKind.recommendation =>
        service.fetchRecommendationItemsPage(
          choice.id,
          cursor: cursor,
          mediaType: mediaType,
        ),
      MdblistDiscoverChoiceKind.officialList =>
        service.fetchOfficialListItemsPage(
          choice.slug!,
          cursor: cursor,
          mediaType: mediaType,
        ),
      MdblistDiscoverChoiceKind.externalList =>
        service.fetchExternalListItemsPage(
          choice.numericId!,
          cursor: cursor,
          mediaType: mediaType,
        ),
      MdblistDiscoverChoiceKind.regularList => null,
    };
    late MdblistDiscoverPage page;
    if (result != null) {
      final loaded = await result;
      final raw = loaded.data;
      page = MdblistDiscoverPage(
        items: raw == null
            ? const []
            : _dedup(MdblistItemTransformer.transformItems(raw.items)),
        kind: loaded.kind,
        nextCursor: raw?.nextCursor,
        quota: raw?.quota,
      );
    } else {
      final id = choice.numericId;
      if (id == null) {
        page = const MdblistDiscoverPage(
          kind: MdblistResultKind.malformedResponse,
        );
      } else {
        final loaded = await service.fetchListItemsResult(id);
        final data = loaded.data;
        final items = <StremioMeta>[
          if (data?['movies'] is List)
            ...MdblistItemTransformer.transformItems(data!['movies'] as List),
          if (data?['shows'] is List)
            ...MdblistItemTransformer.transformItems(data!['shows'] as List),
        ];
        page = MdblistDiscoverPage(items: _dedup(items), kind: loaded.kind);
      }
    }
    if (_scopeChanged(generation)) {
      return const MdblistDiscoverPage(
        kind: MdblistResultKind.transientFailure,
      );
    }
    if (!page.complete) {
      if (cursor == null && cached != null) {
        return cached.page.copyWith(
          kind: MdblistResultKind.partial,
          fromCache: true,
        );
      }
      return page;
    }
    if (cursor == null) {
      _choiceCache[key] = (page: page, at: DateTime.now());
    } else if (cached != null && cached.page.nextCursor == cursor) {
      _choiceCache[key] = (
        page: MdblistDiscoverPage(
          items: _dedup([...cached.page.items, ...page.items]),
          kind: page.kind,
          nextCursor: page.nextCursor,
        ),
        at: DateTime.now(),
      );
    }
    return page;
  }

  Future<MdblistDiscoverPage> applyCatalog(
    MdblistCatalogQuery query, {
    bool force = false,
  }) async {
    _ensureAccountScope();
    query = query.normalized;
    final key = query.cacheKey;
    final cached = _catalogCache[key];
    if (!force && cached != null) return cached.copyWith(fromCache: true);
    if (!force && _catalogQuota?.exhausted == true) {
      return MdblistDiscoverPage(
        kind: MdblistResultKind.rateLimited,
        quota: _catalogQuota,
      );
    }
    final generation = _generation;
    final result = await service.fetchCatalogPage(query);
    if (_scopeChanged(generation)) {
      return const MdblistDiscoverPage(
        kind: MdblistResultKind.transientFailure,
      );
    }
    final raw = result.data;
    if (raw?.quota != null) _catalogQuota = raw!.quota;
    final page = MdblistDiscoverPage(
      items: raw == null
          ? const []
          : _dedup(MdblistItemTransformer.transformItems(raw.items)),
      kind: result.kind,
      nextCursor: raw?.nextCursor,
      quota: raw?.quota ?? _catalogQuota,
    );
    if (page.complete) _catalogCache[key] = page;
    return page;
  }

  Future<MdblistDiscoverPage> loadMoreCatalog(
    MdblistCatalogQuery query,
    MdblistDiscoverPage current,
  ) async {
    _ensureAccountScope();
    query = query.normalized;
    if (_catalogQuota?.exhausted == true) {
      return current.copyWith(
        kind: MdblistResultKind.rateLimited,
        quota: _catalogQuota,
      );
    }
    final cursor = current.nextCursor;
    if (cursor == null || cursor.isEmpty) return current;
    final generation = _generation;
    final result = await service.fetchCatalogPage(query, cursor: cursor);
    if (_scopeChanged(generation)) return current;
    final raw = result.data;
    if (raw?.quota != null) _catalogQuota = raw!.quota;
    if (raw == null) {
      return current.copyWith(kind: MdblistResultKind.partial);
    }
    final merged = _dedup([
      ...current.items,
      ...MdblistItemTransformer.transformItems(raw.items),
    ]);
    final page = current.copyWith(
      items: merged,
      kind: result.kind,
      nextCursor: raw.nextCursor,
      clearCursor: raw.nextCursor == null,
      quota: raw.quota ?? _catalogQuota,
      fromCache: false,
    );
    if (result.isSuccess) _catalogCache[query.cacheKey] = page;
    return page;
  }

  MdblistDiscoverPage _pageFromRows(
    MdblistResult<List<Map<String, dynamic>>> result,
  ) {
    final items = _activityOrdered(
      _dedup(MdblistItemTransformer.transformItems(result.data ?? const [])),
    );
    return MdblistDiscoverPage(items: items, kind: result.kind);
  }

  List<StremioMeta> _activityOrdered(List<StremioMeta> items) {
    final indexed = items.indexed.toList();
    indexed.sort((a, b) {
      final activity = (b.$2.addedAtMs ?? 0).compareTo(a.$2.addedAtMs ?? 0);
      return activity != 0 ? activity : a.$1.compareTo(b.$1);
    });
    return [for (final value in indexed) value.$2];
  }

  MdblistDiscoverChoice? _choiceFromRow(
    MdblistListDirectory directory,
    Map<String, dynamic> row,
  ) {
    if (directory == MdblistListDirectory.official) {
      final slug = _string(row['slug']);
      final name = _string(row['name']);
      if (slug == null || name == null) return null;
      return MdblistDiscoverChoice(
        id: slug,
        label: name,
        slug: slug,
        itemCount:
            _integer(row['items']) ??
            ((_integer(row['movies']) ?? 0) + (_integer(row['shows']) ?? 0)),
        kind: MdblistDiscoverChoiceKind.officialList,
      );
    }
    final parsed = MdblistListChoice.fromJson(row);
    if (parsed.id < 0) return null;
    return MdblistDiscoverChoice(
      id: parsed.id.toString(),
      label: parsed.name,
      numericId: parsed.id,
      ownerName: parsed.ownerName,
      itemCount: parsed.itemCount,
      liked: parsed.liked,
      likes: parsed.likes,
      kind: directory == MdblistListDirectory.external
          ? MdblistDiscoverChoiceKind.externalList
          : MdblistDiscoverChoiceKind.regularList,
    );
  }

  StremioMeta _metaFromSelection(
    AdvancedSearchSelection selection,
  ) => StremioMeta(
    id: selection.imdbId,
    imdbId: selection.imdbId,
    type: selection.isSeries ? 'series' : 'movie',
    name: selection.title,
    poster:
        selection.posterUrl ??
        'https://images.metahub.space/poster/medium/${selection.imdbId}/img',
    background:
        'https://images.metahub.space/background/medium/${selection.imdbId}/img',
    year: selection.year,
  );

  List<StremioMeta> _dedup(Iterable<StremioMeta> items) {
    final seen = <String>{};
    return [
      for (final item in items)
        if (seen.add((item.imdbId ?? item.id).toLowerCase())) item,
    ];
  }

  String _recommendationLabel(String id, String? apiLabel) {
    if (apiLabel != null) return apiLabel;
    return switch (id.toLowerCase()) {
      'recommended' => 'Recommended for You',
      'trending' => 'Trending in Your Genres',
      'similar' => 'Popular Among Similar Users',
      'rising' => 'Rising Fast',
      _ => id,
    };
  }

  String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  int? _integer(Object? value) => value is num
      ? value.toInt()
      : value is String
      ? int.tryParse(value)
      : null;
}
