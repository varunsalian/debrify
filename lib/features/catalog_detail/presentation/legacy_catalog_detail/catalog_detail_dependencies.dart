import 'dart:async';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_parts.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/play_loader_art.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';

class CatalogDetailDependencies {
  late final CatalogDetailParts parts;
  final BuildContext Function() context;
  final bool Function() mounted;
  final StremioMeta Function() presentedItem;
  final MetadataPreferences Function() metadataPreferences;
  final StremioMeta Function() item;
  final bool Function() isTelevision;
  final bool Function() showQuickPlay;
  final VoidCallback Function() onPlay;
  final VoidCallback? Function() onRewatch;
  final ValueChanged<PlayLoaderArt>? Function() onLoaderArt;
  final Future<({bool started, int? season, int? episode})> Function()?
  Function()
  resumeInfoLoader;
  final VoidCallback Function() onBrowse;
  final Future<void> Function()? Function() onBrowsePrimaryEpisodeSources;
  final bool Function() enablePrimarySourcesHold;
  final List<TraktMenuOption> Function() traktMenuOptions;
  final void Function(TraktItemMenuAction action)? Function() onTraktAction;
  final List<SimklMenuOption> Function() simklMenuOptions;
  final void Function(SimklItemMenuAction action)? Function() onSimklAction;
  final List<MdblistMenuOption> Function() mdblistMenuOptions;
  final void Function(MdblistItemMenuAction action)? Function() onMdblistAction;
  final Future<SimklTitleStatus?> Function()? Function() simklStatusLoader;
  final Future<List<StremioMeta>> Function()? Function() recommendationsLoader;
  final void Function(StremioMeta recommendation)? Function()
  onRecommendationTap;
  final Future<StremioMeta?> Function(String imdbId, String type)? Function()
  metaEnricher;
  final void Function(VoidCallback) setState;
  final VoidCallback refreshMetadataPresentation;
  final AnimationController Function() revealController;
  final bool Function() _readHasBoundSource;
  final void Function(bool) writeHasBoundSource;
  AnimationController get revealCtrl => revealController();
  bool get hasBoundSource => _readHasBoundSource();
  set hasBoundSource(bool value) => writeHasBoundSource(value);
  CatalogDetailDependencies({
    required this.context,
    required this.mounted,
    required this.presentedItem,
    required this.metadataPreferences,
    required this.item,
    required this.isTelevision,
    required this.showQuickPlay,
    required this.onPlay,
    required this.onRewatch,
    required this.onLoaderArt,
    required this.resumeInfoLoader,
    required this.onBrowse,
    required this.onBrowsePrimaryEpisodeSources,
    required this.enablePrimarySourcesHold,
    required this.traktMenuOptions,
    required this.onTraktAction,
    required this.simklMenuOptions,
    required this.onSimklAction,
    required this.mdblistMenuOptions,
    required this.onMdblistAction,
    required this.simklStatusLoader,
    required this.recommendationsLoader,
    required this.onRecommendationTap,
    required this.metaEnricher,
    required this.setState,
    required this.refreshMetadataPresentation,
    required this.revealController,
    required this.writeHasBoundSource,
    required bool Function() hasBoundSource,
  }) : _readHasBoundSource = hasBoundSource;
}
