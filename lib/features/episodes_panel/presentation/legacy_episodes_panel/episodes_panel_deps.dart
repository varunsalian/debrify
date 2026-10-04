import 'dart:async';
import 'package:debrify/features/episodes_panel/models/episodes_panel_view.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_parts.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/utils/episode_progress_merge.dart';
import 'package:flutter/material.dart';

class EpisodesPanelDeps {
  late final EpisodesPanelParts parts;
  final BuildContext Function() context;
  final bool Function() mounted;
  final void Function(VoidCallback) setState;
  final Future<void> Function() refreshWatchProgress;
  final StremioMeta Function() show;
  final int? Function() initialSeason;
  final int? Function() initialEpisode;
  final StremioAddon Function() addon;
  final bool Function() isTelevision;
  final bool Function() showQuickPlay;
  final bool Function() isTraktSource;
  final bool Function() isMdblistSource;
  final void Function(AdvancedSearchSelection selection)? Function()
  onItemSelected;
  final void Function(AdvancedSearchSelection selection)? Function()
  onQuickPlay;
  final int Function(StremioMeta show)? Function() boundSourceCount;
  final Future<void> Function(StremioMeta show)? Function() onSelectSource;
  final VoidCallback? Function() onBack;
  final VoidCallback? Function() onBeforeTerminalDispatch;
  final bool Function() showChrome;
  final bool Function() compact;
  final VoidCallback? Function() onFocusLeftEdge;
  final Future<List<TraktSeason>> Function()? Function() seasonsLoader;
  final void Function(TraktEpisode episode)? Function() onPlayEpisode;
  final Future<Map<String, double>> Function()? Function() watchProgressLoader;
  final void Function(EpisodeResumeTarget next, {bool mutation})? Function()
  onNextEpisodeChanged;
  final ValueChanged<bool>? Function() onSeriesCompletedChanged;
  final Widget Function(BuildContext, EpisodesPanelView)? Function()
  contentBuilder;
  // TEMP(episodes_panel): root getter stays in the facade until step 6.
  final bool Function() custom;
  // TEMP(episodes_panel): compact getter stays in the facade until step 6.
  final int Function() currentSeasonIndex;
  EpisodesPanelDeps({
    required this.context,
    required this.mounted,
    required this.setState,
    required this.refreshWatchProgress,
    required this.show,
    required this.initialSeason,
    required this.initialEpisode,
    required this.addon,
    required this.isTelevision,
    required this.showQuickPlay,
    required this.isTraktSource,
    required this.isMdblistSource,
    required this.onItemSelected,
    required this.onQuickPlay,
    required this.boundSourceCount,
    required this.onSelectSource,
    required this.onBack,
    required this.onBeforeTerminalDispatch,
    required this.showChrome,
    required this.compact,
    required this.onFocusLeftEdge,
    required this.seasonsLoader,
    required this.onPlayEpisode,
    required this.watchProgressLoader,
    required this.onNextEpisodeChanged,
    required this.onSeriesCompletedChanged,
    required this.contentBuilder,
    required this.custom,
    required this.currentSeasonIndex,
  });
}
