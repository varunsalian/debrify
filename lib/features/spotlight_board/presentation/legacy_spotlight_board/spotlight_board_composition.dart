import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_ambient.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_cadence.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_focus.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_hero_art.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_hero_warmup.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_movement.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_selection.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_board_metrics.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_board_types.dart';
import 'package:flutter/material.dart';

class SpotlightBoardSections {
  final SpotlightBoardSelection selection;
  final SpotlightBoardHeroArt heroArt;
  final SpotlightBoardHeroWarmup heroWarmup;
  final SpotlightBoardCadence cadence;
  final SpotlightBoardAmbient ambient;
  final SpotlightBoardMovement movement;
  final SpotlightBoardFocus focus;
  SpotlightBoardSections(SpotlightBoardDependencies deps)
    : selection = SpotlightBoardSelection(deps),
      heroArt = SpotlightBoardHeroArt(deps),
      heroWarmup = SpotlightBoardHeroWarmup(deps),
      cadence = SpotlightBoardCadence(deps),
      ambient = SpotlightBoardAmbient(deps),
      movement = SpotlightBoardMovement(deps),
      focus = SpotlightBoardFocus(deps);
}

SpotlightBoardSections createSpotlightBoardSections({
  required SpotlightBoardWidgetView view,
  required SpotlightBoardOwners owners,
  required BuildContext Function() context,
  required bool Function() mounted,
  required void Function(VoidCallback) setState,
  required ImageProvider Function(String) heroWarmupProvider,
  required double Function(SpotlightShelf section, SpotlightBoardMetrics m)
  shelfExtent,
}) {
  final deps = SpotlightBoardDependencies(
    view,
    owners,
    context,
    mounted,
    setState,
    heroWarmupProvider,
    shelfExtent,
  );
  final sections = SpotlightBoardSections(deps);
  deps.bindSections(sections);
  return sections;
}
