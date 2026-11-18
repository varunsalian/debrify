import '../../../models/addon_search_status.dart';
import '../../../models/iptv_source_result.dart';
import '../../../models/torrent.dart';
import 'webdav_source_status.dart';

class SourceSearchResult {
  final List<Torrent> torrents;
  final List<AddonSearchStatus> addonStatuses;
  final List<IptvSourceResult> iptv;
  final List<WebDavSourceStatus> webDav;

  SourceSearchResult({
    List<Torrent> torrents = const [],
    List<AddonSearchStatus> addonStatuses = const [],
    List<IptvSourceResult> iptv = const [],
    List<WebDavSourceStatus> webDav = const [],
  }) : torrents = List.unmodifiable(torrents),
       addonStatuses = List.unmodifiable(addonStatuses),
       iptv = List.unmodifiable(iptv),
       webDav = List.unmodifiable(webDav);
}
