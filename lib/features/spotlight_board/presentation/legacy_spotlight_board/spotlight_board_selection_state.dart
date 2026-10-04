import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_card.dart';
import 'package:flutter/material.dart';

class SpotlightBoardSelectionState {
  final Set<SpotlightBoardCardState> visibleCards = {};

  final Set<BuildContext> scrollingSources = {};

  Size? selectionViewport;

  Object? scrollRowId;

  SpotlightBoardCardState? selectedCard;

  bool largeCardInteractions = false;

  bool selectionQueued = false;

  bool selectionFromScroll = false;

  bool scrollInterruptedPreview = false;
}
