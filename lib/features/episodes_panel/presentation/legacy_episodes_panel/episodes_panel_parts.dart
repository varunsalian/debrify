import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_enrichment.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_metadata.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_mode.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_resources.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_seasons.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_services.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_watched_actions.dart';

class EpisodesPanelParts {
  final EpisodesPanelAuth auth;
  final EpisodesPanelEnrichment enrichment;
  final EpisodesPanelMetadata metadata;
  final EpisodesPanelMode mode;
  final EpisodesPanelProgress progress;
  final EpisodesPanelResources resources;
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
  }) : enrichment = EpisodesPanelEnrichment(deps),
       metadata = EpisodesPanelMetadata(deps),
       mode = EpisodesPanelMode(deps),
       seasons = EpisodesPanelSeasons(deps),
       watchedActions = EpisodesPanelWatchedActions(deps);
}
