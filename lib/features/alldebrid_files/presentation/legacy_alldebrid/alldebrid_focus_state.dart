import 'package:flutter/material.dart';

class AllDebridFocusState {
  final FocusNode searchFocusNode = FocusNode();

  final FocusNode searchClearFocusNode = FocusNode();

  final FocusNode fileSearchFocusNode = FocusNode();

  final ScrollController scrollController = ScrollController();

  final FocusNode backButtonFocusNode = FocusNode();

  final FocusNode deleteButtonFocusNode = FocusNode();

  final FocusNode toolbarSearchFocusNode = FocusNode();

  VoidCallback? tvContentFocusHandler;

  // TV: focus the first magnet card when the user moves focus into content.
  bool shouldFocusOnLoad = false;

  final FocusNode firstItemFocusNode = FocusNode(debugLabel: 'ad-first-item');
}
