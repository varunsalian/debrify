import 'package:debrify/features/torbox_downloads/presentation/torbox_downloads_view.dart';
import 'package:debrify/models/torbox_torrent.dart';

class TorboxCatalogState {
  TorboxDownloadsView selectedView = TorboxDownloadsView.torrents;

  final List<TorboxTorrent> torrents = [];

  bool isLoading = false;

  bool isLoadingMore = false;

  bool hasMore = true;

  bool initialLoad = true;

  int offset = 0;

  String errorMessage = '';

  String? apiKey;

  TorboxTorrent? pendingInitialTorrent;

  bool initialActionHandled = false;

  static const int limit = 50;
}
