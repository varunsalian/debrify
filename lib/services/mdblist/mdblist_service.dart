import 'dart:convert';

import 'package:http/http.dart' as http;

import '../storage_service.dart';

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
  MdblistService._();
  static final MdblistService instance = MdblistService._();

  static const String _base = 'https://api.mdblist.com';

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
  final Map<int, ({Map<String, dynamic> data, DateTime at})> _itemsCache = {};

  bool _fresh(DateTime? at) =>
      at != null && DateTime.now().difference(at) < _cacheTtl;

  void _clearCache() {
    _userListsCache = null;
    _userListsAt = null;
    _topListsCache = null;
    _topListsAt = null;
    _itemsCache.clear();
  }

  Future<bool> isAuthenticated() async {
    final key = await StorageService.getMdblistApiKey();
    return key != null && key.isNotEmpty;
  }

  Future<String?> getUsername() => StorageService.getMdblistUsername();

  /// Validates [apiKey] against the API. On success, persists the key + the
  /// resolved username, caches the snapshot in [currentAccount], and returns
  /// it. On any failure (rejected key, network error) nothing is persisted and
  /// null is returned.
  Future<MdblistAccount?> connect(String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) return null;

    final snapshot = await _fetchAccount(key);
    if (snapshot == null) return null;

    await StorageService.saveMdblistApiKey(key);
    await StorageService.setMdblistUsername(snapshot.username);
    _clearCache();
    currentAccount = snapshot;
    return snapshot;
  }

  /// Re-fetches the account snapshot for the already-stored key (for the
  /// settings page's account card). Returns null if not connected or the fetch
  /// fails; a transient failure does NOT clear stored auth.
  Future<MdblistAccount?> refreshAccount() async {
    final key = await StorageService.getMdblistApiKey();
    if (key == null || key.isEmpty) return null;
    final snapshot = await _fetchAccount(key);
    if (snapshot != null) {
      currentAccount = snapshot;
      if (snapshot.username != null) {
        await StorageService.setMdblistUsername(snapshot.username);
      }
    }
    return snapshot;
  }

  Future<void> logout() async {
    currentAccount = null;
    _clearCache();
    await StorageService.clearMdblistAuth();
  }

  /// Fetches the authenticated user's own lists (raw JSON maps from
  /// `GET /lists/user`). Returns `[]` when not connected or on any failure —
  /// callers treat that the same as "no lists".
  Future<List<Map<String, dynamic>>> fetchUserLists() async {
    if (_userListsCache != null && _fresh(_userListsAt)) {
      return _userListsCache!;
    }
    final key = await StorageService.getMdblistApiKey();
    if (key == null || key.isEmpty) return const [];
    try {
      final res = await http
          .get(Uri.parse('$_base/lists/user?apikey=$key'))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return const [];
      final decoded = jsonDecode(res.body);
      if (decoded is List) {
        final lists = [
          for (final e in decoded)
            if (e is Map<String, dynamic>) e,
        ];
        _userListsCache = lists;
        _userListsAt = DateTime.now();
        return lists;
      }
    } catch (_) {
      // Fall through to empty — offline/parse errors read as "no lists".
    }
    return const [];
  }

  /// Fetches MDBList's top/public lists (raw JSON maps from `GET /lists/top`).
  /// Each entry is another user's public list (carries `user_name`). Returns
  /// `[]` when not connected or on any failure.
  Future<List<Map<String, dynamic>>> fetchTopLists() async {
    if (_topListsCache != null && _fresh(_topListsAt)) {
      return _topListsCache!;
    }
    final key = await StorageService.getMdblistApiKey();
    if (key == null || key.isEmpty) return const [];
    try {
      final res = await http
          .get(Uri.parse('$_base/lists/top?apikey=$key'))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return const [];
      final decoded = jsonDecode(res.body);
      if (decoded is List) {
        final lists = [
          for (final e in decoded)
            if (e is Map<String, dynamic>) e,
        ];
        _topListsCache = lists;
        _topListsAt = DateTime.now();
        return lists;
      }
    } catch (_) {
      // Fall through to empty.
    }
    return const [];
  }

  /// Searches MDBList's public lists by name (`GET /lists/search?query=`).
  /// Returns raw list maps (same shape as the other list endpoints). Not
  /// cached — every query is different. Returns `[]` when not connected, on
  /// an empty query, or on any failure.
  Future<List<Map<String, dynamic>>> searchLists(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final key = await StorageService.getMdblistApiKey();
    if (key == null || key.isEmpty) return const [];
    try {
      final res = await http
          .get(
            Uri.parse(
              '$_base/lists/search?query=${Uri.encodeQueryComponent(q)}&apikey=$key',
            ),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return const [];
      final decoded = jsonDecode(res.body);
      if (decoded is List) {
        return [
          for (final e in decoded)
            if (e is Map<String, dynamic>) e,
        ];
      }
    } catch (_) {
      // Fall through to empty.
    }
    return const [];
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
  Future<Map<String, dynamic>?> fetchListItems(
    int listId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _itemsCache[listId];
      if (cached != null && _fresh(cached.at)) return cached.data;
    }
    final key = await StorageService.getMdblistApiKey();
    if (key == null || key.isEmpty) return null;

    final movies = <dynamic>[];
    final shows = <dynamic>[];
    var offset = 0;
    var fetchedAny = false;
    // Cache ONLY a cleanly-finished walk (X-Has-More went false). A mid-way
    // failure or a maxPages cutoff leaves this false so the partial isn't cached
    // and the next visit retries.
    var complete = false;
    // Safety backstop against a server that never clears X-Has-More:
    // 1000/page × 25 = 25k items, far beyond any real MDBList list.
    const maxPages = 25;

    try {
      for (var page = 0; page < maxPages; page++) {
        final res = await http
            .get(
              Uri.parse('$_base/lists/$listId/items?apikey=$key&offset=$offset'),
            )
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) {
          if (!fetchedAny) return null; // first page failed → error
          break; // later page failed → keep partial, leave complete=false
        }
        final decoded = jsonDecode(res.body);
        List<dynamic> pageMovies = const [];
        List<dynamic> pageShows = const [];
        if (decoded is Map<String, dynamic>) {
          // A 200 can still carry an error body (bad/expired key, gone list).
          if (decoded['error'] != null || decoded['response'] == false) {
            if (!fetchedAny) return null;
            break;
          }
          final mv = decoded['movies'];
          final sh = decoded['shows'];
          if (mv is List) pageMovies = mv;
          if (sh is List) pageShows = sh;
        } else if (decoded is List) {
          // Defensive: a flat array shape — treat as movies.
          pageMovies = decoded;
        } else {
          if (!fetchedAny) return null;
          break;
        }
        movies.addAll(pageMovies);
        shows.addAll(pageShows);
        fetchedAny = true;
        final got = pageMovies.length + pageShows.length;
        final hasMore =
            (res.headers['x-has-more'] ?? '').trim().toLowerCase() == 'true';
        if (!hasMore || got == 0) {
          complete = true; // walked the whole list
          break;
        }
        offset += got;
      }
    } catch (_) {
      if (!fetchedAny) return null; // nothing loaded → error
      // else: partial — return it below but leave complete=false (not cached).
    }

    // 'complete' flags a fully-walked list (X-Has-More reached false). A partial
    // read (a mid-pagination page failed) returns non-null so the display path
    // can still show what loaded, but [saveListAsClone] must NOT clone a partial.
    final data = <String, dynamic>{
      'movies': movies,
      'shows': shows,
      'complete': complete,
    };
    if (complete) {
      _itemsCache[listId] = (data: data, at: DateTime.now());
    }
    return data;
  }

  // ── Saving lists (clone into "My Lists") ───────────────────────────────────
  // MDBList has no API to link/like a list into a user's account, so "Save"
  // creates a static list and copies the source list's items into it. See
  // [saveListAsClone].

  /// Create an empty static list on the user's account. Returns the new list id
  /// (or null on failure).
  Future<int?> createList(String name, {bool private = false}) async {
    final key = await StorageService.getMdblistApiKey();
    if (key == null || key.isEmpty) return null;
    try {
      final res = await http
          .post(
            Uri.parse('$_base/lists/user/add?apikey=$key'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'name': name, 'private': private}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 && res.statusCode != 201) return null;
      final decoded = jsonDecode(res.body);
      final obj = decoded is List && decoded.isNotEmpty
          ? decoded.first
          : decoded;
      final id = obj is Map ? obj['id'] : null;
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
  }) async {
    if (movies.isEmpty && shows.isEmpty) return true;
    final key = await StorageService.getMdblistApiKey();
    if (key == null || key.isEmpty) return false;
    try {
      final res = await http
          .post(
            Uri.parse('$_base/lists/$listId/items/add?apikey=$key'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'movies': movies, 'shows': shows}),
          )
          .timeout(const Duration(seconds: 30));
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// Delete one of the user's static lists. Treats "already gone" (404) and a
  /// bodyless success (204) as success too, so a clone deleted out-of-band (on
  /// the MDBList website) still lets the app clear its saved-state rather than
  /// getting stuck showing "Saved".
  Future<bool> deleteList(int listId) async {
    final key = await StorageService.getMdblistApiKey();
    if (key == null || key.isEmpty) return false;
    try {
      final res = await http
          .delete(Uri.parse('$_base/lists/$listId?apikey=$key'))
          .timeout(const Duration(seconds: 15));
      final c = res.statusCode;
      return c == 200 || c == 204 || c == 404;
    } catch (_) {
      return false;
    }
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
    final movies = extract(data['movies'] as List? ?? const []);
    final shows = extract(data['shows'] as List? ?? const []);

    final newId = await createList(name);
    if (newId == null) return null;
    final added = await addItemsToList(newId, movies: movies, shows: shows);
    if (!added) {
      await deleteList(newId); // roll back the empty list
      return null;
    }
    // My Lists now has a new entry — force a refetch on next read.
    _userListsCache = null;
    _userListsAt = null;
    return newId;
  }

  /// `GET /user` validates the key (limits/user-id); `GET /lists/user` resolves
  /// the display username (from the first list's `user_name`) and the list
  /// count. Returns null if the key is rejected (non-200 on /user) or the
  /// network call throws.
  Future<MdblistAccount?> _fetchAccount(String key) async {
    try {
      final userRes = await http
          .get(Uri.parse('$_base/user?apikey=$key'))
          .timeout(const Duration(seconds: 15));
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
        final listsRes = await http
            .get(Uri.parse('$_base/lists/user?apikey=$key'))
            .timeout(const Duration(seconds: 15));
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
