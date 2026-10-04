import 'dart:async';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_parts.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';

class MergedDetailDependencies {
  late final MergedDetailParts parts;
  final BuildContext Function() context;
  final bool Function() mounted;
  final void Function(VoidCallback) setState;
  final StremioMeta Function() item;
  final StremioAddon Function() addon;
  final bool Function() isTelevision;
  final bool Function() showQuickPlay;
  final bool Function() isTraktSource;
  final bool Function() isMdblistSource;
  final Future<void> Function(
    ({bool started, int season, int episode})? promised,
  )
  Function()
  onResume;
  final Future<void> Function()? Function() onRewatch;
  final Future<({bool started, int? season, int? episode})> Function()?
  Function()
  resumeInfoLoader;
  final VoidCallback? Function() onBrowse;
  final void Function(AdvancedSearchSelection selection)? Function()
  onItemSelected;
  final Future<void> Function(AdvancedSearchSelection selection)? Function()
  onQuickPlay;
  final Future<void> Function(
    ({bool started, int season, int episode})? promised,
  )?
  Function()
  onBrowsePrimaryEpisodeSources;
  final int Function(StremioMeta show)? Function() boundSourceCount;
  final Future<void> Function(StremioMeta show)? Function() onSelectSource;
  final List<TraktMenuOption> Function() traktMenuOptions;
  final List<TraktMenuOption> Function(TraktTitleStatus? status)? Function()
  traktMenuBuilder;
  final Future<void> Function(TraktItemMenuAction action)? Function()
  onTraktAction;
  final Future<TraktTitleStatus?> Function()? Function() traktStatusLoader;
  final List<SimklMenuOption> Function() simklMenuOptions;
  final List<SimklMenuOption> Function(SimklTitleStatus? status)? Function()
  simklMenuBuilder;
  final Future<void> Function(SimklItemMenuAction action)? Function()
  onSimklAction;
  final Future<SimklTitleStatus?> Function()? Function() simklStatusLoader;
  final List<MdblistMenuOption> Function() mdblistMenuOptions;
  final List<MdblistMenuOption> Function(MdblistTitleStatus? status)? Function()
  mdblistMenuBuilder;
  final Future<void> Function(MdblistItemMenuAction action)? Function()
  onMdblistAction;
  final Future<MdblistTitleStatus?> Function()? Function() mdblistStatusLoader;
  final Future<void> Function(int rating)? Function() onTraktRate;
  final Future<void> Function(int rating)? Function() onSimklRate;
  final Future<void> Function(int rating)? Function() onMdblistRate;
  final Future<List<StremioMeta>> Function()? Function() recommendationsLoader;
  final void Function(StremioMeta recommendation)? Function()
  onRecommendationTap;
  final Future<StremioMeta?> Function(String imdbId, String type)? Function()
  metaEnricher;
  final String? Function() heroTag;
  final int? Function() initialSeason;
  final int? Function() initialEpisode;
  final Future<List<TraktSeason>> Function()? Function() seasonsLoader;
  final Future<void> Function(TraktEpisode episode)? Function() onPlayEpisode;
  final Future<Map<String, double>> Function()? Function() watchProgressLoader;
  final bool Function() isMovie;
  final StremioMeta Function() presentedItem;
  final void Function() refreshAfterPlayback;
  final String Function() style;
  final MetadataPreferences Function() metadataPreferences;
  final VoidCallback refreshMetadataPresentation;
  MergedDetailDependencies({
    required this.context,
    required this.mounted,
    required this.setState,
    required this.item,
    required this.addon,
    required this.isTelevision,
    required this.showQuickPlay,
    required this.isTraktSource,
    required this.isMdblistSource,
    required this.onResume,
    required this.onRewatch,
    required this.resumeInfoLoader,
    required this.onBrowse,
    required this.onItemSelected,
    required this.onQuickPlay,
    required this.onBrowsePrimaryEpisodeSources,
    required this.boundSourceCount,
    required this.onSelectSource,
    required this.traktMenuOptions,
    required this.traktMenuBuilder,
    required this.onTraktAction,
    required this.traktStatusLoader,
    required this.simklMenuOptions,
    required this.simklMenuBuilder,
    required this.onSimklAction,
    required this.simklStatusLoader,
    required this.mdblistMenuOptions,
    required this.mdblistMenuBuilder,
    required this.onMdblistAction,
    required this.mdblistStatusLoader,
    required this.onTraktRate,
    required this.onSimklRate,
    required this.onMdblistRate,
    required this.recommendationsLoader,
    required this.onRecommendationTap,
    required this.metaEnricher,
    required this.heroTag,
    required this.initialSeason,
    required this.initialEpisode,
    required this.seasonsLoader,
    required this.onPlayEpisode,
    required this.watchProgressLoader,
    required this.isMovie,
    required this.presentedItem,
    required this.refreshAfterPlayback,
    required this.style,
    required this.metadataPreferences,
    required this.refreshMetadataPresentation,
  });
}
