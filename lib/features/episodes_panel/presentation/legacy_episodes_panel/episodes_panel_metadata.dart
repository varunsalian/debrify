import 'dart:async';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';
import 'package:debrify/services/metadata_episode_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';

class EpisodesPanelMetadata {
  final EpisodesPanelDeps _deps;
  EpisodesPanelMetadata(this._deps);
  EpisodesPanelViewState get _s => _deps.parts.viewState;
  EpisodesPanelAuth get _a => _deps.parts.auth;
  bool get mounted => _deps.mounted();

  final episodeMetadataBaselines = <int, TraktSeason>{};

  int episodeMetadataGeneration = 0;

  void episodePolicyChanged() {
    episodeMetadataGeneration++;
    if (!mounted) return;
    _deps.setState(() {
      _s.episodeSeasons = [
        for (final season in _s.episodeSeasons)
          episodeMetadataBaselines[season.number] ?? season,
      ];
      refreshMetadataLanding();
      // Presentation changes preserve the season view and its focus/scroll.
    });
    unawaited(loadSelectedEpisodeMetadata());
  }

  void refreshMetadataLanding() {
    final landing = _s.landing;
    if (landing == null) return;
    final season = _s.episodeSeasons
        .where((s) => s.number == landing.season)
        .firstOrNull;
    _s.landing = season?.episodes
        .where((e) => e.number == landing.number)
        .firstOrNull;
  }

  Future<void> loadSelectedEpisodeMetadata() async {
    if (_a.isDirectSource || _s.episodeSeasons.isEmpty) return;
    final generation = _s.episodeModeGeneration;
    final selected = _s.selectedSeasonNumber;
    final index = _s.episodeSeasons.indexWhere((s) => s.number == selected);
    if (index < 0) return;
    final original = episodeMetadataBaselines.putIfAbsent(
      selected,
      () => _s.episodeSeasons[index],
    );
    final metadataGeneration = ++episodeMetadataGeneration;
    final scope = ProfileRuntime.scope.value;
    try {
      final result = await MetadataEpisodeService.instance.present(
        _deps.show(),
        original,
      );
      if (!mounted ||
          generation != _s.episodeModeGeneration ||
          selected != _s.selectedSeasonNumber ||
          scope != ProfileRuntime.scope.value ||
          metadataGeneration != episodeMetadataGeneration ||
          identical(result, _s.episodeSeasons[index])) {
        return;
      }
      _deps.setState(() {
        _s.episodeSeasons = [
          for (final s in _s.episodeSeasons) s.number == selected ? result : s,
        ];
        refreshMetadataLanding();
        // Presentation changes preserve the season view and its focus/scroll.
      });
    } catch (_) {}
  }
}
