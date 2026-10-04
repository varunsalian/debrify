import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_focus_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_menus.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_pane_layout.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_playback_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_resume_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_root_layout.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_trailer_actions.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_trailer_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_watchlist_actions.dart';
import 'package:debrify/features/merged_detail/presentation/merged_ghost_button.dart';
import 'package:debrify/features/merged_detail/presentation/merged_primary_button.dart';
import 'package:debrify/features/merged_detail/presentation/merged_round_icon_button.dart';
import 'package:debrify/features/merged_detail/presentation/merged_source_pill.dart';
import 'package:debrify/features/merged_detail/presentation/merged_tracker_pill.dart';
import 'package:debrify/widgets/tracker_brand_marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MergedDetailActionLayout {
  final MergedDetailDependencies _deps;
  MergedDetailActionLayout(this._deps);
  bool get mounted => _deps.mounted();
  void Function(VoidCallback) get setState => _deps.setState;
  MergedDetailFocusState get _f => _deps.parts.focusState;
  MergedDetailMenus get _mn => _deps.parts.menus;
  MergedDetailMetadataActions get _ma => _deps.parts.metadataActions;
  MergedDetailMetadataState get _m => _deps.parts.metadataState;
  MergedDetailPaneLayout get _pa => _deps.parts.paneLayout;
  MergedDetailPlaybackActions get _pl => _deps.parts.playbackActions;
  MergedDetailResumeActions get _ra => _deps.parts.resumeActions;
  MergedDetailRootLayout get _ro => _deps.parts.rootLayout;
  MergedDetailTrackingActions get _ta => _deps.parts.trackingActions;
  MergedDetailTrackingState get _k => _deps.parts.trackingState;
  MergedDetailTrailerActions get _tr => _deps.parts.trailerActions;
  MergedDetailTrailerState get _t => _deps.parts.trailerState;
  MergedDetailWatchlistActions get _wa => _deps.parts.watchlistActions;

  /// Action-row key policy (TV). Without this, LEFT/RIGHT on a row button fall
  /// through to the pane's `focusInDirection`, whose geometric search happily
  /// picks a Cast / More-Like-This card sitting below-right of the row (every
  /// rail card is a real widget even when scrolled far out of view) — so RIGHT
  /// on the last button flung the cursor into "More Like This" instead of
  /// crossing into the episodes pane. Here the row owns its horizontal axis:
  /// RIGHT/LEFT walk the row's buttons in reading order; RIGHT past the last
  /// button crosses into the episodes pane (series two-pane only — dead stop
  /// otherwise); LEFT past the first is a dead stop.
  KeyEventResult handleActionRowKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowRight &&
        key != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    // The row's buttons in reading order (the Wrap can break onto a second
    // line, so order by line first, then x).
    // Bucket y into coarse lines rather than comparing raw centers: the
    // center-aligned Wrap can leave same-line buttons of different heights a
    // sub-pixel apart, which an exact compare would read as separate lines.
    // Wrap lines are ≥40px apart, so a 24px bucket can never split one.
    int line(FocusNode n) => (n.rect.center.dy / 24).round();
    final buttons = node.traversalDescendants.toList()
      ..sort((a, b) {
        final dy = line(a).compareTo(line(b));
        return dy != 0 ? dy : a.rect.center.dx.compareTo(b.rect.center.dx);
      });
    final i = buttons.indexOf(primary);
    if (i < 0) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowRight) {
      if (i < buttons.length - 1) {
        buttons[i + 1].requestFocus();
      } else if (!_ro.isMovie && _ro.wide) {
        _pa.focusEpisodesPane();
      }
      return KeyEventResult.handled;
    }
    // LEFT: previous button; dead stop at the first (UP is the way to the
    // back button, and a geometric fallback would dive into the rails).
    if (i > 0) buttons[i - 1].requestFocus();
    return KeyEventResult.handled;
  }

  Widget buildActionRow() {
    final count = _deps.boundSourceCount()?.call(_deps.item()) ?? 0;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: handleActionRowKey,
      child: buildActionRowButtons(count),
    );
  }

  Widget buildActionRowButtons(int count) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Primary play. Hidden for PikPak-only (can't quick-play — it queues a
        // cloud download), mirroring the detail screen's "Play". Holds the
        // LEFT-entry focus node when present; movies autofocus it on TV (a movie
        // has no episode list to auto-focus).
        if (_deps.showQuickPlay())
          MergedPrimaryButton(
            label: _ra.primaryLabel,
            busy: _ra.primaryBusy,
            icon: Icons.play_arrow_rounded,
            onTap: _pl.playPrimary,
            onLongPress:
                ((_ro.isMovie && _deps.onBrowse() != null) ||
                    (!_ro.isMovie &&
                        _deps.onBrowsePrimaryEpisodeSources() != null))
                ? _pl.browsePrimarySources
                : null,
            focusNode: _f.leftEntryFocusNode,
            autofocus: _deps.isTelevision() && _ro.isMovie,
            glow: _m.accent,
          ),
        // Trailer — sits right after Play. Only when Cinemeta gave us a YouTube
        // trailer id. Reflects the ambient backdrop's state: spinner while the
        // trailer loads, "Watch Trailer" once it's playing (tap = fullscreen),
        // plain "Trailer" otherwise (tap = resolve & play).
        if (_t.trailerYtId != null)
          MergedGhostButton(
            label: _t.trailerAmbientPlaying ? 'Watch Trailer' : 'Trailer',
            icon: _t.trailerAmbientPlaying
                ? Icons.play_circle_outline_rounded
                : Icons.movie_outlined,
            busy: _t.trailerResolving || _t.trailerLoading,
            onTap: _tr.playTrailer,
          ),
        // Movie: a Sources (manual list) button — the episode list is the
        // picker for series, so this is movie-only.
        if (_ro.isMovie && _deps.onBrowse() != null)
          MergedGhostButton(
            label: 'Sources',
            icon: Icons.layers_rounded,
            onTap: _deps.onBrowse()!,
          ),
        if (_wa.supportsMyWatchlist)
          MergedGhostButton(
            label: _k.inMyWatchlist ? 'In My Watchlist' : 'My Watchlist',
            icon: _k.inMyWatchlist
                ? Icons.bookmark_rounded
                : Icons.bookmark_add_outlined,
            onTap: _wa.toggleMyWatchlist,
          ),
        // Source binding. Takes the LEFT-entry focus node only when Play is
        // hidden (PikPak), so LEFT from an episode always lands on a live target.
        if (_deps.onSelectSource() != null)
          MergedSourcePill(
            count: count,
            focusNode: _deps.showQuickPlay() ? null : _f.leftEntryFocusNode,
            // A movie with Play hidden (PikPak-only) has no episode list to
            // auto-focus and no Play to autofocus — start the remote here.
            autofocus:
                _deps.isTelevision() && _ro.isMovie && !_deps.showQuickPlay(),
            onTap: () async {
              await _deps.onSelectSource()!(_deps.item());
              if (mounted) setState(() {});
            },
          ),
        // Debrify's own actions (bind source, Stremio TV, random episode,
        // season packs, local Continue Watching) — no tracker involved, so a
        // neutral button rather than a branded one.
        if (_ma.metadataExploreAction != null)
          MergedRoundIconButton(
            icon: Icons.explore_outlined,
            tooltip: 'Explore',
            onTap: _ma.metadataExploreAction!,
          ),
        if (_mn.appMenuOptions.isNotEmpty && _deps.onTraktAction() != null)
          MergedRoundIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'More',
            onTap: _mn.showAppActionsMenu,
          ),
        // Trakt — a branded pill that *carries* the live status (the status
        // chips that used to sit under the title are folded into it, so one
        // control both shows and changes the relationship).
        if (_mn.traktOnlyMenuOptions.isNotEmpty &&
            _deps.onTraktAction() != null)
          MergedTrackerPill(
            mark: TraktMark(size: 21, opacity: _ta.traktTracked ? 1 : 0.55),
            brand: 'TRAKT',
            state: _ta.traktPillLabel,
            rating: _k.traktStatus?.rating,
            accent: kTraktRed,
            tracked: _ta.traktTracked,
            tooltip: 'Trakt options',
            onTap: _mn.showQuickActionsMenu,
          ),
        // Simkl's own pill — a separate button/sheet, not merged with Trakt's,
        // so nothing here touches the button above.
        if (_mn.menuOptionsSimkl.isNotEmpty && _deps.onSimklAction() != null)
          MergedTrackerPill(
            mark: SimklMark(size: 21, opacity: _ta.simklTracked ? 1 : 0.55),
            brand: 'SIMKL',
            state: _ta.simklPillLabel,
            rating: _k.simklStatus?.rating,
            accent: kSimklCyan,
            tracked: _ta.simklTracked,
            tooltip: 'Simkl options',
            onTap: _mn.showSimklQuickActionsMenu,
          ),
        if (_mn.menuOptionsMdblist.isNotEmpty &&
            _deps.onMdblistAction() != null)
          MergedTrackerPill(
            mark: MdblistMark(size: 21, opacity: _ta.mdblistTracked ? 1 : 0.55),
            brand: 'MDBLIST',
            state: _ta.mdblistPillLabel,
            rating: _k.mdblistStatus?.rating,
            accent: kMdblistPurple,
            tracked: _ta.mdblistTracked,
            tooltip: 'MDBList options',
            onTap: _mn.showMdblistQuickActionsMenu,
          ),
      ],
    );
  }
}
