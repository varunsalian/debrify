import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../storage_service.dart';
import '../episode_tracker_snapshot_revision.dart';
import '../../models/profiles/profile_policy.dart';
import '../profiles/profile_async_authorization.dart';
import '../profiles/profile_credential_facade.dart';
import 'mdblist_discover_models.dart';
import 'mdblist_models.dart';
import 'mdblist_transport.dart';

/// Feature flag — MDBList is unfinished, so its Settings entry is hidden for
/// the alpha. Flip to `true` to re-expose it. (Deliberately not `const` so the
/// gated branches don't read as dead code to the analyzer.) The Discover/Search
/// surfaces gate on being connected instead, so with this off and no stored key
/// nothing MDBList is reachable.
final bool kMdblistEnabled = true;

/// A small snapshot of the connected MDBList account, used to render the
/// settings page's status/account card. Not persisted as a whole — only the
/// API key and resolved username are stored (see [StorageService]).
class MdblistAccount {
  final int? userId;
  final String? username;
  final int listCount;
  final String? patronStatus;
  final int apiRequests;
  final int apiRequestsUsed;

  const MdblistAccount({
    this.userId,
    this.username,
    this.listCount = 0,
    this.patronStatus,
    this.apiRequests = 0,
    this.apiRequestsUsed = 0,
  });
}

/// Thin client for the MDBList API (https://api.mdblist.com).
///
/// MDBList auth is a single API key (from mdblist.com/preferences) passed as
/// the `apikey` query param on every request — there is no OAuth/PIN flow, so
/// "connecting" is just validating the key and remembering it. This service
/// only covers what the settings page needs: validate a key, fetch a small
/// account snapshot, and log out. Browsing the actual lists lives elsewhere
/// (a later step).
class MdblistService {
  MdblistService._({
    http.Client? client,
    MdblistApiKeyProvider? apiKeyProvider,
    bool Function()? featureEnabled,
    Uri? baseUri,
  }) : _client = client ?? http.Client(),
       _apiKeyProvider =
           apiKeyProvider ?? (() => StorageService.getMdblistApiKey()),
       _featureEnabled = featureEnabled ?? (() => kMdblistEnabled),
       _baseUri = baseUri ?? Uri.parse(_base) {
    _transport = MdblistTransport(
      client: _client,
      apiKeyProvider: _apiKeyProvider,
      featureEnabled: _featureEnabled,
      baseUri: _baseUri,
    );
  }

  factory MdblistService.forTesting({
    required http.Client client,
    required MdblistApiKeyProvider apiKeyProvider,
    bool Function()? featureEnabled,
    Uri? baseUri,
  }) => MdblistService._(
    client: client,
    apiKeyProvider: apiKeyProvider,
    featureEnabled: featureEnabled ?? (() => true),
    baseUri: baseUri,
  );

  static final MdblistService instance = MdblistService._();

  /// Changes after the server accepts a playback mutation. Detail views use
  /// this to refresh after an asynchronous player-exit scrobble finishes.
  final ValueNotifier<int> playbackRevision = ValueNotifier<int>(0);

  /// Changes after MDBList accepts a mutation that can alter a title's
  /// effective watched/completed state. Global poster badges listen to this
  /// instead of [playbackRevision], because pause checkpoints must not trigger
  /// quota-sensitive watched-history refreshes.
  final ValueNotifier<int> watchedRevision = ValueNotifier<int>(0);

  /// Changes when the active MDBList credential identity changes.
  final ValueNotifier<int> authRevision = ValueNotifier<int>(0);

  /// Changes whenever server-owned MDBList Library data mutates.
  ///
  /// This intentionally does not invalidate quota-sensitive catalog results.
  final ValueNotifier<int> libraryRevision = ValueNotifier<int>(0);

  static const String _base = 'https://api.mdblist.com';
  final http.Client _client;
  final MdblistApiKeyProvider _apiKeyProvider;
  final bool Function() _featureEnabled;
  final Uri _baseUri;
  late final MdblistTransport _transport;

  bool get networkEnabled => _featureEnabled();

  /// Last successful account snapshot, kept so the settings page can render
  /// account details across rebuilds without re-hitting the network.
  MdblistAccount? currentAccount;

  // ── In-memory response cache ────────────────────────────────────────────────
  // Discover re-mounts the MDBList See-All on every source switch, so these
  // spare a fresh network round-trip when the user flips back within the TTL.
  // Only successful responses are cached (failures fall through and retry).
  // Cleared on connect (possible account change) and logout.
  static const Duration _cacheTtl = Duration(minutes: 5);
  List<Map<String, dynamic>>? _userListsCache;
  DateTime? _userListsAt;
  List<Map<String, dynamic>>? _topListsCache;
  DateTime? _topListsAt;
  List<Map<String, dynamic>>? _likedListsCache;
  DateTime? _likedListsAt;
  final Map<int, ({Map<String, dynamic> data, DateTime at})> _itemsCache = {};
  Set<String>? _droppedImdbCache;
  DateTime? _droppedImdbAt;
  Future<Set<String>?>? _droppedImdbInFlight;

  bool _fresh(DateTime? at) =>
      at != null && DateTime.now().difference(at) < _cacheTtl;

  void _clearCache() {
    _userListsCache = null;
    _userListsAt = null;
    _topListsCache = null;
    _topListsAt = null;
    _likedListsCache = null;
    _likedListsAt = null;
    _itemsCache.clear();
    _droppedImdbCache = null;
    _droppedImdbAt = null;
    _droppedImdbInFlight = null;
  }

  /// Clear account-derived state without modifying the scoped credentials.
  void resetProfileScope() {
    currentAccount = null;
    _clearCache();
    authRevision.value++;
  }

  /// Drop only caches whose server activity bucket changed. The incremental
  /// sync coordinator invalidates owning caches so their next surface fetches
  /// authoritative state instead of maintaining a second local tracker DB.
  void invalidateSyncBuckets(Set<String> buckets, {bool all = false}) {
    const libraryBuckets = {
      'playback',
      'watched',
      'watchlist',
      'collection',
      'ratings',
      'dropped',
    };
    if (all || buckets.any(libraryBuckets.contains)) libraryRevision.value++;
    if (all || buckets.contains('lists')) {
      _userListsCache = null;
      _userListsAt = null;
      _likedListsCache = null;
      _likedListsAt = null;
      _itemsCache.clear();
    }
    if (all || buckets.contains('dropped')) {
      _droppedImdbCache = null;
      _droppedImdbAt = null;
      _droppedImdbInFlight = null;
    }
  }

  Future<ProfileAsyncAuthorization?> _captureCapability({
    bool requireExistingResource = true,
  }) async {
    final authority = requireExistingResource
        ? await ProfileCredentialFacade.boundAuthority('mdblist_api_key')
        : null;
    return ProfileAsyncAuthorization.capture(
      ProfileFeature.trackersAndDiscovery,
      resourceId: authority?.resourceId,
      resourceAuthorizationRevision: authority?.resourceAuthorizationRevision,
    );
  }

  Future<ProfileAsyncAuthorization?> capturePlaybackCapability() =>
      _captureCapability();

  Future<bool> isAuthenticated() async {
    if (!networkEnabled) return false;
    final key = await _apiKeyProvider();
    return key != null && key.isNotEmpty;
  }

  Future<String?> getUsername() => StorageService.getMdblistUsername();

