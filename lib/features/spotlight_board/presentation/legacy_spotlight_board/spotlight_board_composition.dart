import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_ambient.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_cadence.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_hero_art.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_hero_warmup.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:flutter/material.dart';

class SpotlightBoardSections {
  final SpotlightBoardHeroArt heroArt;
  final SpotlightBoardHeroWarmup heroWarmup;
  final SpotlightBoardCadence cadence;
  final SpotlightBoardAmbient ambient;
  SpotlightBoardSections(SpotlightBoardDependencies deps)
    : heroArt = SpotlightBoardHeroArt(deps),
      heroWarmup = SpotlightBoardHeroWarmup(deps),
      cadence = SpotlightBoardCadence(deps),
      ambient = SpotlightBoardAmbient(deps);
}

SpotlightBoardSections createSpotlightBoardSections({
  required SpotlightBoardWidgetView view,
  required SpotlightBoardOwners owners,
  required BuildContext Function() context,
  required bool Function() mounted,
  required void Function(VoidCallback) setState,
  required ImageProvider Function(String) heroWarmupProvider,
}) {
  final deps = SpotlightBoardDependencies(
    view,
    owners,
    context,
    mounted,
    setState,
    heroWarmupProvider,
  );
  final sections = SpotlightBoardSections(deps);
  deps.bindSections(sections);
  return sections;
}
