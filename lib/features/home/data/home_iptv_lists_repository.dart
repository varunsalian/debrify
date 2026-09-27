import '../../../models/home_preferences.dart';
import '../../../models/iptv_playlist.dart';
import '../../../services/home_list_rows.dart' show HomeExtraRowIds;
import '../models/home_iptv_list.dart';

typedef HomeIptvListsRead = ({bool hasWantedLists, List<HomeIptvList> rows});

/// Reads extras directly on each load; the concurrently loaded board is not an
/// authoritative source for cold-start opt-ins. List/channel order stays stored.
class HomeIptvListsRepository {
  const HomeIptvListsRepository({
    required Future<List<HomeExtraRow>> Function() extras,
    required Future<List<HomeIptvListMeta>> Function() lists,
    required Future<Map<String, Map<String, dynamic>>> Function(String)
    channels,
    required Map<String, String> Function(Map<String, dynamic>) headers,
    required String favoritesListId,
  }) : _extras = extras,
       _lists = lists,
       _channels = channels,
       _headers = headers,
       _favoritesListId = favoritesListId;

  final Future<List<HomeExtraRow>> Function() _extras;
  final Future<List<HomeIptvListMeta>> Function() _lists;
  final Future<Map<String, Map<String, dynamic>>> Function(String) _channels;
  final Map<String, String> Function(Map<String, dynamic>) _headers;
  final String _favoritesListId;

  Future<HomeIptvListsRead?> read({required bool Function() isCurrent}) async {
    if (!isCurrent()) return null;
    final extras = await _extras();
    if (!isCurrent()) return null;
    final wanted = <String>{
      for (final row in extras)
        if (HomeExtraRowIds.iptvListId(row.id) case final String id) id,
    }..remove(_favoritesListId);
    if (wanted.isEmpty) {
      return (hasWantedLists: false, rows: const <HomeIptvList>[]);
    }
    final metas = await _lists();
    if (!isCurrent()) return null;
    final rows = <HomeIptvList>[];
    for (final meta in metas) {
      if (!wanted.contains(meta.id) || meta.isFavorites) continue;
      final map = await _channels(meta.id);
      if (!isCurrent()) return null;
      final channels = <IptvChannel>[];
      map.forEach((url, m) {
        final name = (m['name'] as String?) ?? '';
        final logo = (m['logoUrl'] as String?) ?? '';
        final group = (m['group'] as String?) ?? '';
        channels.add(
          IptvChannel(
            name: name.isEmpty ? 'Unknown Channel' : name,
            url: url,
            logoUrl: logo.isEmpty ? null : logo,
            group: group.isEmpty ? null : group,
            channelNumber: (m['channelNumber'] as num?)?.toInt(),
            duration: (m['duration'] as num?)?.toInt() ?? -1,
            contentType: m['contentType'] as String?,
            attributes: Map.unmodifiable({
              if ((m['playlistId'] as String?)?.isNotEmpty ?? false)
                'list_playlist_id': m['playlistId'] as String,
            }),
            httpHeaders: Map.unmodifiable(_headers(m)),
          ),
        );
      });
      if (channels.isEmpty) continue;
      rows.add(
        HomeIptvList(listId: meta.id, title: meta.title, channels: channels),
      );
    }
    return (hasWantedLists: true, rows: List<HomeIptvList>.unmodifiable(rows));
  }
}
