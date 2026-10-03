import 'package:debrify/models/rd_torrent.dart';
import 'package:flutter/material.dart';

class DebridTorrentSearchState {
  bool isTorrentSearchActive = false;

  final TextEditingController torrentSearchController = TextEditingController();

  List<RDTorrent> allTorrentsForSearch = [];

  bool isLoadingSearch = false;

  String torrentSearchQuery = '';

  bool hiddenFromNav = false;
}
