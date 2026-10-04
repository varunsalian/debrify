import 'dart:async';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_board_types.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:flutter/material.dart';

abstract class SpotlightBoardWidgetView {
  String get animationStyle;
  bool get animationsEnabled;
  double get cardTrailerVolume;
  bool get dpad;
  bool get expandFocusedCard;
  bool get forceCardParallax;
  List<StremioMeta> get hero;
  StremioAddon? get heroAddon;
  FocusNode get heroNode;
  bool get largeScreenInteractions;
  void Function(String? art, Color? tint)? get onAmbient;
  void Function(StremioMeta item)? get onDwell;
  VoidCallback? get onExitTop;
  void Function(StremioMeta, StremioAddon) get onHeroOpen;
  void Function(int row)? get onLoadMoreRow;
  Future<bool> Function()? get onLoadMoreShelves;
  VoidCallback? get onTrailerStop;
  bool get paintBackground;
  bool get pendingShelves;
  List<SpotlightShelf> get sections;
  bool get shelvesOnly;
  bool get showCardTitlesAndRatings;
  Widget? get trailer;
  bool get trailersEnabled;
  Color Function(AppTheme) get groundOf;
  Color Function(AppTheme) get groundLowOf;
  double get leftThirdBusy;

  bool metadataArtworkPending(MetadataCategory category);
  bool usesMetadataProvider(MetadataCategory category);
  MetadataPreferences get metadataPreferences;
  StremioMeta? get heroPresentation;
  StremioMeta? get originalMetadata;
  Future<void> preloadMetadata(
    List<StremioMeta> items,
    Future<void> Function(StremioMeta, MetadataPreferences) warmArtwork,
  );
  void refreshMetadataPresentation();
}

class SpotlightBoardDependencies {
  // TEMP(spotlight_board): borrowed State callbacks until their planned step.

  final SpotlightBoardWidgetView view;
  final SpotlightBoardOwners owners;
  final BuildContext Function() context;
  final bool Function() mounted;
  final void Function(VoidCallback) setState;
  final ImageProvider Function(String) heroWarmupProvider;
  SpotlightBoardSections? _sections;
  SpotlightBoardSections get sections => _sections!;
  void bindSections(SpotlightBoardSections value) => _sections = value;
  SpotlightBoardDependencies(
    this.view,
    this.owners,
    this.context,
    this.mounted,
    this.setState,
    this.heroWarmupProvider,
  );
}
