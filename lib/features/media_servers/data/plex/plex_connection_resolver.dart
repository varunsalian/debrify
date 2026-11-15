import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../../models/media_server.dart';
import '../../../../services/profiles/profile_runtime.dart';
import '../../models/media_server_errors.dart';
import '../media_server_http.dart';
import 'plex_request.dart';

/// Picks a reachable address for a Plex server. Only addresses stored at
/// sign-in are tried, and a token is never sent to an address before its
/// `/identity` answers with the expected server id.
class PlexConnectionResolver {
  PlexConnectionResolver(
    this._http, {
    DateTime Function()? clock,
    this.probeTimeout = const Duration(seconds: 3),
  }) : _clock = clock ?? DateTime.now {
    _clearOnProfileSwitch();
  }

  final MediaServerHttp _http;
  final DateTime Function() _clock;
  final Duration probeTimeout;

  static const _lifetime = Duration(minutes: 10);
  static const _maxEntries = 32;
  static final _cache = <(Object?, String), _Resolved>{};
  static final _pending = <(Object?, String), Future<String>>{};
  static final _forgotten = <String, int>{};
  static var _listening = false;

  /// Addresses chosen for one profile are not kept for the next.
  static void _clearOnProfileSwitch() {
    if (_listening) return;
    _listening = true;
    ProfileRuntime.scope.addListener(_cache.clear);
  }

  static String _serverKey(MediaServerAccount account) => sha256
      .convert(utf8.encode(jsonEncode([account.serverId, candidates(account)])))
      .toString();

  /// Forgets the address chosen for [account]'s server in every scope,
  /// including a probe still running.
  static void forget(MediaServerAccount account) {
    final server = _serverKey(account);
    _cache.removeWhere((key, _) => key.$2 == server);
    _forgotten[server] = (_forgotten[server] ?? 0) + 1;
  }

  /// Every address the account may use, in priority order.
  static List<String> candidates(MediaServerAccount account) {
    final ordered = <String>[
      for (final c in account.connections) c.uri,
      if (account.connections.isEmpty) account.baseUrl,
    ];
    return ordered.toSet().toList();
  }

  /// [account] with a verified [MediaServerAccount.baseUrl]. [cacheScope]
  /// separates profiles and connection revisions. Callers waiting on the same
  /// probe share the first caller's deadline.
  Future<MediaServerAccount> resolve(
    MediaServerAccount account, {
    Future<void> Function()? authorize,
    Object? cacheScope,
    DateTime? deadline,
  }) async {
    await authorize?.call();
    final server = _serverKey(account);
    final key = (cacheScope, server);
    final now = _clock();
    _cache.removeWhere((_, entry) => now.isAfter(entry.expires));
    final cached = _cache[key];
    if (cached != null) return account.withBaseUrl(cached.baseUrl);
    final epoch = _forgotten[server] ?? 0;
    final base = await (_pending[key] ??= _probe(account, deadline)
        // A callback returning the removed future would wait on itself.
        .whenComplete(() {
          _pending.remove(key);
        }));
    await authorize?.call();
    if ((_forgotten[server] ?? 0) == epoch) {
      while (_cache.length >= _maxEntries) {
        _cache.remove(_cache.keys.first);
      }
      _cache[key] = _Resolved(base, _clock().add(_lifetime));
    }
    return account.withBaseUrl(base);
  }

  /// All addresses are probed at once; the result is the first address in
  /// priority order that answers, decided as soon as every address before
  /// it has failed.
  Future<String> _probe(MediaServerAccount account, DateTime? deadline) async {
    final remaining = deadline?.difference(_clock());
    if (remaining != null && remaining <= Duration.zero) {
      throw const MediaServerLookupBudgetExhausted('Search budget exhausted');
    }
    final cutShort = remaining != null && remaining < probeTimeout;
    final timeout = cutShort ? remaining : probeTimeout;
    final addresses = candidates(account);
    if (addresses.isEmpty) {
      throw const MediaServerUnreachable(
        'Cannot reach the server. Check its address and network connection.',
      );
    }
    final answers = List<bool?>.filled(addresses.length, null);
    final decided = Completer<String?>();
    void decide() {
      if (decided.isCompleted) return;
      for (var i = 0; i < answers.length; i++) {
        if (answers[i] == null) return;
        if (answers[i]!) {
          decided.complete(addresses[i]);
          return;
        }
      }
      decided.complete(null);
    }

    for (var i = 0; i < addresses.length; i++) {
      unawaited(
        _identity(account, addresses[i], timeout).then((ok) {
          answers[i] = ok;
          decide();
        }),
      );
    }
    final base = await decided.future;
    if (base != null) return base;
    if (cutShort) {
      // Not proof the server is down: the search ran out of time first.
      throw const MediaServerLookupBudgetExhausted('Search budget exhausted');
    }
    throw const MediaServerUnreachable(
      'Cannot reach the server. Check its address and network connection.',
    );
  }

  Future<bool> _identity(
    MediaServerAccount account,
    String address,
    Duration timeout,
  ) async {
    try {
      final identity = await _http.json(
        () => MediaServerHttp.endpoint(address, 'identity'),
        headers: () => PlexRequest.headers(account.deviceId),
        kind: MediaServerKind.plex,
        operation: 'identity',
        requestTimeout: timeout,
      );
      final container = identity['MediaContainer'];
      return container is Map &&
          container['machineIdentifier'] == account.serverId;
    } catch (_) {
      return false;
    }
  }
}

class _Resolved {
  const _Resolved(this.baseUrl, this.expires);
  final String baseUrl;
  final DateTime expires;
}
