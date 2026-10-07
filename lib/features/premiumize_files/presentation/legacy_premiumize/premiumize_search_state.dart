import 'dart:async';

import 'package:debrify/models/premiumize_folder_item.dart';
import 'package:flutter/material.dart';

class PremiumizeSearchState {
  // Search state. At root this runs a server-side cloud search (debounced);
  // inside a folder it filters the currently-loaded items locally.
  bool isSearchActive = false;

  bool isSearching = false; // a cloud search request is in flight

  Timer? searchDebounce;

  final TextEditingController searchController = TextEditingController();

  List<PremiumizeFolderItem> searchResults = [];
}
