import 'package:debrify/features/debrid_downloads/models/rd_search_result.dart';
import 'package:flutter/material.dart';

class DebridFolderSearchState {
  bool isSearchActive = false;

  final TextEditingController searchController = TextEditingController();

  List<RDSearchResult> searchResults = [];
}
