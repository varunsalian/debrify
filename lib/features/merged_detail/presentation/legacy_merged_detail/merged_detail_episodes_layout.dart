import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_focus_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_playback_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_rail_layout.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_state.dart';
import 'package:debrify/features/merged_detail/presentation/merged_detail_palette.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:flutter/material.dart';

class MergedDetailEpisodesLayout {
  final MergedDetailDependencies _deps;
  MergedDetailEpisodesLayout(this._deps);
  bool get mounted => _deps.mounted();
  void Function(VoidCallback) get setState => _deps.setState;
  MergedDetailFocusState get _f => _deps.parts.focusState;
  MergedDetailPlaybackActions get _pl => _deps.parts.playbackActions;
  MergedDetailRailLayout get _ri => _deps.parts.railLayout;
  MergedDetailResumeActions get _ra => _deps.parts.resumeActions;
  MergedDetailResumeState get _r => _deps.parts.resumeState;

  // ── Bodies ────────────────────────────────────────────────────────────────

  /// [contentBuilder] non-null hands the arrangement to an alternate layout;
  /// the engine (loading, watch merge, enrichment, playback, options) is
  /// identical either way.
  Widget buildEpisodesPanel({
    Widget Function(BuildContext, EpisodesPanelView)? contentBuilder,
  }) {
    return EpisodesPanel(
      key: _f.episodesPanelKey,
      contentBuilder: contentBuilder,
      show: _deps.item(),
      addon: _deps.addon(),
      initialSeason: _deps.initialSeason(),
      initialEpisode: _deps.initialEpisode(),
      isTelevision: _deps.isTelevision(),
      // Match the standalone `_openEpisodes` flow, which does NOT pass
      // showQuickPlay (defaults true) — episode tiles keep quick-play even for
      // PikPak-only. Only the hero Resume (≙ detail "Play") is PikPak-gated.
      showQuickPlay: true,
      isTraktSource: _deps.isTraktSource(),
      isMdblistSource: _deps.isMdblistSource(),
      // The host pushes Sources on top of this page, like the hero's own
      // "browse sources", so Back from Sources returns to this season's
      // episodes; didPopNext then refreshes the ticks. Closing the page first
      // sent Back all the way to Home.
      onItemSelected: _deps.onItemSelected(),
      // Quick-play deliberately does NOT pop: the host pushes the player on
      // top of this screen (same as the hero Resume), so playback pops back to
      // the episode list here — didPopNext then refreshes the ticks.
      onQuickPlay: _deps.onQuickPlay() == null ? null : _pl.quickPlayEpisode,
      boundSourceCount: _deps.boundSourceCount(),
      onSelectSource: _deps.onSelectSource(),
      showChrome: false,
      compact: true,
      // Null when neither Play nor the source pill exists (no holder for the
      // node) — the episode row then leaves LEFT to directional traversal
      // instead of swallowing it as a dead key.
      onFocusLeftEdge: (_deps.showQuickPlay() || _deps.onSelectSource() != null)
          ? () => _f.leftEntryFocusNode.requestFocus()
          : null,
      onBack: () => Navigator.of(_deps.context()).maybePop(),
      // Direct-source mode (Xtream IPTV series) — pass-throughs.
      seasonsLoader: _deps.seasonsLoader(),
      onPlayEpisode: _deps.onPlayEpisode() == null
          ? null
          : _pl.playDirectEpisode,
      watchProgressLoader: _deps.watchProgressLoader(),
      onNextEpisodeChanged: _ra.onNextEpisodeChanged,
      onSeriesCompletedChanged: (completed) {
        if (mounted && completed != _r.seriesDone) {
          setState(() => _r.seriesDone = completed);
        }
      },
    );
  }

  void openDetailsSheet() {
    showModalBottomSheet<void>(
      context: _deps.context(),
      backgroundColor: MergedDetailPalette.bg,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // Quick actions already shown in the strip; the sheet holds the rest.
            children: _ri.sideRailSections(),
          ),
        ),
      ),
    );
  }
}