  /// Validates [apiKey] against the API. On success, persists the key + the
  /// resolved username, caches the snapshot in [currentAccount], and returns
  /// it. On any failure (rejected key, network error) nothing is persisted and
  /// null is returned.
  Future<MdblistAccount?> connect(String apiKey) async {
    if (!networkEnabled) return null;
    final capability = await _captureCapability(requireExistingResource: false);
    final key = apiKey.trim();
    if (key.isEmpty) return null;

    final snapshot = await _fetchAccount(key, capability: capability);
    if (snapshot == null) return null;

    Future<void> commit() async {
      await StorageService.saveMdblistApiKey(key);
      await StorageService.setMdblistUsername(snapshot.username);
      await StorageService.setMdblistSyncCheckpoint(null);
      if (capability == null || capability.isCurrentlyActive) {
        _clearCache();
        currentAccount = snapshot;
        authRevision.value++;
      }
    }

    if (capability == null) {
      await commit();
    } else {
      await capability.runIfCurrent(commit);
    }
    return snapshot;
  }

  /// Re-fetches the account snapshot for the already-stored key (for the
  /// settings page's account card). Returns null if not connected or the fetch
  /// fails; a transient failure does NOT clear stored auth.
  Future<MdblistAccount?> refreshAccount() async {
    if (!networkEnabled) return null;
    final capability = await _captureCapability();
    final key = await _apiKeyProvider();
    if (key == null || key.isEmpty) return null;
    final snapshot = await _fetchAccount(key, capability: capability);
    if (snapshot != null) {
      Future<void> commit() async {
        if (snapshot.username != null) {
          await StorageService.setMdblistUsername(snapshot.username);
        }
        if (capability == null || capability.isCurrentlyActive) {
          currentAccount = snapshot;
        }
      }

      if (capability == null) {
        await commit();
      } else {
        await capability.runIfCurrent(commit);
      }
    }
    return snapshot;
  }

  Future<void> logout() async {
    final capability = await _captureCapability();
    Future<void> clear() async {
      await StorageService.clearMdblistAuth();
      currentAccount = null;
      _clearCache();
      authRevision.value++;
    }

    if (capability == null) {
      await clear();
    } else {
      await capability.runIfCurrent(clear);
    }
  }

  Future<MdblistResult<List<Map<String, dynamic>>>> _fetchLists(
    String path, {
    Map<String, Object?> query = const {},
    List<Map<String, dynamic>>? cached,
    DateTime? cachedAt,
    void Function(List<Map<String, dynamic>>, DateTime)? publish,
  }) async {
    int? integer(Object? value) => value is num
        ? value.toInt()
        : value is String
        ? int.tryParse(value)
        : null;

    final capability = await _captureCapability();
    if (cached != null && _fresh(cachedAt)) {
      try {
        await capability?.runIfCurrent(() async {});
        return MdblistResult.success(cached);
      } catch (_) {
        return const MdblistResult.failure(MdblistResultKind.transientFailure);
      }
    }
    final lists = <Map<String, dynamic>>[];
    var offset = 0;
    String? cursor;
    var reachedEnd = false;
    final seenCursors = <String>{};
    for (var page = 0; page < 25; page++) {
      final response = await _transport.request(
        'GET',
        path,
        query: {
          ...query,
          'limit': query['limit'] ?? 100,
          if (cursor != null) 'cursor': cursor,
          if (cursor == null && offset > 0) 'offset': offset,
        },
        capability: capability,
      );
      if (!response.isSuccess) {
        if (lists.isNotEmpty) {
          return MdblistResult.partial(
            lists,
            statusCode: response.statusCode,
            headers: response.headers,
          );
        }
        return MdblistResult.failure(
          response.kind,
          statusCode: response.statusCode,
          retryAfter: response.retryAfter,
          headers: response.headers,
        );
      }

      final decoded = response.data;
      List<dynamic>? rawLists;
      Map<dynamic, dynamic>? pagination;
      if (decoded is List) {
        rawLists = decoded;
      } else if (decoded is Map && decoded['lists'] is List) {
        rawLists = decoded['lists'] as List;
        if (decoded['pagination'] is Map) {
          pagination = decoded['pagination'] as Map;
        }
      }
      if (rawLists == null || rawLists.any((value) => value is! Map)) {
        return lists.isEmpty
            ? const MdblistResult.failure(MdblistResultKind.malformedResponse)
            : MdblistResult.partial(
                lists,
                statusCode: response.statusCode,
                headers: response.headers,
              );
      }
      for (final value in rawLists) {
        lists.add(Map<String, dynamic>.from(value as Map));
      }

      final bodyCursor = pagination?['next_cursor']?.toString().trim();
      final headerCursor = response.headers?['x-next-cursor']?.trim();
      final nextCursor = bodyCursor?.isNotEmpty == true
          ? bodyCursor
          : headerCursor?.isNotEmpty == true
          ? headerCursor
          : null;
      if (nextCursor != null) {
        if (!seenCursors.add(nextCursor)) {
          return MdblistResult.partial(
            lists,
            statusCode: response.statusCode,
            headers: response.headers,
          );
        }
        cursor = nextCursor;
        continue;
      }

      final bodyHasMore = pagination?['has_more'];
      final headerHasMore = response.headers?['x-has-more'];
      final hasMore =
          bodyHasMore == true ||
          bodyHasMore?.toString().toLowerCase() == 'true' ||
          headerHasMore?.toLowerCase() == 'true';
      if (!hasMore) {
        reachedEnd = true;
        break;
      }
      if (rawLists.isEmpty) {
        return MdblistResult.partial(
          lists,
          statusCode: response.statusCode,
          headers: response.headers,
        );
      }
      final pageOffset = integer(pagination?['offset']) ?? offset;
      final pageLimit = integer(pagination?['limit']);
      offset = pageOffset + (pageLimit ?? rawLists.length);
      cursor = null;
    }
    if (!reachedEnd) return MdblistResult.partial(lists);
    try {
      await capability?.runIfCurrent(() async {
        publish?.call(lists, DateTime.now());
      });
    } catch (_) {
      return const MdblistResult.failure(MdblistResultKind.transientFailure);
    }
    return MdblistResult.success(lists);
  }

  Future<MdblistResult<List<Map<String, dynamic>>>> fetchUserListsResult() =>
      _fetchLists(
        '/lists/user',
        cached: _userListsCache,
        cachedAt: _userListsAt,
        publish: (data, at) {
          _userListsCache = data;
          _userListsAt = at;
        },
      );

  Future<List<Map<String, dynamic>>> fetchUserLists() async =>
      (await fetchUserListsResult()).data ?? const [];

  Future<MdblistResult<List<Map<String, dynamic>>>> fetchTopListsResult() =>
      _fetchLists(
        '/lists/top',
        cached: _topListsCache,
        cachedAt: _topListsAt,
        publish: (data, at) {
          _topListsCache = data;
          _topListsAt = at;
        },
      );

  Future<List<Map<String, dynamic>>> fetchTopLists() async =>
      (await fetchTopListsResult()).data ?? const [];

  Future<MdblistResult<List<Map<String, dynamic>>>> fetchLikedListsResult() =>
      _fetchLists(
        '/lists/liked',
        cached: _likedListsCache,
        cachedAt: _likedListsAt,
        publish: (data, at) {
          _likedListsCache = data;
          _likedListsAt = at;
        },
      );

  Future<List<Map<String, dynamic>>> fetchLikedLists() async =>
      (await fetchLikedListsResult()).data ?? const [];

  Future<MdblistResult<List<Map<String, dynamic>>>> searchListsResult(
    String query,
  ) async {
    final q = query.trim();
    if (q.isEmpty) return const MdblistResult.success([]);
    return _fetchLists('/lists/search', query: {'query': q});
  }

  Future<List<Map<String, dynamic>>> searchLists(String query) async =>
      (await searchListsResult(query)).data ?? const [];

  Future<MdblistResult<List<Map<String, dynamic>>>> fetchCuratedListsResult() =>
      _fetchLists('/lists/curated');

  Future<MdblistResult<List<Map<String, dynamic>>>>
  fetchOfficialListsResult() => _fetchLists('/lists/official');

