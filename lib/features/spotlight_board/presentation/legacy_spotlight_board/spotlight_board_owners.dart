import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_constants_state.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_hero_state.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_navigation_state.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_scroll_state.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_selection_state.dart';

class SpotlightBoardOwners {
  final SpotlightBoardSelectionState selection = SpotlightBoardSelectionState();
  final SpotlightBoardScrollState scroll = SpotlightBoardScrollState();
  final SpotlightBoardHeroState hero = SpotlightBoardHeroState();
  final SpotlightBoardConstantsState constants = SpotlightBoardConstantsState();
  final SpotlightBoardNavigationState navigation =
      SpotlightBoardNavigationState();
}
