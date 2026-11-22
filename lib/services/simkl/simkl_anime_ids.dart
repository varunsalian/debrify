import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/media_identity.dart';
import 'simkl_constants.dart';

/// The full ids of Simkl anime titles. The account's lists name an anime by
/// its Simkl and TMDB ids only, but metadata and sources need its IMDb id,
/// which the public catalog (`GET /anime/{id}`) has.
final class SimklAnimeIds {
  const SimklAnimeIds._();

  static const Duration _ttl = Duration(days: 1);
  static const Duration _failureTtl = Duration(minutes: 10);
  static const int _maxCachedTitles = 500;
  static final Map<int, ({Map<String, dynamic>? ids, DateTime at})> _ids = {};
  static final Map<int, Future<Map<String, dynamic>?>> _inFlight = {};

  /// Forgets every read (tests; ids are catalog data, not per account).
  static void clearCache() {
    _ids.clear();
    _inFlight.clear();
  }

  /// [ids] filled in from the catalog when it lacks an IMDb id. Ids the
  /// account already gives are kept; a failed read returns [ids] as they
  /// are. Never throws.
  static Future<Map<String, dynamic>> complete(dynamic ids) async {
    final own = ids is Map
        ? ids.cast<String, dynamic>()
        : const <String, dynamic>{};
    if (_hasImdb(own)) return own;
    final simklId = _int(own['simkl'] ?? own['simkl_id']);
    if (simklId == null) return own;
    final full = await _idsFor(simklId);
    if (full == null) return own;
    return {
      ...own,
      for (final entry in full.entries)
        if (_missing(own[entry.key])) entry.key: entry.value,
    };
  }

  static bool _hasImdb(Map<String, dynamic> ids) {
    final imdb = ids['imdb'];
    return imdb is String && MediaIdentity.isImdb(imdb.trim().toLowerCase());
  }

  static bool _missing(Object? value) =>
      value == null || (value is String && value.trim().isEmpty);

  static Future<Map<String, dynamic>?> _idsFor(int simklId) {
    final cached = _ids[simklId];
    if (cached != null &&
        DateTime.now().difference(cached.at) <
            (cached.ids == null ? _failureTtl : _ttl)) {
      return Future.value(cached.ids);
    }
    return _inFlight[simklId] ??= () async {
      Map<String, dynamic>? ids;
      try {
        final raw = await simklPublicGet('/anime/$simklId');
        if (raw is Map && raw['ids'] is Map) {
          ids = (raw['ids'] as Map).cast<String, dynamic>();
        }
      } catch (_) {
        ids = null;
      } finally {
        _inFlight.remove(simklId);
      }
      _ids.remove(simklId);
      if (_ids.length >= _maxCachedTitles) _ids.remove(_ids.keys.first);
      _ids[simklId] = (ids: ids, at: DateTime.now());
      return ids;
    }();
  }

  static int? _int(dynamic value) => switch (value) {
    int v => v,
    num v => v.toInt(),
    String v => int.tryParse(v),
    _ => null,
  };
}

/// A public Simkl catalog GET (client id only, no user token); decoded JSON
/// or null on failure.
Future<dynamic> simklPublicGet(String path) async {
  final uri = Uri.parse('$kSimklApiBaseUrl$path').replace(
    queryParameters: {
      'client_id': kSimklClientId,
      'app-name': kSimklAppName,
      'app-version': kSimklAppVersion,
    },
  );
  final response = await http
      .get(
        uri,
        headers: {'simkl-api-key': kSimklClientId, 'User-Agent': 'Debrify'},
      )
      .timeout(const Duration(seconds: 15));
  if (response.statusCode != 200) {
    debugPrint('Simkl: anime catalog read failed (${response.statusCode})');
    return null;
  }
  return jsonDecode(response.body);
}
