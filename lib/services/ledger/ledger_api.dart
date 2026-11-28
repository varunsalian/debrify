import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/features/ledger/models/ledger_media.dart';
import 'package:debrify/features/ledger/models/ledger_tracking.dart';

/// Supplies the bearer token for [LedgerApi] and renews it after a 401.
abstract interface class LedgerTokenSource {
  /// A currently valid access token, refreshing first when it is about to
  /// expire. Null when signed out.
  Future<String?> accessToken();

  /// Forces one refresh after the server rejected [rejectedToken]. Returns
  /// the new token, or null when the session could not be renewed.
  Future<String?> renewAfterRejection(String rejectedToken);
}

class LedgerApiException implements Exception {
  const LedgerApiException(this.statusCode, [this.message]);

  /// HTTP status, or 0 for a transport failure / signed-out state.
  final int statusCode;
  final String? message;

  bool get unauthorized => statusCode == 401;

  @override
  String toString() => 'LedgerApiException($statusCode)';
}

/// Typed client for the authenticated tracking endpoints. Every method
/// throws [LedgerApiException] on failure; callers decide how to degrade.
class LedgerApi {
  LedgerApi({
    required LedgerTokenSource tokens,
    http.Client? client,
    this.baseUrl = kLedgerApiBaseUrl,
  }) : _tokens = tokens,
       _client = client;

  final LedgerTokenSource _tokens;
  final http.Client? _client;
  final String baseUrl;

  static const Duration _timeout = Duration(seconds: 15);

  // ── Scrobble ──────────────────────────────────────────────────────────

  Future<LedgerScrobbleResult> scrobble({
    required LedgerScrobbleAction action,
    required LedgerMediaRef item,
    required double progress,
  }) async {
    final json = await _send(
      'POST',
      '/v1/me/scrobble',
      body: {
        'action': action.wire,
        'item': item.toJson(),
        'progress': progress.clamp(0.0, 100.0),
        'source': kLedgerScrobbleSource,
      },
    );
    return LedgerScrobbleResult(watched: json['watched'] == true);
  }

  // ── History ───────────────────────────────────────────────────────────

  Future<void> addHistory(List<LedgerMediaRef> items) async {
    if (items.isEmpty) return;
    await _send(
      'POST',
      '/v1/me/history',
      body: {
        'items': [
          for (final item in items) {'item': item.toJson()},
        ],
        'source': kLedgerScrobbleSource,
      },
    );
  }

  Future<void> removeHistory(List<LedgerMediaRef> items) async {
    if (items.isEmpty) return;
    await _send(
      'POST',
      '/v1/me/history:remove',
      body: {
        'items': [for (final item in items) item.toJson()],
      },
    );
  }

  /// Every watched movie, or every watched show with its episodes.
  Future<List<LedgerWatchedItem>> watched(LedgerMediaKind kind) async {
    final json = await _send(
      'GET',
      '/v1/me/watched',
      query: {
        'kind': kind.wire,
        if (kind == LedgerMediaKind.show) 'includeEpisodes': 'true',
      },
    );
    return _list(json['items'], LedgerWatchedItem.fromJson);
  }

  // ── Playback / progress ───────────────────────────────────────────────

  Future<List<LedgerPlayback>> playback({LedgerMediaKind? kind}) async {
    final json = await _send(
      'GET',
      '/v1/me/playback',
      query: {if (kind != null) 'kind': kind.wire, 'pageSize': '500'},
    );
    return _list(json['playback'], LedgerPlayback.fromJson);
  }

  Future<void> deletePlayback(String id) async {
    await _send('DELETE', '/v1/me/playback/${Uri.encodeComponent(id)}');
  }

  Future<List<LedgerUpNextEntry>> upNext({int pageSize = 100}) async {
    final json = await _send(
      'GET',
      '/v1/me/up-next',
      query: {'pageSize': '${pageSize.clamp(1, 100)}'},
    );
    return _list(json['entries'], LedgerUpNextEntry.fromJson);
  }

  Future<LedgerShowProgress?> showProgress(
    String showId, {
    bool includeSpecials = false,
  }) async {
    final json = await _send(
      'GET',
      '/v1/me/progress/shows/${Uri.encodeComponent(showId)}',
      query: {if (includeSpecials) 'includeSpecials': 'true'},
    );
    return LedgerShowProgress.fromJson(json);
  }

