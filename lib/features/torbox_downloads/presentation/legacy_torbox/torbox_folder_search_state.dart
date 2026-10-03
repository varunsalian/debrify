import 'package:debrify/features/torbox_downloads/models/torbox_search_result.dart';
import 'package:flutter/material.dart';

class TorboxFolderSearchState {
  bool isSearchActive = false;

  final TextEditingController searchController = TextEditingController();

  List<TorboxSearchResult> searchResults = [];
}
