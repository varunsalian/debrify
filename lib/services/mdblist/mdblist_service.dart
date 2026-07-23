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
    await StorageService.clearMdblistAuth();
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
