import '../../../models/media_server.dart';
import 'jellyfin_emby_request.dart';
import 'media_server_lookup_pager.dart';

/// Jellyfin/Emby exact provider-ID lookup (moved from the original
/// `MediaServerClient`).
class JellyfinEmbyLookup {
  JellyfinEmbyLookup(
    this._request,
    this._pager, {
    required this.lookupBudget,
    required DateTime Function() lookupClock,
  }) : _lookupClock = lookupClock;

  final JellyfinEmbyRequest _request;
  final MediaServerLookupPager _pager;
  final Duration lookupBudget;
  final DateTime Function() _lookupClock;

  // Jellyfin has no exact provider-ID query. The pager caches only verified
  // matches and a continuation offset.
  Future<List<Map<String, dynamic>>> _lookupPages(
    MediaServerAccount account,
    String path,
    Map<String, String> query,
    bool Function(Map<String, dynamic>) matches,
    Future<void> Function()? authorize, {
    required DateTime deadline,
    required String identity,
    Object? cacheScope,
    void Function()? onIncomplete,
  }) {
    final pageSize = account.kind == MediaServerKind.jellyfin ? 500 : 100;
    return _pager.pages(
      account: account,
      path: path,
      query: query,
      pageSize: pageSize,
      idOf: (item) => item['Id'] as String,
      matches: matches,
      deadline: deadline,
      identity: identity,
      authorize: authorize,
      cacheScope: cacheScope,
      onIncomplete: onIncomplete,
      fetchPage: (offset, requestTimeout) async {
        final data = await _request.call(
          account.baseUrl,
          path,
          deviceId: account.deviceId,
          kind: account.kind,
          token: account.token,
          query: {
            ...query,
            'UserId': account.userId,
            'StartIndex': '$offset',
            'Limit': '$pageSize',
            'EnableTotalRecordCount': 'true',
          },
          authorize: authorize,
          requestTimeout: requestTimeout,
        );
        final page = data['Items'];
        if (page is! List ||
            page.any(
              (item) => item is! Map<String, dynamic> || item['Id'] is! String,
            )) {
          throw const MediaServerException(
            'The server returned an invalid library response.',
          );
        }
        final total = data['TotalRecordCount'];
        return (
          items: page.cast<Map<String, dynamic>>(),
          total: total is num ? total.toInt() : null,
        );
      },
    );
  }

  /// Exact provider IDs only. Avoid fuzzy guesses, remakes and alternate
  /// anime numbering: missing metadata should produce no match, not a wrong one.
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
    final deadline = _lookupClock().add(lookupBudget);
    final provider = RegExp(r'^tt\d+$').hasMatch(id)
        ? 'imdb'
        : RegExp(r'^tmdb:\d+$').hasMatch(id)
        ? 'tmdb'
        : RegExp(r'^tvdb:\d+$').hasMatch(id)
        ? 'tvdb'
        : null;
    if (provider == null || (!isMovie && (season == null || episode == null))) {
      return [];
    }
    final providerId = provider == 'imdb' ? id : id.split(':').last;
    bool matchesIdentity(Map<String, dynamic> item) {
      final ids = item['ProviderIds'];
      return item['Type'] == (isMovie ? 'Movie' : 'Series') &&
          ids is Map &&
          ids.entries.any(
            (entry) =>
                entry.key.toString().toLowerCase() == provider &&
                entry.value.toString() == providerId,
          );
    }

    final path = 'Users/${JellyfinEmbyRequest.segment(account.userId)}/Items';
    final query = {
      'Recursive': 'true',
      'IncludeItemTypes': isMovie ? 'Movie' : 'Series',
      'EnableImages': 'false',
      'EnableUserData': 'false',
    };
    final exact = await _lookupPages(
      account,
      path,
      {
        ...query,
        if (account.kind == MediaServerKind.jellyfin) ...{
          'Fields': 'ProviderIds',
          'Has${provider[0].toUpperCase()}${provider.substring(1)}Id': 'true',
          'SortBy': 'SortName',
          'SortOrder': 'Ascending',
        } else ...{
          'AnyProviderIdEquals': '$provider.$providerId',
          'Fields': 'ProviderIds,MediaSources,MediaStreams',
        },
      },
      matchesIdentity,
      authorize,
      deadline: deadline,
      identity: id,
      cacheScope: cacheScope,
      onIncomplete: onIncomplete,
    );
    if (isMovie) {
      return exact.where((item) => item['IsPlaceHolder'] != true).toList();
    }
    final episodes = <Map<String, dynamic>>[];
    for (final series in exact) {
      final path =
          'Shows/${JellyfinEmbyRequest.segment(series['Id'] as String)}/Episodes';
      final query = {
        'Season': '$season',
        // PlaybackInfo supplies streams after matching. Avoid downloading every
        // episode's versions/tracks while scanning a large Jellyfin season.
        if (account.kind == MediaServerKind.emby)
          'Fields': 'MediaSources,MediaStreams',
        'IsMissing': 'false',
        'EnableImages': 'false',
        'EnableUserData': 'false',
      };
      bool matchesEpisode(Map<String, dynamic> item) =>
          item['Type'] == 'Episode' &&
          item['ParentIndexNumber'] == season &&
          item['IndexNumber'] is int &&
          episode! >= (item['IndexNumber'] as int) &&
          episode <=
              (item['IndexNumberEnd'] is int
                  ? item['IndexNumberEnd'] as int
                  : item['IndexNumber'] as int) &&
          item['IsMissing'] != true &&
          item['IsPlaceHolder'] != true;
      final found = await _lookupPages(
        account,
        path,
        query,
        matchesEpisode,
        authorize,
        deadline: deadline,
        identity: '$id:$season:$episode',
        cacheScope: cacheScope,
        onIncomplete: onIncomplete,
      );
      episodes.addAll(found);
    }
    return episodes;
  }
}