  Future<MdblistResult<List<Map<String, dynamic>>>>
  fetchExternalListsResult() => _fetchLists(
    '/external/lists/user',
    query: const {'append_to_response': 'poster'},
  );

  Future<MdblistResult<List<Map<String, dynamic>>>>
  fetchRecommendationSections() async {
    final response = await _mapRequest('GET', '/lists/recommended');
    if (!response.isSuccess) {
      return MdblistResult.failure(
        response.kind,
        statusCode: response.statusCode,
        retryAfter: response.retryAfter,
        headers: response.headers,
      );
    }
    final raw = response.data?['sections'];
    if (raw is! List) {
      return const MdblistResult.failure(MdblistResultKind.malformedResponse);
    }
    final sections = <Map<String, dynamic>>[];
    for (final value in raw) {
      if (value is! Map) {
        return const MdblistResult.failure(MdblistResultKind.malformedResponse);
      }
      sections.add(Map<String, dynamic>.from(value));
    }
    return MdblistResult.success(sections, statusCode: response.statusCode);
  }

  Future<MdblistResult<MdblistRawPage>> fetchRecommendationItemsPage(
    String section, {
    String? cursor,
    String? mediaType,
    int limit = 100,
  }) => _fetchRawPage(
    '/lists/recommended/${Uri.encodeComponent(section)}/items',
    query: {
      'limit': limit.clamp(1, 1000),
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      if (mediaType != null) 'mediatype': mediaType,
      'unified': true,
      'append_to_response': 'poster,ratings,description,genres',
    },
  );

  Future<MdblistResult<MdblistRawPage>> fetchOfficialListItemsPage(
    String slug, {
    String? cursor,
    String? mediaType,
    int limit = 100,
  }) => _fetchRawPage(
    '/lists/official/${Uri.encodeComponent(slug)}/items',
    query: {
      'limit': limit.clamp(1, 1000),
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      if (mediaType != null) 'mediatype': mediaType,
      'unified': true,
      'append_to_response': 'poster,ratings,description,genres',
    },
  );

  Future<MdblistResult<MdblistRawPage>> fetchExternalListItemsPage(
    int listId, {
    String? cursor,
    String? mediaType,
    int limit = 100,
  }) => _fetchRawPage(
    '/external/lists/$listId/items',
    query: {
      'limit': limit.clamp(1, 1000),
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      if (mediaType != null) 'mediatype': mediaType,
      'unified': true,
      'append_to_response': 'poster,ratings,description,genres',
    },
  );

  Future<MdblistResult<MdblistRawPage>> fetchCatalogPage(
    MdblistCatalogQuery catalogQuery, {
    String? cursor,
    int limit = 100,
  }) {
    final query = catalogQuery.normalized;
    return _fetchRawPage(
      '/catalog/${query.mediaType}',
      query: query.toQuery(cursor: cursor, limit: limit),
    );
  }

