import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_tuner.dart';
import 'package:flutter/material.dart';

class StremioTvFocusState {
  final List<FocusNode> rowFocusNodes = [];

  int focusedIndex = 0;

  /// Imperative handle to the tuner so header→dial focus jumps scroll the
  /// target card into view before focusing it — a recycled off-screen card
  /// can't otherwise receive focus (silent no-op), which stranded focus on the
  /// header search box after a long channel hold.
  final StremioTvTunerController tunerController = StremioTvTunerController();
  // Header buttons
  final FocusNode searchBtnFocusNode = FocusNode(debugLabel: 'searchBtn');

  final FocusNode providerFocusNode = FocusNode(debugLabel: 'providerBtn');

  final FocusNode menuFocusNode = FocusNode(debugLabel: 'menuBtn');

  final FocusNode submenuFocusNode = FocusNode(debugLabel: 'localCatalogs');

  final MenuController providerMenuController = MenuController();

  final MenuController menuController = MenuController();
  // Search
  final TextEditingController searchController = TextEditingController();

  final FocusNode searchFocusNode = FocusNode();

  String searchQuery = '';

  bool showSearchField = false;
  // TV content focus handler (stored for proper unregistration)
  VoidCallback? tvContentFocusHandler;
}
