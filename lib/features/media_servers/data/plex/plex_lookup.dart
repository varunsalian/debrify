import '../../../../models/media_server.dart';
import '../../models/media_server_errors.dart';
import '../media_server_lookup_pager.dart';
import 'plex_item_mapping.dart';
import 'plex_request.dart';

/// Exact IMDb/TMDB/TVDB matching on a Plex server. Plex cannot filter a
/// library by an external id, so modern-agent libraries ask the server's
/// agent for the item's `plex://` guid and filter by that; legacy-agent
/// libraries (or servers that refuse the agent call) are scanned within the
/// lookup budget. Every result is checked against the requested id.
class PlexLookup {
  PlexLookup(
    this._request,
    this._pager, {
    required this.lookupBudget,
    required DateTime Function() clock,
  }) : _clock = clock;

  final PlexRequest _request;
  final MediaServerLookupPager _pager;
  final Duration lookupBudget;
  final DateTime Function() _clock;

  static const _modernAgents = {
    'movie': 'tv.plex.agents.movie',
    'show': 'tv.plex.agents.series',
  };
  static const _noIdAgents = {'tv.plex.agents.none', 'com.plexapp.agents.none'};
  static const _scanPageSize = 500;

  static ({String provider, String value})? _parse(String id) {
    if (RegExp(r'^tt\d+$').hasMatch(id)) return (provider: 'imdb', value: id);
    final match = RegExp(r'^(tmdb|tvdb):(\d+)$').firstMatch(id);
    return match == null ? null : (provider: match[1]!, value: match[2]!);
  }

  Future<List<Map<String, dynamic>>> findItems(
    MediaServerAccount account, {
    required String id,
    required bool isMovie,
    int? season,
    int? episode,
    Future<void> Function()? authorize,
    Object? cacheScope,
    void Function()? onIncomplete,
  }) async {
    final wanted = _parse(id);
    if (wanted == null || (!isMovie && (season == null || episode == null))) {
      return [];
    }
    final deadline = _clock().add(lookupBudget);
    final type = isMovie ? 'movie' : 'show';
    final externalId = '${wanted.provider}:${wanted.value}';
    bool isWanted(Map<String, dynamic> metadata) =>
        metadata['type'] == type &&
        plexExternalIds(metadata).contains(externalId);

    Duration remaining() {
      final left = deadline.difference(_clock());
      if (left <= Duration.zero) {
        throw const MediaServerLookupBudgetExhausted('Search budget exhausted');
      }
      return left < _request.timeout ? left : _request.timeout;
    }

    Future<Map<String, dynamic>> get(
      String path,
      String operation, [
      Map<String, String>? query,
    ]) async => _container(
      await _request.call(
        account,
        path,
        query: query,
        operation: operation,
        authorize: authorize,
        requestTimeout: remaining(),
      ),
    );

    final found = <String, Map<String, dynamic>>{};
    final episodes = <Map<String, dynamic>>[];
    try {
      final sections = [
        for (final section
            in (await get('library/sections', 'sections'))['Directory']
                    as List? ??
                const [])
          if (section is Map<String, dynamic> &&
              section['type'] == type &&
              plexNumericId(section['key']) != null &&
              !_noIdAgents.contains(section['agent']))
            section,
      ];
      final modern = [
        for (final s in sections)
          if (s['agent'] == _modernAgents[type]) s,
      ];
      final scan = [
        for (final s in sections)
          if (s['agent'] != _modernAgents[type]) s,
      ];
      final guids = modern.isEmpty
          ? const <String>{}
          : await _plexGuids(modern, wanted, get);
      if (guids == null) {
        scan.addAll(modern);
      } else {
        for (final section in modern) {
          for (final guid in guids) {
            final data = await get(
              'library/sections/${section['key']}/all',
              'lookup',
              {'guid': guid, 'includeGuids': '1'},
            );
            for (final item in _metadata(data)) {
              if (isWanted(item)) {
                found[item['ratingKey'] as String] = {
                  ...item,
                  'librarySectionID': section['key'],
                };
              }
            }
          }
        }
      }
      for (final section in scan) {
        final path = 'library/sections/${section['key']}/all';
        final query = {'type': isMovie ? '1' : '2', 'includeGuids': '1'};
        final items = await _pager.pages(
          account: account,
          path: path,
          query: query,
          pageSize: _scanPageSize,
          idOf: (item) => item['ratingKey'] as String,
          matches: isWanted,
          deadline: deadline,
          identity: id,
          authorize: authorize,
          cacheScope: cacheScope,
          onIncomplete: onIncomplete,
          fetchPage: (offset, requestTimeout) async {
            final data = _container(
              await _request.call(
                account,
                path,
                query: {
                  ...query,
                  'X-Plex-Container-Start': '$offset',
                  'X-Plex-Container-Size': '$_scanPageSize',
                },
                operation: 'lookup',
                authorize: authorize,
                requestTimeout: requestTimeout,
              ),
            );
            final total = data['totalSize'];
            return (
              items: _metadata(data, strict: true),
              total: total is num ? total.toInt() : null,
            );
          },
        );
        for (final item in items) {
          found[item['ratingKey'] as String] = {
            ...item,
            'librarySectionID': section['key'],
          };
        }
      }
      if (isMovie) {
        return [for (final item in found.values) ?plexItem(item)];
      }
      for (final show in found.values) {
        final section = plexNumericId(show['librarySectionID']);
        final sectionKeys = section == null
            ? [for (final s in sections) s['key'] as String]
            : [section];
        for (final key in sectionKeys) {
          final data = await get('library/sections/$key/all', 'lookup', {
            'type': '4',
            'show.id': show['ratingKey'] as String,
            'season.index': '$season',
            'episode.index': '$episode',
          });
          for (final item in _metadata(data)) {
            if (item['type'] == 'episode' &&
                plexNumericId(item['grandparentRatingKey']) ==
                    show['ratingKey'] &&
                item['parentIndex'] == season &&
                item['index'] == episode) {
              if (plexItem(item) case final mapped?) episodes.add(mapped);
            }
          }
        }
      }
      return episodes;
    } on MediaServerTimeout {
      // Same rule as the pager: running out of time is an incomplete search,
      // never a reason to skip authorization.
      await authorize?.call();
      if (onIncomplete == null) rethrow;
      onIncomplete();
      return isMovie
          ? [for (final item in found.values) ?plexItem(item)]
          : episodes;
    }
  }

