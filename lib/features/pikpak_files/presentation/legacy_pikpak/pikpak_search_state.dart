import 'package:debrify/features/pikpak_files/models/pikpak_search_result.dart';
import 'package:flutter/material.dart';

// Search state (for folder browsing mode)
class PikpakSearchState {
  bool isSearchActive = false;

  final TextEditingController searchController = TextEditingController();

  final FocusNode searchFocusNode = FocusNode(debugLabel: 'pikpak-search');

  final FocusNode searchButtonFocusNode = FocusNode(
    debugLabel: 'pikpak-search-button',
  );

  final FocusNode searchClearFocusNode = FocusNode(
    debugLabel: 'pikpak-search-clear',
  );

  List<PikPakSearchResult> searchResults = [];
}
