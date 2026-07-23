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
  List<Map<String, dynamic>>? _likedListsCache;
  DateTime? _likedListsAt;
  final Map<int, ({Map<String, dynamic> data, DateTime at})> _itemsCache = {};

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

  /// Fetches the user's liked lists (raw JSON maps from `GET /lists/user/liked`
  /// — a plain array, same shape as the other list endpoints). These are public
  /// lists the user has liked on MDBList (carry `user_name`). Returns `[]` when
  /// not connected or on any failure.
  Future<List<Map<String, dynamic>>> fetchLikedLists() async {
    if (_likedListsCache != null && _fresh(_likedListsAt)) {
      return _likedListsCache!;
    }
    final key = await StorageService.getMdblistApiKey();
    if (key == null || key.isEmpty) return const [];
    try {
      final res = await http
          .get(Uri.parse('$_base/lists/user/liked?apikey=$key'))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return const [];
      final decoded = jsonDecode(res.body);
      if (decoded is List) {
        final lists = [
          for (final e in decoded)
            if (e is Map<String, dynamic>) e,
        ];
        _likedListsCache = lists;
        _likedListsAt = DateTime.now();
        return lists;
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

    final data = <String, dynamic>{'movies': movies, 'shows': shows};
    if (complete) {
      _itemsCache[listId] = (data: data, at: DateTime.now());
    }
    return data;
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
