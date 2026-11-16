import 'dart:typed_data';

import '../../../../models/media_server.dart';
import '../../../../models/media_server_library.dart';
import 'plex_item_mapping.dart';
import 'plex_media.dart';
import 'plex_request.dart';

/// Plex library browsing for Discover. Library sections appear as views
/// with ids `s{key}`; shows and seasons open through their children.
class PlexLibrary {
  PlexLibrary(this._request, this._media);

  final PlexRequest _request;
  final PlexMedia _media;

  static const _pageSize = 60;
  static const _sorts = {
    'SortName': 'titleSort',
    'DateCreated': 'addedAt:desc',
    'ProductionYear': 'year:desc',
  };

  Future<MediaServerLibraryPage> library(
    MediaServerAccount account, {
    String? parentId,
    bool views = false,
    int offset = 0,
    String search = '',
    String sort = 'SortName',
    String mode = 'browse',
    bool episodeOrder = false,
    Future<void> Function()? authorize,
  }) async {
    if (offset < 0 ||
        !_sorts.containsKey(sort) ||
        !const {'browse', 'recent', 'resume'}.contains(mode)) {
      throw ArgumentError('Invalid library query');
    }
    if (views || parentId == null) {
      final data = await _request.call(
        account,
        'library/sections',
        operation: 'sections',
        authorize: authorize,
      );
      final rows = (data['MediaContainer'] as Map?)?['Directory'];
      return MediaServerLibraryPage([
        if (rows is List)
          for (final row in rows)
            if (row is Map<String, dynamic>)
              if (plexSectionItem(row) case final item?)
                MediaServerLibraryItem.fromJson(item),
      ], null);
    }
    final paging = {
      'X-Plex-Container-Start': '$offset',
      'X-Plex-Container-Size': '$_pageSize',
    };
    final String path;
    final Map<String, String> query;
    if (parentId.startsWith('s')) {
      final section = plexNumericId(parentId.substring(1));
      if (section == null) throw ArgumentError('Invalid library query');
      final shows = await _isShowSection(account, section, authorize);
      final term = search.trim();
      path = 'library/sections/$section/all';
      query = {
        ...paging,
        if (term.isNotEmpty) 'title': term,
        if (mode == 'browse') 'sort': _sorts[sort]!,
        if (mode == 'recent') ...{
          'type': shows ? '4' : '1',
          'sort': 'addedAt:desc',
        },
        if (mode == 'resume') ...{
          'type': shows ? '4' : '1',
          'inProgress': '1',
          'sort': 'lastViewedAt:desc',
        },
      };
    } else {
      final item = plexNumericId(parentId);
      if (item == null) throw ArgumentError('Invalid library query');
      path = 'library/metadata/$item/children';
      query = paging;
    }
    final data = await _request.call(
      account,
      path,
      query: query,
      operation: 'api',
      authorize: authorize,
    );
    final container = data['MediaContainer'];
    final rows = container is Map ? container['Metadata'] ?? const [] : null;
    if (rows is! List) {
      throw const MediaServerException(
        'The server returned an invalid library response.',
      );
    }
    final items = [
      for (final row in rows)
        if (row is Map<String, dynamic>)
          if (plexItem(row) case final item?)
            MediaServerLibraryItem.fromJson(item),
    ];
    final total = (container as Map)['totalSize'];
    final more = total is num
        ? offset + rows.length < total
        : rows.length >= _pageSize;
    return MediaServerLibraryPage(
      items,
      rows.isNotEmpty && more ? offset + rows.length : null,
    );
  }

  Future<bool> _isShowSection(
    MediaServerAccount account,
    String section,
    Future<void> Function()? authorize,
  ) async {
    final data = await _request.call(
      account,
      'library/sections',
      operation: 'sections',
      authorize: authorize,
    );
    final rows = (data['MediaContainer'] as Map?)?['Directory'];
    return rows is List &&
        rows.any(
          (row) =>
              row is Map &&
              plexNumericId(row['key']) == section &&
              row['type'] == 'show',
        );
  }

  Future<MediaServerLibraryItem> libraryItem(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) async {
    final item = plexItem(
      await _media.metadata(account, itemId, authorize: authorize),
    );
    if (item == null) {
      throw const MediaServerException('The server returned a different item.');
    }
    return MediaServerLibraryItem.fromJson(item);
  }

  Future<Uint8List?> libraryImage(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) async {
    final id = plexNumericId(itemId);
    if (id == null) {
      throw const MediaServerException(
        'The server returned an invalid item identifier.',
      );
    }
    return _request.image(account, 'photo/:/transcode', {
      'url': '/library/metadata/$id/thumb',
      'width': '360',
      'height': '540',
      'minSize': '1',
      'upscale': '1',
    }, authorize: authorize);
  }
}
