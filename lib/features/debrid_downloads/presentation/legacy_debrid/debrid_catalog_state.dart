import 'package:debrify/features/debrid_downloads/models/debrid_downloads_view.dart';
import 'package:debrify/models/rd_torrent.dart';

class DebridCatalogState {
  DebridDownloadsView selectedView = DebridDownloadsView.torrents;

  final List<RDTorrent> torrents = [];

  bool isLoadingTorrents = false;

  bool isLoadingMoreTorrents = false;

  String torrentErrorMessage = '';

  int torrentPage = 1;

  bool hasMoreTorrents = true;

  String? apiKey;

  static const int limit = 50;
}