  /// The catalog item behind [ref] plus the user's state for it. Returns
  /// null when the catalog does not hold the item (404).
  Future<({LedgerMedia? item, LedgerItemStatus status})?> status(
    LedgerMediaRef ref,
  ) async {
    final query = <String, String>{'item.kind': ref.kind.wire};
    void addIds(String prefix, LedgerIds ids) {
      if (ids.imdb != null) query['$prefix.imdb'] = ids.imdb!;
      if (ids.tmdb != null) query['$prefix.tmdb'] = ids.tmdb!;
      if (ids.tvdb != null) query['$prefix.tvdb'] = ids.tvdb!;
    }

    addIds('item.ids', ref.ids);
    addIds('item.showIds', ref.showIds);
    if (ref.season != null) query['item.season'] = '${ref.season}';
    if (ref.number != null) query['item.number'] = '${ref.number}';
    try {
      final json = await _send('GET', '/v1/me/status', query: query);
      return (
        item: LedgerMedia.fromJson(json['item']),
        status: LedgerItemStatus.fromJson(json),
      );
    } on LedgerApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<LedgerCalendarEntry>> calendar({
    required String startDate,
    int days = 30,
  }) async {
    final json = await _send(
      'GET',
      '/v1/me/calendar',
      query: {'startDate': startDate, 'days': '${days.clamp(1, 62)}'},
    );
    return _list(json['entries'], LedgerCalendarEntry.fromJson);
  }

  /// Items the user hid from one [section] (`HIDDEN_SECTION_PROGRESS`
  /// hides from Up Next; `HIDDEN_SECTION_DROPPED` marks dropped shows).
  Future<List<LedgerMedia>> hidden(String section) async {
    final json = await _send(
      'GET',
      '/v1/me/hidden',
      query: {'section': section},
    );
    final items = json['items'];
    if (items is! List) return List<LedgerMedia>.empty();
    return List<LedgerMedia>.unmodifiable(
      items
          .whereType<Map>()
          .map((entry) => LedgerMedia.fromJson(entry['item']))
          .whereType<LedgerMedia>(),
    );
  }

  /// The user's watched percent: a STOP at or past it records a play.
  Future<int?> watchedPercent() async {
    final json = await _send('GET', '/v1/me/tracking-settings');
    final settings = json['settings'] is Map ? json['settings'] : json;
    final value = ledgerPositiveInt((settings as Map)['watchedPercent']);
    return value?.clamp(50, 100);
  }

  /// Hides shows/movies from progress (Up Next / Continue Watching).
  Future<void> hideFromProgress(List<LedgerMediaRef> items) async {
    if (items.isEmpty) return;
    await _send(
      'POST',
      '/v1/me/hidden',
      body: {
        'section': 'HIDDEN_SECTION_PROGRESS',
        'items': [for (final item in items) item.toJson()],
      },
    );
  }

  /// Marks shows/movies dropped, or takes the mark off.
  Future<void> setDropped(
    List<LedgerMediaRef> items, {
    required bool dropped,
  }) async {
    if (items.isEmpty) return;
    await _send(
      'POST',
      dropped ? '/v1/me/hidden' : '/v1/me/hidden:remove',
      body: {
        'section': kLedgerDroppedSection,
        'items': [for (final item in items) item.toJson()],
      },
    );
  }

  // ── Watchlist / lists / ratings ───────────────────────────────────────

  Future<List<LedgerListedItem>> watchlist() async {
    final json = await _send('GET', '/v1/me/watchlist');
    return _list(json['items'], LedgerListedItem.fromJson);
  }

  Future<void> addToWatchlist(List<LedgerMediaRef> items) async {
    if (items.isEmpty) return;
    await _send(
      'POST',
      '/v1/me/watchlist',
      body: {
        'items': [
          for (final item in items) {'item': item.toJson()},
        ],
      },
    );
  }

  Future<void> removeFromWatchlist(List<LedgerMediaRef> items) async {
    if (items.isEmpty) return;
    await _send(
      'POST',
      '/v1/me/watchlist:remove',
      body: {
        'items': [for (final item in items) item.toJson()],
      },
    );
  }

  Future<List<LedgerUserList>> userLists() async {
    final json = await _send('GET', '/v1/me/lists');
    return _list(json['lists'], LedgerUserList.fromJson);
  }

  Future<List<LedgerListedItem>> userListItems(String listId) async {
    final json = await _send(
      'GET',
      '/v1/me/lists/${Uri.encodeComponent(listId)}/items',
    );
    return _list(json['items'], LedgerListedItem.fromJson);
  }

  Future<void> addToUserList(String listId, List<LedgerMediaRef> items) async {
    if (items.isEmpty) return;
    await _send(
      'POST',
      '/v1/me/lists/${Uri.encodeComponent(listId)}/items',
      body: {
        'items': [
          for (final item in items) {'item': item.toJson()},
        ],
      },
    );
  }

  Future<void> removeFromUserList(
    String listId,
    List<LedgerMediaRef> items,
  ) async {
    if (items.isEmpty) return;
    await _send(
      'POST',
      '/v1/me/lists/${Uri.encodeComponent(listId)}/items:remove',
      body: {
        'items': [for (final item in items) item.toJson()],
      },
    );
  }

  Future<void> rate(LedgerMediaRef item, int rating) async {
    await _send(
      'POST',
      '/v1/me/ratings',
      body: {
        'items': [
          {'item': item.toJson(), 'rating': rating.clamp(1, 10)},
        ],
      },
    );
  }

  Future<void> removeRating(LedgerMediaRef item) async {
    await _send(
      'POST',
      '/v1/me/ratings:remove',
      body: {
        'items': [item.toJson()],
      },
    );
  }

  // ── Account / imports ─────────────────────────────────────────────────

  Future<String?> displayName() async {
    final json = await _send('GET', '/v1/users/me');
    return ledgerString(json['displayName']) ?? ledgerString(json['email']);
  }

  Future<List<LedgerLinkedTracker>> linkedTrackers() async {
    final json = await _send('GET', '/v1/me/trackers');
    return _list(json['trackers'], LedgerLinkedTracker.fromJson);
  }

  /// Re-imports from a tracker linked on the website. Already imported
  /// plays are not duplicated.
  Future<void> startImport(String provider) async {
    await _send(
      'POST',
      '/v1/me/trackers/${Uri.encodeComponent(provider)}/imports',
      body: const <String, Object>{},
    );
  }

  // ── Transport ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final token = await _tokens.accessToken();
    if (token == null || token.isEmpty) {
      throw const LedgerApiException(0, 'signed out');
    }
    var response = await _request(method, path, token, query, body);
    if (response.statusCode == 401) {
      final renewed = await _tokens.renewAfterRejection(token);
      if (renewed == null || renewed.isEmpty) {
        throw const LedgerApiException(401);
      }
      response = await _request(method, path, renewed, query, body);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LedgerApiException(response.statusCode, _errorMessage(response));
    }
    if (response.body.isEmpty) return const <String, dynamic>{};
    try {
      final json = jsonDecode(response.body);
      return json is Map<String, dynamic> ? json : const <String, dynamic>{};
    } on FormatException {
      throw LedgerApiException(response.statusCode, 'invalid JSON');
    }
  }