  /// The `plex://` guids Plex's own agent gives [wanted], or null when the
  /// server will not answer (shared users, old servers): then the caller
  /// scans instead. Profile and deadline errors are not caught here.
  Future<Set<String>?> _plexGuids(
    List<Map<String, dynamic>> sections,
    ({String provider, String value}) wanted,
    Future<Map<String, dynamic>> Function(
      String path,
      String operation, [
      Map<String, String>? query,
    ])
    get,
  ) async {
    try {
      for (final section in sections) {
        final sample = _metadata(
          await get('library/sections/${section['key']}/all', 'lookup', {
            'X-Plex-Container-Start': '0',
            'X-Plex-Container-Size': '1',
          }),
        );
        final dummy = sample.isEmpty
            ? null
            : plexNumericId(sample.first['ratingKey']);
        if (dummy == null) continue;
        final language = section['language'];
        final data = await get('library/metadata/$dummy/matches', 'match', {
          'manual': '1',
          'title': '${wanted.provider}-${wanted.value}',
          'agent': section['agent'] as String,
          if (language is String && language.isNotEmpty) 'language': language,
        });
        // Plex answers an id it does not know with no results at all (and
        // may answer the same when its metadata service is unreachable), so
        // an empty answer means "not here": scanning on every
        // search for a title the user does not own would be far too costly.
        // Only a refused or failed agent request (below) falls back to a scan.
        final results = data['SearchResult'];
        return {
          if (results is List)
            for (final result in results)
              if (result is Map &&
                  result['guid'] is String &&
                  (result['guid'] as String).startsWith('plex://'))
                result['guid'] as String,
        };
      }
      return const {};
    } on MediaServerAuthError {
      return null;
    } on MediaServerHttpError {
      return null;
    }
  }

  static Map<String, dynamic> _container(Map<String, dynamic> data) {
    final container = data['MediaContainer'];
    if (container is! Map<String, dynamic>) {
      throw const MediaServerException(
        'The server returned an invalid library response.',
      );
    }
    return container;
  }

  /// Entries with a numeric `ratingKey`. In [strict] mode (paged scans) a
  /// malformed entry fails the page, as it does for Jellyfin.
  static List<Map<String, dynamic>> _metadata(
    Map<String, dynamic> container, {
    bool strict = false,
  }) {
    final rows = container['Metadata'] ?? const [];
    if (rows is! List) {
      throw const MediaServerException(
        'The server returned an invalid library response.',
      );
    }
    final valid = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row is Map<String, dynamic> &&
          plexNumericId(row['ratingKey']) != null) {
        valid.add({...row, 'ratingKey': plexNumericId(row['ratingKey'])});
      } else if (strict) {
        throw const MediaServerException(
          'The server returned an invalid library response.',
        );
      }
    }
    return valid;
  }
}
