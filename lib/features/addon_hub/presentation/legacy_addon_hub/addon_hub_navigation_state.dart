import 'package:debrify/features/addon_hub/models/addon_hub_kinds.dart';
import 'package:debrify/features/addon_hub/presentation/addon_hub_row_nav.dart';
import 'package:flutter/material.dart';

class AddonHubNavigationState {
  final TextEditingController searchController = TextEditingController();

  final FocusNode kindFocus = FocusNode(debugLabel: 'hub-kind');

  final FocusNode sourceFocus = FocusNode(debugLabel: 'hub-source');

  final FocusNode typeFocus = FocusNode(debugLabel: 'hub-type');

  final FocusNode addFocus = FocusNode(debugLabel: 'hub-add');

  final FocusNode moreFocus = FocusNode(debugLabel: 'hub-more');

  final FocusNode searchFocus = FocusNode(debugLabel: 'hub-search');

  final FocusNode searchBtnFocus = FocusNode(debugLabel: 'hub-search-btn');

  final FocusNode metadataFocus = FocusNode(
    debugLabel: 'hub-metadata-provider',
  );

  /// Attached to the first focusable of the installed/engine lists (single-focus
  /// cards), so DOWN from the filter bar deterministically lands on item 1.
  final FocusNode firstRowFocus = FocusNode(debugLabel: 'hub-first-row');

  /// One focus node per focusable marketplace row (its primary button). Market
  /// rows have variable buttons (Install / Install+Configure / Configure), so
  /// geometric DOWN is unreliable — vertical moves go through these instead, and
  /// always land on the NEXT row's first button regardless of its layout.
  final AddonHubRowNav marketNav = AddonHubRowNav();

  bool isTv = false;

  AddonHubKind kind = AddonHubKind.addons;

  AddonHubSource source = AddonHubSource.installed;

  String typeFilter = ''; // '' == All

  String search = '';

  bool searchOpen = false;
}
