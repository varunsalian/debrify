import 'package:flutter/material.dart';

class EpisodesPanelResources {
  final List<FocusNode> episodeFocusNodes = [];

  final ScrollController episodeScrollController = ScrollController();

  final FocusNode episodeBackButtonFocusNode = FocusNode(
    debugLabel: 'catalog-ep-back',
  );

  final FocusNode episodeSeasonDropdownFocusNode = FocusNode(
    debugLabel: 'catalog-ep-season',
  );

  // Retry button in the "couldn't load episodes" panel, so the back button can
  // hand focus to it (the season dropdown / episode list aren't in the tree
  // in that state).
  final FocusNode episodeRetryFocusNode = FocusNode(
    debugLabel: 'catalog-ep-retry',
  );
}
