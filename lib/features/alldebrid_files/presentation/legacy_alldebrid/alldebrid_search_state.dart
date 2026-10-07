import 'package:flutter/material.dart';

class AllDebridSearchState {
  // Root search.
  bool searchActive = false;

  String searchQuery = '';

  final TextEditingController searchController = TextEditingController();

  // In-folder (files) search.
  bool fileSearchActive = false;

  String fileSearchQuery = '';

  final TextEditingController fileSearchController = TextEditingController();
}
