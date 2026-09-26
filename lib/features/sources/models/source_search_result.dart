import '../../../models/torrent.dart';
import '../../../services/iptv_source_search.dart';
import '../../../models/addon_search_status.dart';

class SourceSearchResult {
  final List<Torrent> torrents;
  final List<AddonSearchStatus> addonStatuses;
  final List<IptvSourceResult> iptv;

  SourceSearchResult({
    List<Torrent> torrents = const [],
    List<AddonSearchStatus> addonStatuses = const [],
    List<IptvSourceResult> iptv = const [],
  }) : torrents = List.unmodifiable(torrents),
       addonStatuses = List.unmodifiable(addonStatuses),
       iptv = List.unmodifiable(iptv);
}
