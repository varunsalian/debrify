import 'package:debrify/models/torbox_torrent.dart';
import 'package:flutter/material.dart';

class TorboxTorrentSearchState {
  // Torrent-level search state (for root torrent list)
  bool isTorrentSearchActive = false;

  final TextEditingController torrentSearchController = TextEditingController();

  String torrentSearchQuery = '';

  List<TorboxTorrent> allTorrentsForSearch = [];

  bool isLoadingTorrentSearch = false;

  // Whether TorBox is hidden from bottom-nav. In selectSourceMode we use this to
  // decide whether to restrict searches to queries matching the show title.
  bool hiddenFromNav = false;
}
