import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../models/media_server.dart';
import '../models/media_server_errors.dart';

/// One fetched page: validated items and the server's total, if it sent one.
typedef MediaServerLookupPage = ({
  List<Map<String, dynamic>> items,
  int? total,
});

/// Pages through a library looking for exact matches (moved from the
/// original Jellyfin client). Servers without an exact provider-ID query are
/// scanned page by page within a time budget. Only verified matches and a
/// continuation offset are cached, not a copy of the user's library. Each
/// caller supplies its profile/connection revision scope; credentials are
/// hashed into the key.
class MediaServerLookupPager {
  MediaServerLookupPager({
    required this.timeout,
    required DateTime Function() clock,
  }) : _clock = clock;

  final Duration timeout;
  final DateTime Function() _clock;
  static final _cache = <(Object, String), _LookupPageState>{};

  /// Returns matching items. When the budget or a request runs out of time,
  /// [onIncomplete] (if given) is called and the matches found so far are
  /// returned; any other failure is rethrown and drops the cached progress.
  Future<List<Map<String, dynamic>>> pages({
    required MediaServerAccount account,
    required String path,
    required Map<String, String> query,
    required int pageSize,
    required String Function(Map<String, dynamic>) idOf,
    required bool Function(Map<String, dynamic>) matches,
    required Future<MediaServerLookupPage> Function(
      int offset,
      Duration requestTimeout,
    )
    fetchPage,
    required DateTime deadline,
    required String identity,
    Future<void> Function()? authorize,
    Object? cacheScope,
    void Function()? onIncomplete,
  }) async {
    await authorize?.call();
    final now = _clock();
    _cache.removeWhere(
      (_, entry) => now.difference(entry.created) > const Duration(minutes: 1),
    );
    final cacheKey = cacheScope == null
        ? null
        : (
            cacheScope,
            sha256
                .convert(
                  utf8.encode(
                    jsonEncode([account.toJson(), path, query, identity]),
                  ),
                )
                .toString(),
          );
    final saved = cacheKey == null ? null : _cache[cacheKey];
    final state = saved?.copy() ?? _LookupPageState(now);
    if (state.complete) {
      await authorize?.call();
      return state.items;
    }
    try {
      while (true) {
        await authorize?.call();
        final remaining = deadline.difference(_clock());
        if (remaining <= Duration.zero) {
          throw const MediaServerLookupBudgetExhausted(
            'Search budget exhausted',
          );
        }
        final data = await fetchPage(
          state.offset,
          remaining < timeout ? remaining : timeout,
        );
        final page = data.items;
        if (page.isEmpty) {
          state.complete = true;
          break;
        }
        final boundary = jsonEncode([
          idOf(page.first),
          idOf(page.last),
          page.length,
        ]);
        if (!state.boundaries.add(boundary)) {
          throw const MediaServerException(
            'The server repeated a library page. Please retry or check the server.',
          );
        }
        final known = state.items.map(idOf).toSet();
        state.items.addAll(
          page.where((item) => matches(item) && known.add(idOf(item))),
        );
        state.offset += page.length;
        final total = data.total;
        if (total != null ? state.offset >= total : page.length < pageSize) {
          state.complete = true;
          break;
        }
      }
    } on MediaServerTimeout {
      // Authorization failures must never be converted to partial success.
      await authorize?.call();
      if (onIncomplete == null) rethrow;
      onIncomplete();
    } catch (_) {
      if (cacheKey != null) _cache.remove(cacheKey);
      rethrow;
    }
    await authorize?.call();
    if (cacheKey != null &&
        state.items.length <= 2000 &&
        state.boundaries.length <= 2000) {
      // Fixed creation time prevents a frequently used entry from living forever.
      // Empty completed lookups are not cached: new additions remain discoverable.
      _cache.remove(cacheKey);
      if (!state.complete || state.items.isNotEmpty) {
        while (_cache.length >= 32) {
          _cache.remove(_cache.keys.first);
        }
        _cache[cacheKey] = state.copy();
      }
    }
    return state.items;
  }
}

class _LookupPageState {
  _LookupPageState(this.created);
  final DateTime created;
  int offset = 0;
  bool complete = false;
  final items = <Map<String, dynamic>>[];
  final boundaries = <String>{};
  _LookupPageState copy() => _LookupPageState(created)
    ..offset = offset
    ..complete = complete
    ..items.addAll(items.map((item) => Map<String, dynamic>.from(item)))
    ..boundaries.addAll(boundaries);
}