  Future<MdblistResult<MdblistRawPage>> _fetchRawPage(
    String path, {
    Map<String, Object?> query = const {},
  }) async {
    final response = await _trackerRequest('GET', path, query: query);
    if (!response.isSuccess) {
      return MdblistResult.failure(
        response.kind,
        statusCode: response.statusCode,
        retryAfter: response.retryAfter,
        headers: response.headers,
      );
    }
    final decoded = response.data;
    final items = <Map<String, dynamic>>[];
    String? nextCursor;
    MdblistCatalogQuota? quota;
    if (decoded is List) {
      for (final value in decoded) {
        if (value is! Map) {
          return const MdblistResult.failure(
            MdblistResultKind.malformedResponse,
          );
        }
        items.add(Map<String, dynamic>.from(value));
      }
    } else if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      var foundBucket = false;
      for (final key in const ['items', 'movies', 'shows']) {
        final values = map[key];
        if (values == null) continue;
        if (values is! List) {
          return const MdblistResult.failure(
            MdblistResultKind.malformedResponse,
          );
        }
        foundBucket = true;
        for (final value in values) {
          if (value is! Map) {
            return const MdblistResult.failure(
              MdblistResultKind.malformedResponse,
            );
          }
          items.add(Map<String, dynamic>.from(value));
        }
      }
      if (!foundBucket && map.isNotEmpty) {
        return const MdblistResult.failure(MdblistResultKind.malformedResponse);
      }
      final pagination = map['pagination'];
      if (pagination is Map) {
        final rawCursor = pagination['next_cursor']?.toString().trim();
        if (rawCursor != null && rawCursor.isNotEmpty) nextCursor = rawCursor;
      }
      final rawQuota = map['quota'];
      if (rawQuota is Map) {
        quota = MdblistCatalogQuota.fromJson(
          Map<String, dynamic>.from(rawQuota),
        );
      }
    } else {
      return const MdblistResult.failure(MdblistResultKind.malformedResponse);
    }
    final headerCursor = response.headers?['x-next-cursor']?.trim();
    if (nextCursor == null && headerCursor != null && headerCursor.isNotEmpty) {
      nextCursor = headerCursor;
    }
    return MdblistResult.success(
      MdblistRawPage(items: items, nextCursor: nextCursor, quota: quota),
      statusCode: response.statusCode,
      headers: response.headers,
    );
  }

  /// Fetches a list's items via `GET /lists/{id}/items`, following pagination.
  ///
  /// The API returns `{ "movies": [...], "shows": [...] }` a page at a time
  /// (default 1000 items) and sets an `X-Has-More: true` header while more
  /// remain, so this walks pages by `offset` (advancing by the item count each
  /// page — confirmed standard offset paging) until the header is false,
  /// accumulating into one merged map. Lists ≤1000 items resolve in a single
  /// request. Returns null on a first-page failure so callers can tell error
  /// from an empty list; a *later*-page failure returns whatever loaded so far
  /// (and is not cached, so it retries).
  Future<MdblistResult<Map<String, dynamic>>> fetchListItemsResult(
    int listId, {
    bool forceRefresh = false,
  }) async {
    final capability = await _captureCapability();
    if (!forceRefresh) {
      final cached = _itemsCache[listId];
      if (cached != null && _fresh(cached.at)) {
        await capability?.runIfCurrent(() async {});
        return MdblistResult.success(cached.data);
      }
    }

    final movies = <dynamic>[];
    final shows = <dynamic>[];
    String? cursor;
    var fallbackOffset = 0;
    var fetchedAny = false;
    // Cache ONLY a cleanly-finished walk (X-Has-More went false). A mid-way
    // failure or a maxPages cutoff leaves this false so the partial isn't cached
    // and the next visit retries.
    var complete = false;
    // Safety backstop against a server that never clears X-Has-More:
    // 1000/page × 25 = 25k items, far beyond any real MDBList list.
    const maxPages = 25;

    MdblistResult<dynamic>? lastFailure;
    for (var page = 0; page < maxPages; page++) {
      final response = await _transport.request(
        'GET',
        '/lists/$listId/items',
        query: {
          'limit': 1000,
          if (cursor != null) 'cursor': cursor,
          if (cursor == null && fallbackOffset > 0) 'offset': fallbackOffset,
        },
        capability: capability,
      );
      if (!response.isSuccess) {
        lastFailure = response;
        break;
      }
      final decoded = response.data;
      List<dynamic> pageMovies = const [];
      List<dynamic> pageShows = const [];
      if (decoded is Map<String, dynamic>) {
        final mv = decoded['movies'];
        final sh = decoded['shows'];
        if (mv is List) pageMovies = mv;
        if (sh is List) pageShows = sh;
      } else if (decoded is List) {
        // Defensive: a flat array shape — treat as movies.
        pageMovies = decoded;
      } else {
        lastFailure = const MdblistResult.failure(
          MdblistResultKind.malformedResponse,
        );
        break;
      }
      movies.addAll(pageMovies);
      shows.addAll(pageShows);
      fetchedAny = true;
      final got = pageMovies.length + pageShows.length;
      final pagination = decoded is Map<String, dynamic>
          ? decoded['pagination']
          : null;
      final next = pagination is Map
          ? pagination['next_cursor']?.toString().trim()
          : null;
      if (next != null && next.isNotEmpty) {
        cursor = next;
        continue;
      }
      // Old servers may omit pagination but still return a full page. Use a
      // bounded offset fallback only in that compatibility case.
      if (got >= 1000) {
        fallbackOffset += got;
        cursor = null;
        continue;
      }
      if (got == 0 || next == null || next.isEmpty) {
        complete = true;
        break;
      }
    }

    if (!fetchedAny) {
      return MdblistResult.failure(
        lastFailure?.kind ?? MdblistResultKind.transientFailure,
        statusCode: lastFailure?.statusCode,
        retryAfter: lastFailure?.retryAfter,
      );
    }

    // 'complete' flags a fully-walked list (X-Has-More reached false). A partial
    // read (a mid-pagination page failed) returns non-null so the display path
    // can still show what loaded, but [saveListAsClone] must NOT clone a partial.
    final data = <String, dynamic>{
      'movies': movies,
      'shows': shows,
      'complete': complete,
    };
    await capability?.runIfCurrent(() async {});
    if (complete) {
      _itemsCache[listId] = (data: data, at: DateTime.now());
    }
    return complete
        ? MdblistResult.success(data)
        : MdblistResult.partial(data, statusCode: lastFailure?.statusCode);
  }

  Future<Map<String, dynamic>?> fetchListItems(
    int listId, {
    bool forceRefresh = false,
  }) async =>
      (await fetchListItemsResult(listId, forceRefresh: forceRefresh)).data;

  Future<bool> likeList(int listId) => _setListLike(listId, true);

  Future<bool> unlikeList(int listId) => _setListLike(listId, false);

  Future<bool> _setListLike(int listId, bool liked) async {
    final capability = await _captureCapability();
    final response = await _transport.request(
      liked ? 'PUT' : 'DELETE',
      '/lists/$listId/like',
      capability: capability,
      allowNotFound: !liked,
    );
    final success =
        response.isSuccess ||
        (!liked && response.kind == MdblistResultKind.notFound) ||
        (liked && response.kind == MdblistResultKind.conflict);
    if (success) {
      await capability?.runIfCurrent(() async {});
      _likedListsCache = null;
      _likedListsAt = null;
      _topListsCache = null;
      _topListsAt = null;
    }
    return success;
  }

  // ── Tracker API ───────────────────────────────────────────────────────────

  Future<MdblistResult<dynamic>> _trackerRequest(
    String method,
    String path, {
    Map<String, Object?> query = const {},
    Object? body,
    ProfileAsyncAuthorization? capability,
  }) async {
    capability ??= await _captureCapability();
    return _transport.request(
      method,
      path,
      query: query,
      body: body,
      capability: capability,
    );
  }

  Future<MdblistResult<Map<String, dynamic>>> _mapRequest(
    String method,
    String path, {
    Map<String, Object?> query = const {},
    Object? body,
    ProfileAsyncAuthorization? capability,
  }) async {
    final response = await _trackerRequest(
      method,
      path,
      query: query,
      body: body,
      capability: capability,
    );
    if (!response.isSuccess) {
      return MdblistResult.failure(
        response.kind,
        statusCode: response.statusCode,
        retryAfter: response.retryAfter,
        headers: response.headers,
      );
    }
    if (response.data is! Map<String, dynamic>) {
      return const MdblistResult.failure(MdblistResultKind.malformedResponse);
    }
    return MdblistResult.success(
      response.data! as Map<String, dynamic>,
      statusCode: response.statusCode,
      headers: response.headers,
    );
  }

  Future<MdblistResult<List<Map<String, dynamic>>>> _listRequest(
    String path, {
    Map<String, Object?> query = const {},
  }) async {
    final response = await _trackerRequest('GET', path, query: query);
    if (!response.isSuccess) {
      return MdblistResult.failure(
        response.kind,
        statusCode: response.statusCode,
        retryAfter: response.retryAfter,
        headers: response.headers,
      );
    }
    final raw = response.data;
    if (raw is! List) {
      return const MdblistResult.failure(MdblistResultKind.malformedResponse);
    }
    final result = <Map<String, dynamic>>[];
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) {
        return const MdblistResult.failure(MdblistResultKind.malformedResponse);
      }
      result.add(entry);
    }
    return MdblistResult.success(
      result,
      statusCode: response.statusCode,
      headers: response.headers,
    );
  }

  Future<MdblistResult<Map<String, dynamic>>> scrobbleStart(
    MdblistScrobbleTarget target,
    double progress, {
    ProfileAsyncAuthorization? capability,
  }) => _scrobble('start', target, progress, capability: capability);

  Future<MdblistResult<Map<String, dynamic>>> scrobblePause(
    MdblistScrobbleTarget target,
    double progress, {
    ProfileAsyncAuthorization? capability,
  }) => _scrobble('pause', target, progress, capability: capability);

  Future<MdblistResult<Map<String, dynamic>>> scrobbleStop(
    MdblistScrobbleTarget target,
    double progress, {
    ProfileAsyncAuthorization? capability,
  }) => _scrobble('stop', target, progress, capability: capability);

  Future<MdblistResult<Map<String, dynamic>>> scrobbleClear(
    MdblistScrobbleTarget target, {
    ProfileAsyncAuthorization? capability,
  }) => _scrobble('clear', target, 0, capability: capability);

  Future<MdblistResult<Map<String, dynamic>>> _scrobble(
    String action,
    MdblistScrobbleTarget target,
    double progress, {
    ProfileAsyncAuthorization? capability,
  }) async {
    final payload = target.payload(progress);
    if (payload == null) {
      return const MdblistResult.failure(MdblistResultKind.malformedResponse);
    }
    final result = await _mapRequest(
      'POST',
      '/scrobble/$action',
      body: payload,
      capability: capability,
    );
    if (result.isSuccess) {
      if (target.isEpisode) {
        EpisodeTrackerSnapshotRevision.invalidateTitle(
          'mdblist',
          target.ids.imdb,
        );
      }
      playbackRevision.value++;
      libraryRevision.value++;
      if (action == 'stop') watchedRevision.value++;
    }
    return result;
  }

  Future<MdblistResult<List<MdblistPlaybackSession>>>
  fetchPlaybackSessions() async {
    final response = await _listRequest('/sync/playback');
    if (!response.isSuccess) {
      return MdblistResult.failure(
        response.kind,
        statusCode: response.statusCode,
        retryAfter: response.retryAfter,
      );
    }
    try {
      return MdblistResult.success([
        for (final row in response.data!) MdblistPlaybackSession.fromJson(row),
      ]);
    } catch (_) {
      return const MdblistResult.failure(MdblistResultKind.malformedResponse);
    }
  }

  Future<MdblistResult<List<Map<String, dynamic>>>> fetchNowPlaying() =>
      _listRequest('/sync/now-playing');

  Future<MdblistResult<List<Map<String, dynamic>>>> fetchUpNext({
    bool watchlist = false,
    bool upcoming = false,
  }) async {
    assert(!(watchlist && upcoming));
    final path = watchlist
        ? '/upnext/watchlist'
        : upcoming
        ? '/upnext/upcoming'
        : '/upnext';
    final items = <Map<String, dynamic>>[];
    var offset = 0;
    for (var page = 0; page < 100; page++) {
      final response = await _mapRequest(
        'GET',
        path,
        query: {'limit': 100, 'offset': offset},
      );
      if (!response.isSuccess) {
        return items.isEmpty
            ? MdblistResult.failure(
                response.kind,
                statusCode: response.statusCode,
                retryAfter: response.retryAfter,
              )
            : MdblistResult.partial(items, statusCode: response.statusCode);
      }
      final pageItems = response.data?['items'];
      if (pageItems is! List) {
        return const MdblistResult.failure(MdblistResultKind.malformedResponse);
      }
      for (final row in pageItems) {
        if (row is! Map<String, dynamic>) {
          return const MdblistResult.failure(
            MdblistResultKind.malformedResponse,
          );
        }
        items.add(row);
      }
      if (response.data?['has_more'] != true) {
        return MdblistResult.success(items);
      }
      offset += pageItems.length;
      if (pageItems.isEmpty) break;
    }
    return MdblistResult.partial(items);
  }

  Map<String, dynamic>? _singleTitlePayload(
    MdblistMediaIds ids,
    String type, {
    int? season,
    int? episode,
    int? rating,
    String? timestampField,
  }) {
    if (ids.isEmpty) return null;
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final attributes = <String, dynamic>{
      if (rating != null) 'rating': rating,
      if (timestampField != null) timestampField: timestamp,
    };
    if (type == 'episode') {
      if (season == null || episode == null) return null;
      return {
        'shows': [
          {
            'ids': ids.toJson(),
            'seasons': [
              {
                'number': season,
                'episodes': [
                  {'number': episode, ...attributes},
                ],
              },
            ],
          },
        ],
      };
    }
    final bucket = type == 'series' || type == 'show' ? 'shows' : 'movies';
    return {
      bucket: [
        {'ids': ids.toJson(), ...attributes},
      ],
    };
  }

  Future<bool> _mutateTitle(
    String path,
    MdblistMediaIds ids,
    String type, {
    int? season,
    int? episode,
    int? rating,
    String? timestampField,
  }) async {
    final payload = _singleTitlePayload(
      ids,
      type,
      season: season,
      episode: episode,
      rating: rating,
      timestampField: timestampField,
    );
    if (payload == null) return false;
    final response = await _trackerRequest('POST', path, body: payload);
    final success = response.isSuccess;
    if (success &&
        (type == 'episode' || type == 'series' || type == 'show') &&
        (path == '/sync/watched' || path == '/sync/watched/remove')) {
      EpisodeTrackerSnapshotRevision.invalidateTitle('mdblist', ids.imdb);
    }
    if (success) {
      libraryRevision.value++;
      if (path == '/sync/watched' || path == '/sync/watched/remove') {
        watchedRevision.value++;
      }
    }
    return success;
  }

  Future<bool> addToWatchlist(MdblistMediaIds ids, String type) =>
      _mutateTitle('/watchlist/items/add', ids, type);
  Future<bool> removeFromWatchlist(MdblistMediaIds ids, String type) =>
      _mutateTitle('/watchlist/items/remove', ids, type);
  Future<bool> markWatched(
    MdblistMediaIds ids,
    String type, {
    int? season,
    int? episode,
  }) => _mutateTitle(
    '/sync/watched',
    ids,
    type,
    season: season,
    episode: episode,
    timestampField: 'watched_at',
  );
  Future<bool> markUnwatched(
    MdblistMediaIds ids,
    String type, {
    int? season,
    int? episode,
  }) => _mutateTitle(
    '/sync/watched/remove',
    ids,
    type,
    season: season,
    episode: episode,
  );
  Future<bool> rateTitle(
    MdblistMediaIds ids,
    String type,
    int rating, {
    int? season,
    int? episode,
  }) {
    if (rating < 1 || rating > 10) return Future.value(false);
    return _mutateTitle(
      '/sync/ratings',
      ids,
      type,
      season: season,
      episode: episode,
      rating: rating,
      timestampField: 'rated_at',
    );
  }

  Future<bool> removeRating(
    MdblistMediaIds ids,
    String type, {
    int? season,
    int? episode,
  }) => _mutateTitle(
    '/sync/ratings/remove',
    ids,
    type,
    season: season,
    episode: episode,
  );
  Future<bool> addToCollection(MdblistMediaIds ids, String type) =>
      _mutateTitle(
        '/sync/collection',
        ids,
        type,
        timestampField: 'collected_at',
      );
  Future<bool> removeFromCollection(MdblistMediaIds ids, String type) =>
      _mutateTitle('/sync/collection/remove', ids, type);
  Future<bool> setDropped(MdblistMediaIds ids, {required bool dropped}) =>
      _setDropped(ids, dropped: dropped);

  Future<bool> _setDropped(MdblistMediaIds ids, {required bool dropped}) async {
    final success = await _mutateTitle(
      dropped ? '/sync/dropped' : '/sync/dropped/remove',
      ids,
      'show',
      timestampField: dropped ? 'dropped_at' : null,
    );
    if (!success) return false;
    final imdb = ids.imdb?.toLowerCase();
    if (imdb != null && _droppedImdbCache != null) {
      dropped ? _droppedImdbCache!.add(imdb) : _droppedImdbCache!.remove(imdb);
      _droppedImdbAt = DateTime.now();
    } else {
      _droppedImdbCache = null;
      _droppedImdbAt = null;
    }
    return true;
  }

  Future<bool> setSeasonDropped(
    MdblistMediaIds ids,
    int season, {
    required bool dropped,
  }) async {
    if (ids.isEmpty || season < 0) return false;
    final row = <String, dynamic>{'number': season};
    if (dropped) {
      row['dropped_at'] = DateTime.now().toUtc().toIso8601String();
    }
    final response = await _trackerRequest(
      'POST',
      dropped ? '/sync/seasons/dropped' : '/sync/seasons/dropped/remove',
      body: {
        'shows': [
          {
            'ids': ids.toJson(),
            'seasons': [row],
          },
        ],
      },
    );
    return response.isSuccess;
  }

  Future<MdblistResult<List<Map<String, dynamic>>>> fetchWatchlist() async {
    final rows = <Map<String, dynamic>>[];
    final seenCursors = <String>{};
    String? cursor;
    var offset = 0;
    for (var page = 0; page < 100; page++) {
      final response = await _mapRequest(
        'GET',
        '/watchlist/items',
        query: {
          'limit': 1000,
          if (cursor != null) 'cursor': cursor,
          if (cursor == null && offset > 0) 'offset': offset,
          'append_to_response': 'poster,ratings,description,genres',
        },
      );
      if (!response.isSuccess) {
        return rows.isEmpty
            ? MdblistResult.failure(
                response.kind,
                statusCode: response.statusCode,
                retryAfter: response.retryAfter,
                headers: response.headers,
              )
            : MdblistResult.partial(
                rows,
                statusCode: response.statusCode,
                headers: response.headers,
              );
      }
      var pageRows = 0;
      for (final bucket in ['movies', 'shows']) {
        final values = response.data?[bucket];
        if (values is! List) continue;
        for (final value in values) {
          if (value is Map<String, dynamic>) {
            rows.add(value);
            pageRows++;
          }
        }
      }
      final pagination = response.data?['pagination'];
      final bodyCursor = pagination is Map
          ? pagination['next_cursor']?.toString().trim()
          : null;
      final headerCursor = response.headers?['x-next-cursor']?.trim();
      final next = bodyCursor?.isNotEmpty == true
          ? bodyCursor
          : headerCursor?.isNotEmpty == true
          ? headerCursor
          : null;
      if (next != null) {
        if (!seenCursors.add(next)) {
          return MdblistResult.partial(
            rows,
            statusCode: response.statusCode,
            headers: response.headers,
          );
        }
        cursor = next;
        continue;
      }
      final bodyHasMore =
          pagination is Map &&
          (pagination['has_more'] == true ||
              pagination['has_more']?.toString().toLowerCase() == 'true');
      final headerHasMore =
          response.headers?['x-has-more']?.toLowerCase() == 'true';
      if (!bodyHasMore && !headerHasMore) {
        return MdblistResult.success(rows);
      }
      if (pageRows == 0) return MdblistResult.partial(rows);
      offset += pageRows;
      cursor = null;
    }
    return MdblistResult.partial(rows);
  }

  Future<MdblistResult<Map<Object, MdblistTitleStatus>>> fetchTitleStates({
    required String mediaType,
    required String provider,
    required List<Object> ids,
  }) async {
    if (ids.length > 100 || ids.isEmpty) {
      return const MdblistResult.failure(MdblistResultKind.malformedResponse);
    }
    final response = await _mapRequest(
      'POST',
      '/sync/state/$mediaType/$provider',
      body: {'ids': ids},
    );
    if (!response.isSuccess) {
      return MdblistResult.failure(
        response.kind,
        statusCode: response.statusCode,
        retryAfter: response.retryAfter,
      );
    }
    final items = response.data?['items'];
    if (items is! List) {
      return const MdblistResult.failure(MdblistResultKind.malformedResponse);
    }
    final statuses = <Object, MdblistTitleStatus>{};
    for (final item in items) {
      if (item is! Map<String, dynamic> || item['id'] == null) continue;
      final status = MdblistTitleStatus.fromJson(item);
      statuses[status.id] = status;
    }
    return MdblistResult.success(statuses);
  }

  Future<MdblistResult<Map<String, dynamic>>> resolveImdb(
    String imdbId,
    String type,
  ) => _mapRequest('GET', '/imdb/${type == 'series' ? 'show' : type}/$imdbId/');

  Future<MdblistResult<Map<String, dynamic>>> resolveTmdb(
    int tmdbId,
    String type,
  ) => _mapRequest('GET', '/tmdb/${type == 'series' ? 'show' : type}/$tmdbId/');

  Future<MdblistTitleStatus?> fetchTitleStatus(
    String imdbId,
    String type,
  ) async {
    final resolved = await resolveImdb(imdbId, type);
    if (!resolved.isSuccess) return null;
    final ids = resolved.data?['ids'];
    final rawTmdb = ids is Map ? ids['tmdb'] : null;
    final tmdb = rawTmdb is num
        ? rawTmdb.toInt()
        : int.tryParse(rawTmdb?.toString() ?? '');
    if (tmdb == null) return null;
    final isSeries = type == 'series';
    final reads = await Future.wait<Object?>([
      fetchTitleStates(
        mediaType: isSeries ? 'show' : 'movie',
        provider: 'tmdb',
        ids: [tmdb],
      ),
      if (isSeries) _fetchDroppedImdbIds() else Future.value(null),
    ]);
    final states = reads[0] as MdblistResult<Map<Object, MdblistTitleStatus>>;
    if (!states.isSuccess || states.data!.isEmpty) return null;
    final status =
        states.data![tmdb] ??
        states.data![tmdb.toString()] ??
        states.data!.values.first;
    final droppedIds = reads[1] as Set<String>?;
    return status.copyWith(
      dropped: isSeries
          ? droppedIds?.contains(imdbId.toLowerCase())
          : status.dropped,
    );
  }

  Future<Set<String>?> _fetchDroppedImdbIds() async {
    if (_droppedImdbCache != null && _fresh(_droppedImdbAt)) {
      return Set.of(_droppedImdbCache!);
    }
    final existing = _droppedImdbInFlight;
    if (existing != null) return existing;
    final future = () async {
      final result = await fetchSyncSnapshot('dropped');
      if (!result.isSuccess) return null;
      final ids = <String>{};
      for (final row in result.data!) {
        final show = row['show'];
        final rawIds = show is Map ? show['ids'] : row['ids'];
        if (rawIds is! Map) continue;
        final imdb = rawIds['imdb']?.toString().trim().toLowerCase();
        if (imdb != null && imdb.isNotEmpty) ids.add(imdb);
      }
      _droppedImdbCache = ids;
      _droppedImdbAt = DateTime.now();
      return Set.of(ids);
    }();
    _droppedImdbInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_droppedImdbInFlight, future)) {
        _droppedImdbInFlight = null;
      }
    }
  }

  Future<MdblistResult<Map<String, double>>> fetchShowEpisodeProgress(
    String imdbId,
  ) async {
    final reads = await Future.wait([
      resolveImdb(imdbId, 'series'),
      fetchPlaybackSessions(),
    ]);
    final resolved = reads[0] as MdblistResult<Map<String, dynamic>>;
    final playback = reads[1] as MdblistResult<List<MdblistPlaybackSession>>;
    final merged = <String, double>{};
    if (playback.isUsable) {
      for (final session in playback.data!) {
        if (!session.isEpisode ||
            session.imdbId?.toLowerCase() != imdbId.toLowerCase() ||
            session.season == null ||
            session.episode == null ||
            !session.isResumable) {
          continue;
        }
        merged['${session.season}-${session.episode}'] = session.progress;
      }
    }
    if (!resolved.isSuccess) {
      return playback.isUsable
          ? MdblistResult.partial(merged)
          : const MdblistResult.failure(MdblistResultKind.transientFailure);
    }
    final ids = resolved.data?['ids'];
    final rawTmdb = ids is Map ? ids['tmdb'] : null;
    final tmdb = rawTmdb is num
        ? rawTmdb.toInt()
        : int.tryParse(rawTmdb?.toString() ?? '');
    if (tmdb == null) return MdblistResult.partial(merged);
    final history = await _mapRequest('GET', '/sync/history/show/tmdb/$tmdb');
    if (!history.isSuccess) return MdblistResult.partial(merged);
    final plays = history.data?['plays'];
    if (plays is! List) {
      return const MdblistResult.failure(MdblistResultKind.malformedResponse);
    }
    for (final play in plays.whereType<Map<String, dynamic>>()) {
      final season = play['season_num'];
      final episode = play['episode_num'];
      if (season is num && episode is num) {
        merged['${season.toInt()}-${episode.toInt()}'] = 100;
      }
    }
    if (!playback.isSuccess) return MdblistResult.partial(merged);
    return history.data?['truncated'] == true
        ? MdblistResult.partial(merged)
        : MdblistResult.success(merged);
  }

  /// Returns the authenticated user's episode ratings for one show, keyed as
  /// `season-episode`. The sync API has emitted both flattened episode rows
  /// and nested show/season payloads over its lifetime, so accept both shapes
  /// while still requiring the parent IMDb id to match.
  Future<MdblistResult<Map<String, int>>> fetchShowEpisodeRatings(
    String imdbId,
  ) async {
    final snapshot = await fetchSyncSnapshot('ratings', mediaType: 'episode');
    if (!snapshot.isUsable) {
      return MdblistResult.failure(
        snapshot.kind,
        statusCode: snapshot.statusCode,
        retryAfter: snapshot.retryAfter,
      );
    }

    final wanted = imdbId.trim().toLowerCase();
    final ratings = <String, int>{};

    int? integer(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    String? parentImdb(Map<dynamic, dynamic> row) {
      final show = row['show'];
      final candidates = <dynamic>[
        if (show is Map) show['ids'],
        row['show_ids'],
        row['ids'],
      ];
      for (final candidate in candidates) {
        if (candidate is Map) {
          final imdb = candidate['imdb']?.toString().trim().toLowerCase();
          if (imdb != null && imdb.isNotEmpty) return imdb;
        }
      }
      return null;
    }

    void addEpisode(Map<dynamic, dynamic> row, int? inheritedSeason) {
      final episodeValue = row['episode'];
      final episodeMap = episodeValue is Map ? episodeValue : null;
      final season =
          integer(
            row['season'] is Map ? row['season']['number'] : row['season'],
          ) ??
          integer(row['season_num']) ??
          inheritedSeason;
      final episode =
          integer(episodeMap?['number']) ??
          integer(episodeValue) ??
          integer(row['episode_num']) ??
          integer(row['number']);
      final rating = integer(row['rating']) ?? integer(episodeMap?['rating']);
      if (season != null &&
          episode != null &&
          rating != null &&
          rating >= 1 &&
          rating <= 10) {
        ratings['$season-$episode'] = rating;
      }
    }

    void addNested(Map<dynamic, dynamic> row) {
      final show = row['show'];
      final owner = show is Map ? show : row;
      if (parentImdb(row) != wanted && parentImdb(owner) != wanted) return;
      final seasons = owner['seasons'];
      if (seasons is List) {
        for (final seasonValue in seasons.whereType<Map>()) {
          final season = integer(seasonValue['number']);
          final episodes = seasonValue['episodes'];
          if (episodes is List) {
            for (final episodeValue in episodes.whereType<Map>()) {
              addEpisode(episodeValue, season);
            }
          }
        }
        return;
      }
      addEpisode(row, null);
    }

    for (final row in snapshot.data!) {
      addNested(row);
    }
    return snapshot.kind == MdblistResultKind.partial
        ? MdblistResult.partial(ratings)
        : MdblistResult.success(ratings);
  }

  Future<MdblistResult<Map<String, dynamic>>> fetchLastActivities() =>
      _mapRequest('GET', '/sync/last_activities');

  Future<MdblistResult<Map<String, dynamic>>> fetchJournal({
    DateTime? since,
    String? cursor,
    int limit = 1000,
  }) => _mapRequest(
    'GET',
    '/sync/journal',
    query: {
      if (cursor != null) 'cursor': cursor,
      if (cursor == null && since != null)
        'since': since.toUtc().toIso8601String(),
      'limit': limit.clamp(1, 1000),
    },
  );

  Future<MdblistResult<List<Map<String, dynamic>>>> fetchSyncSnapshot(
    String bucket, {
    String? mediaType,
    DateTime? since,
  }) async {
    if (!const {
      'watched',
      'ratings',
      'collection',
      'dropped',
    }.contains(bucket)) {
      return const MdblistResult.failure(MdblistResultKind.malformedResponse);
    }
    final rows = <Map<String, dynamic>>[];
    String? cursor;
    const maxPages = 100;
    for (var page = 0; page < maxPages; page++) {
      final response = await _trackerRequest(
        'GET',
        '/sync/$bucket',
        query: {
          'limit': 1000,
          if (cursor != null) 'cursor': cursor,
          if (cursor == null && since != null)
            'since': since.toUtc().toIso8601String(),
          if (mediaType != null) 'mediatype': mediaType,
        },
      );
      if (!response.isSuccess) {
        if (rows.isNotEmpty) return MdblistResult.partial(rows);
        return MdblistResult.failure(
          response.kind,
          statusCode: response.statusCode,
          retryAfter: response.retryAfter,
        );
      }
      final data = response.data;
      if (data is List) {
        for (final row in data) {
          if (row is Map<String, dynamic>) rows.add(row);
        }
        return MdblistResult.success(rows);
      }
      if (data is! Map<String, dynamic>) {
        return rows.isEmpty
            ? const MdblistResult.failure(MdblistResultKind.malformedResponse)
            : MdblistResult.partial(rows);
      }
      for (final key in ['movies', 'shows', 'seasons', 'episodes', 'items']) {
        final values = data[key];
        if (values is List) {
          for (final row in values) {
            if (row is Map<String, dynamic>) rows.add(row);
          }
        }
      }
      final pagination = data['pagination'];
      final next = pagination is Map
          ? pagination['next_cursor']?.toString().trim()
          : null;
      if (next == null || next.isEmpty) {
        return MdblistResult.success(rows);
      }
      cursor = next;
    }
    // A pathological cursor loop/max-page walk is useful but never complete.
    return MdblistResult.partial(rows);
  }

  Future<MdblistResult<List<Map<String, dynamic>>>> fetchCalendarEvents({
    required DateTime start,
    required DateTime end,
  }) async {
    final response = await _mapRequest(
      'GET',
      '/calendar/events',
      query: {
        'start': start.toIso8601String().split('T').first,
        'end': end.toIso8601String().split('T').first,
        'limit': 1000,
        'favorite_cast': false,
        'append_to_response': 'description',
      },
    );
    if (!response.isSuccess) {
      return MdblistResult.failure(
        response.kind,
        statusCode: response.statusCode,
        retryAfter: response.retryAfter,
      );
    }
    final values = response.data?['events'];
    if (values is! List) {
      return const MdblistResult.failure(MdblistResultKind.malformedResponse);
    }
    return MdblistResult.success(
      values.whereType<Map<String, dynamic>>().toList(),
    );
  }

  Future<({Set<String> movies, Set<String> series})?>
  fetchCompletedTitleIds() async {
    if (!networkEnabled) return (movies: <String>{}, series: <String>{});
    if (!await isAuthenticated()) {
      return (movies: <String>{}, series: <String>{});
    }
    final results = await Future.wait([
      fetchSyncSnapshot('watched', mediaType: 'movie'),
      fetchSyncSnapshot('watched', mediaType: 'show'),
      fetchSyncSnapshot('watched', mediaType: 'episode'),
    ]);
    if (results.any((result) => !result.isSuccess)) return null;
    String? imdbOf(Map<String, dynamic> row) {
      final container = row['movie'] ?? row['show'];
      final ids = container is Map ? container['ids'] : row['ids'];
      final id = ids is Map
          ? ids['imdb']?.toString()
          : row['imdb_id']?.toString();
      return id?.trim().toLowerCase();
    }

    final movies = <String>{};
    for (final row in results[0].data!) {
      final id = imdbOf(row);
      if (id != null && id.isNotEmpty) movies.add(id);
    }
    // `/sync/watched` does not include the computed `completed` field; that
    // belongs to `/sync/state/show/{provider}`. More importantly, a show
    // completed episode-by-episode may exist only in the episode snapshot, not
    // as a whole-show watched row. Use parent show IDs from both snapshots as
    // candidates, then batch their authoritative state 100 at a time.
    final imdbByMdblistId = <String, String>{};
    void addShowCandidate(Map<String, dynamic> row) {
      final episode = row['episode'];
      final nestedShow = episode is Map ? episode['show'] : null;
      final show = nestedShow is Map ? nestedShow : row['show'];
      final ids = show is Map ? show['ids'] : row['ids'];
      final mdblistId = ids is Map ? ids['mdblist']?.toString().trim() : null;
      final imdb = ids is Map
          ? ids['imdb']?.toString().trim().toLowerCase()
          : null;
      if (mdblistId != null &&
          mdblistId.isNotEmpty &&
          imdb != null &&
          imdb.isNotEmpty) {
        imdbByMdblistId[mdblistId] = imdb;
      }
    }

    for (final row in results[1].data!) {
      addShowCandidate(row);
    }
    for (final row in results[2].data!) {
      addShowCandidate(row);
    }

    final series = <String>{};
    final mdblistIds = imdbByMdblistId.keys.toList(growable: false);
    for (var offset = 0; offset < mdblistIds.length; offset += 100) {
      final end = (offset + 100).clamp(0, mdblistIds.length);
      final batch = mdblistIds.sublist(offset, end);
      final states = await fetchTitleStates(
        mediaType: 'show',
        provider: 'mdblist',
        ids: batch,
      );
      // Never publish a partial/empty replacement after a failed batch. The
      // caller preserves its previous authoritative snapshot when null.
      if (!states.isSuccess) return null;
      for (final entry in states.data!.entries) {
        if (entry.value.completed != true) continue;
        final imdb = imdbByMdblistId[entry.key.toString()];
        if (imdb != null) series.add(imdb);
      }
    }
    return (movies: movies, series: series);
  }

  // ── Explicit static-list cloning ───────────────────────────────────────────
  // Public-list Save uses the real like API. Cloning remains a separately
  // labelled operation for users who want an editable point-in-time copy.

  /// Create an empty static list on the user's account. Returns the new list id
  /// (or null on failure).
  Future<int?> createList(
    String name, {
    bool private = false,
    ProfileAsyncAuthorization? capability,
  }) async {
    capability ??= await _captureCapability();
    final response = await _transport.request(
      'POST',
      '/lists/user/add',
      body: {'name': name, 'private': private},
      capability: capability,
    );
    if (!response.isSuccess) return null;
    try {
      final decoded = response.data;
      final obj = decoded is List && decoded.isNotEmpty
          ? decoded.first
          : decoded;
      final id = obj is Map ? obj['id'] : null;
      await capability?.runIfCurrent(() async {});
      return id is int ? id : (id is num ? id.toInt() : null);
    } catch (_) {
      return null;
    }
  }

  /// Add items to a static list. [movies]/[shows] are `{tmdb, imdb}` maps.
  Future<bool> addItemsToList(
    int listId, {
    required List<Map<String, dynamic>> movies,
    required List<Map<String, dynamic>> shows,
    ProfileAsyncAuthorization? capability,
  }) async {
    capability ??= await _captureCapability();
    if (movies.isEmpty && shows.isEmpty) return true;
    final response = await _transport.request(
      'POST',
      '/lists/$listId/items/add',
      body: {'movies': movies, 'shows': shows},
      capability: capability,
    );
    return response.isSuccess;
  }

  /// Delete one of the user's static lists. Treats "already gone" (404) and a
  /// bodyless success (204) as success too, so a clone deleted out-of-band (on
  /// the MDBList website) still lets the app clear its saved-state rather than
  /// getting stuck showing "Saved".
  Future<bool> deleteList(
    int listId, {
    ProfileAsyncAuthorization? capability,
  }) async {
    capability ??= await _captureCapability();
    final response = await _transport.request(
      'DELETE',
      '/lists/$listId',
      capability: capability,
      allowNotFound: true,
    );
    return response.isSuccess || response.kind == MdblistResultKind.notFound;
  }

  Future<bool> deleteSavedClone({
    required int sourceListId,
    required int cloneListId,
  }) async {
    final capability = await _captureCapability();
    final deleted = await deleteList(cloneListId, capability: capability);
    if (!deleted) return false;
    if (capability == null) {
      await StorageService.removeMdblistSavedClone(sourceListId);
    } else {
      await capability.runIfCurrent(
        () => StorageService.removeMdblistSavedClone(sourceListId),
      );
    }
    return true;
  }

  /// Save [sourceListId] into the user's account by cloning it: create a new
  /// static list named [name] and copy the source's items in. Returns the new
  /// list id, or null on failure (an empty list is rolled back so we don't
  /// litter "My Lists"). Snapshot only — it does NOT auto-update if the source
  /// changes. Drops the user-lists cache so "My Lists" reflects the new list.
  Future<int?> saveListAsClone({
    required int sourceListId,
    required String name,
  }) async {
    final capability = await _captureCapability();
    List<Map<String, dynamic>> extract(List<dynamic> raw) {
      final out = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final ids = item['ids'];
        final tmdb = ids is Map ? ids['tmdb'] : null;
        final imdb = (ids is Map ? ids['imdb'] : null) ?? item['imdb_id'];
        if (tmdb == null && (imdb is! String || imdb.isEmpty)) continue;
        out.add({
          if (tmdb != null) 'tmdb': tmdb,
          if (imdb is String && imdb.isNotEmpty) 'imdb': imdb,
        });
      }
      return out;
    }

    final data = await fetchListItems(sourceListId);
    // Abort on a failed OR partial read — cloning a truncated list would
    // silently save a subset. Better to fail loudly (UI shows "Couldn't save").
    if (data == null || data['complete'] != true) return null;
    await capability?.runIfCurrent(() async {});
    final movies = extract(data['movies'] as List? ?? const []);
    final shows = extract(data['shows'] as List? ?? const []);

    final newId = await createList(name, capability: capability);
    if (newId == null) return null;
    const chunkSize = 500;
    for (
      var movieAt = 0, showAt = 0;
      movieAt < movies.length || showAt < shows.length;
    ) {
      final movieEnd = (movieAt + chunkSize).clamp(0, movies.length);
      final remaining = chunkSize - (movieEnd - movieAt);
      final showEnd = (showAt + remaining).clamp(0, shows.length);
      final added = await addItemsToList(
        newId,
        movies: movies.sublist(movieAt, movieEnd),
        shows: shows.sublist(showAt, showEnd),
        capability: capability,
      );
      if (!added) {
        await deleteList(newId, capability: capability);
        return null;
      }
      movieAt = movieEnd;
      showAt = showEnd;
    }
    await capability?.runIfCurrent(() async {});
    // My Lists now has a new entry — force a refetch on next read.
    _userListsCache = null;
    _userListsAt = null;
    return newId;
  }

  /// `GET /user` validates the key (limits/user-id); `GET /lists/user` resolves
  /// the display username (from the first list's `user_name`) and the list
  /// count. Returns null if the key is rejected (non-200 on /user) or the
  /// network call throws.
  Future<MdblistAccount?> _fetchAccount(
    String key, {
    ProfileAsyncAuthorization? capability,
  }) async {
    if (!networkEnabled) return null;
    try {
      Future<http.Response> get(Uri uri) =>
          _client.get(uri).timeout(const Duration(seconds: 15));
      final userUri = _baseUri.replace(
        path: '/user',
        queryParameters: {'apikey': key},
      );
      final userRes = capability == null
          ? await get(userUri)
          : await capability.runIfCurrentAsOutbound(() => get(userUri));
      // MDBList returns 4xx for a bad key; a 200 means it was accepted.
      if (userRes.statusCode != 200) return null;

      int? userId;
      String? patronStatus;
      int apiRequests = 0;
      int apiRequestsUsed = 0;
      final u = jsonDecode(userRes.body);
      if (u is Map<String, dynamic>) {
        // MDBList can answer a rejected key with HTTP 200 + an error body
        // (e.g. {"error": "Invalid API key!"} or {"response": false}); treat
        // that as invalid rather than "connected".
        if (u['error'] != null || u['response'] == false) return null;
        userId = (u['user_id'] as num?)?.toInt();
        patronStatus = u['patron_status'] as String?;
        apiRequests = (u['api_requests'] as num?)?.toInt() ?? 0;
        apiRequestsUsed = (u['api_requests_count'] as num?)?.toInt() ?? 0;
      }

      // Resolve username + list count from the user's own lists. Non-fatal:
      // the key already validated via /user above.
      String? username;
      int listCount = 0;
      try {
        final listsUri = _baseUri.replace(
          path: '/lists/user',
          queryParameters: {'apikey': key},
        );
        final listsRes = capability == null
            ? await get(listsUri)
            : await capability.runIfCurrentAsOutbound(() => get(listsUri));
        if (listsRes.statusCode == 200) {
          final decoded = jsonDecode(listsRes.body);
          if (decoded is List) {
            listCount = decoded.length;
            for (final item in decoded) {
              if (item is Map<String, dynamic>) {
                final name = item['user_name'] as String?;
                if (name != null && name.isNotEmpty) {
                  username = name;
                  break;
                }
              }
            }
          }
        }
      } catch (_) {
        // Ignore — a valid key with zero lists (or a hiccup here) is still
        // connected; we just won't have a username/count to show.
      }

      username ??= userId != null ? 'User #$userId' : null;

      return MdblistAccount(
        userId: userId,
        username: username,
        listCount: listCount,
        patronStatus: patronStatus,
        apiRequests: apiRequests,
        apiRequestsUsed: apiRequestsUsed,
      );
    } catch (_) {
      return null;
    }
  }
}