  Future<http.Response> _request(
    String method,
    String path,
    String token,
    Map<String, String>? query,
    Object? body,
  ) async {
    final uri = Uri.parse(
      '$baseUrl$path',
    ).replace(queryParameters: query == null || query.isEmpty ? null : query);
    final request = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final client = _client;
      final streamed =
          await (client == null ? request.send() : client.send(request))
              .timeout(_timeout);
      return await http.Response.fromStream(streamed).timeout(_timeout);
    } on LedgerApiException {
      rethrow;
    } catch (error) {
      throw LedgerApiException(0, error.runtimeType.toString());
    }
  }

  String? _errorMessage(http.Response response) {
    try {
      final json = jsonDecode(response.body);
      return json is Map ? ledgerString(json['message']) : null;
    } catch (_) {
      return null;
    }
  }

  static List<T> _list<T>(Object? source, T? Function(Object?) parse) {
    if (source is! List) return List<T>.empty();
    return List<T>.unmodifiable(source.map(parse).whereType<T>());
  }
}

enum LedgerScrobbleAction {
  start('SCROBBLE_ACTION_START'),
  pause('SCROBBLE_ACTION_PAUSE'),
  stop('SCROBBLE_ACTION_STOP');

  const LedgerScrobbleAction(this.wire);
  final String wire;
}
