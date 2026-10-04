import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_classic_chrome.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_classic_content.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_compact_layout.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_enrichment.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_episode_options.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_metadata.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_mode.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_navigation.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_resources.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_root_layout.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_season_options.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_seasons.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_services.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_watched_actions.dart';

class EpisodesPanelParts {
  final EpisodesPanelAuth auth;
  final EpisodesPanelClassicChrome classicChrome;
  final EpisodesPanelClassicContent classicContent;
  final EpisodesPanelCompactLayout compactLayout;
  final EpisodesPanelEnrichment enrichment;
  final EpisodesPanelEpisodeOptions episodeOptions;
  final EpisodesPanelMetadata metadata;
  final EpisodesPanelMode mode;
  final EpisodesPanelNavigation navigation;
  final EpisodesPanelProgress progress;
  final EpisodesPanelResources resources;
  final EpisodesPanelRootLayout rootLayout;
  final EpisodesPanelSeasonOptions seasonOptions;
  final EpisodesPanelSeasons seasons;
  final EpisodesPanelServices services;
  final EpisodesPanelViewState viewState;
  final EpisodesPanelWatchedActions watchedActions;
  EpisodesPanelParts(
    EpisodesPanelDeps deps, {
    required this.services,
    required this.viewState,
    required this.progress,
    required this.auth,
    required this.resources,
  }) : classicChrome = EpisodesPanelClassicChrome(deps),
       classicContent = EpisodesPanelClassicContent(deps),
       compactLayout = EpisodesPanelCompactLayout(deps),
       enrichment = EpisodesPanelEnrichment(deps),
       episodeOptions = EpisodesPanelEpisodeOptions(deps),
       metadata = EpisodesPanelMetadata(deps),
       mode = EpisodesPanelMode(deps),
       navigation = EpisodesPanelNavigation(deps),
       rootLayout = EpisodesPanelRootLayout(deps),
       seasonOptions = EpisodesPanelSeasonOptions(deps),
       seasons = EpisodesPanelSeasons(deps),
       watchedActions = EpisodesPanelWatchedActions(deps);
}
