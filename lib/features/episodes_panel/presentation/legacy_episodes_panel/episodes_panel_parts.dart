import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_resources.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_services.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';

class EpisodesPanelParts {
  final EpisodesPanelAuth auth;
  final EpisodesPanelProgress progress;
  final EpisodesPanelResources resources;
  final EpisodesPanelServices services;
  final EpisodesPanelViewState viewState;
  EpisodesPanelParts(
    EpisodesPanelDeps deps, {
    required this.services,
    required this.viewState,
    required this.progress,
    required this.auth,
    required this.resources,
  });
}
