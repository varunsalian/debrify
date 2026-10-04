import 'package:debrify/features/playlist_content/models/playlist_content_search_result.dart';
import 'package:flutter/material.dart';

class PlaylistContentSearchState {
  // Search state (for Raw and Sort A-Z modes)
  bool isSearchActive = false;

  final TextEditingController searchController = TextEditingController();

  List<PlaylistContentSearchResult> searchResults = [];
}
