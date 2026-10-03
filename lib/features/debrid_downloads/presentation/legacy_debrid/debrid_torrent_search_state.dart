import 'package:debrify/models/rd_torrent.dart';
import 'package:flutter/material.dart';

class DebridTorrentSearchState {
  // Torrent list search state
  bool isTorrentSearchActive = false;

  final TextEditingController torrentSearchController = TextEditingController();

  List<RDTorrent> allTorrentsForSearch = [];

  bool isLoadingSearch = false;

  String torrentSearchQuery = '';

  // Whether RD is hidden from bottom-nav. In selectSourceMode we use this to
  // decide whether to restrict searches to queries matching the show title.
  bool hiddenFromNav = false;
}
