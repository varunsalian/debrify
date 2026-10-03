import 'package:debrify/models/torbox_torrent.dart';
import 'package:flutter/material.dart';

class TorboxTorrentSearchState {
  bool isTorrentSearchActive = false;

  final TextEditingController torrentSearchController = TextEditingController();

  String torrentSearchQuery = '';

  List<TorboxTorrent> allTorrentsForSearch = [];

  bool isLoadingTorrentSearch = false;

  bool hiddenFromNav = false;
}
