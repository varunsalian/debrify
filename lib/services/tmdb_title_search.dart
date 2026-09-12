import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/stremio_addon.dart';
import 'tmdb_metadata_repository.dart';

/// A short, debounced title lookup. Submitting the field still belongs to the
/// host's catalog/keyword search; this never fans out to stream addons.
class TmdbTitleSearch extends ValueNotifier<List<StremioMeta>> {
  TmdbTitleSearch({TmdbMetadataRepository? repository})
    : _repository = repository ?? TmdbMetadataRepository.instance,
      super(const []);

  final TmdbMetadataRepository _repository;
  Timer? _timer;
  int _generation = 0;
  String? _requestKey;
  bool _disposed = false;

  static bool accepts(String query) {
    final q = query.trim();
    return q.runes.length >= 2 &&
        q.length <= 200 &&
        // A colon is common in a title ("Dune: Part Two"). Only recognizable
        // link forms and URI schemes should bypass title lookup.
        !RegExp(
          r'(^(?:https?|ftp|ftps|file|content|magnet|data|mailto|tel|urn):|://|^www\.)',
          caseSensitive: false,
        ).hasMatch(q) &&
        !RegExp(
          r'^(tt\d+|[a-f0-9]{40}|[a-f0-9]{64})$',
          caseSensitive: false,
        ).hasMatch(q);
  }

  void update(
    String query, {
    required String language,
    bool enabled = true,
    bool composing = false,
  }) {
    if (_disposed) return;
    final q = query.trim();
    if (!enabled || composing || !_repository.configured || !accepts(q)) {
      clear();
      return;
    }
    final key = '$language\n$q';
    if (_requestKey == key) return;
    clear();
    _requestKey = key;
    final generation = _generation;
    _timer = Timer(const Duration(milliseconds: 350), () async {
      bool current() => !_disposed && generation == _generation;
      try {
        final data = await _repository.get('search/multi', {
          'query': q,
          'language': language,
          'include_adult': 'false',
          'page': '1',
        }, current);
        if (!current()) return;
        value = parse(data);
      } catch (_) {
        // Optional suggestions must never block an ordinary search. The shared
        // repository owns timeout, caching, concurrency and 429 backoff.
        if (current()) value = const [];
      }
    });
  }

  static List<StremioMeta> parse(Map<String, dynamic> data) {
    final results = data['results'];
    if (results is! List) return const [];
    final seen = <String>{};
    final items = <StremioMeta>[];
    for (final raw in results) {
      if (raw is! Map<String, dynamic> || raw['adult'] == true) continue;
      final media = raw['media_type'];
      if (media != 'movie' && media != 'tv') continue;
      final id = raw['id'];
      final title = media == 'movie' ? raw['title'] : raw['name'];
      if (id is! int || id <= 0 || title is! String || title.trim().isEmpty) {
        continue;
      }
      if (!seen.add('$media:$id')) continue;
      final date = media == 'movie'
          ? raw['release_date']
          : raw['first_air_date'];
      final year = date is String && RegExp(r'^\d{4}-').hasMatch(date)
          ? date.substring(0, 4)
          : null;
      items.add(
        StremioMeta(
          id: 'tmdb:$id',
          type: media == 'tv' ? 'series' : 'movie',
          name: title.trim(),
          year: year,
          poster: TmdbMetadataRepository.image(
            raw['poster_path'],
            size: 'w185',
          ),
          background: TmdbMetadataRepository.image(
            raw['backdrop_path'],
            size: 'w1280',
          ),
          description: raw['overview'] is String
              ? raw['overview'] as String
              : null,
        ),
      );
      if (items.length == 6) break;
    }
    return List.unmodifiable(items);
  }

  void clear() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _requestKey = null;
    if (!_disposed && value.isNotEmpty) value = const [];
  }

  @override
  void dispose() {
    clear();
    _disposed = true;
    super.dispose();
  }
}
