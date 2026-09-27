import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../models/stremio_addon.dart';
import '../../../widgets/see_all/discover_card_settings_scope.dart';
import '../../../widgets/see_all/discover_detail_rail.dart';
import '../../../widgets/see_all/discover_trailer_stage.dart';
import '../models/discover_card_settings.dart';
import 'discover_grid_layout.dart';
import 'discover_preview.dart';
import 'discover_stage_backdrop.dart';
import 'discover_stage_layout.dart';
import 'discover_stage_veils.dart';

/// Assembles one Discover canvas using a borrowed panel and preview feed.
/// Owns no focus nodes, data reads, preference state or native resources.
Widget buildDiscoverContent(
  BuildContext context, {
  required Widget sourcePanel,
  required DiscoverCardSettings cardSettings,
  required bool showPreview,
  required bool stage,
  required ValueListenable<StremioMeta?> focused,
  required DiscoverPreview preview,
  required bool Function() isCurrent,
  required Widget Function(bool visible) loadingIndicator,
  required Widget Function(bool visible) ambientIndicator,
}) {
  final panel = DiscoverCardSettingsScope(
    showTypeTags: cardSettings.showTypeTags,
    showRatings: cardSettings.showRatings,
    showTitles: cardSettings.showTitles,
    child: sourcePanel,
  );
  // Touch has no persistent focus, so a reactive detail rail has nothing to
  // react to — keep the full-width grid there. TV gets the glass-stage
  // two-pane layout.
  if (!showPreview) {
    return panel;
  }
  return LayoutBuilder(
    builder: (layoutContext, c) {
      // Guard a degenerate canvas: too narrow leaves no room for a usable grid
      // beside the rail; too short and the rail's fixed identity block can't
      // fit. Either way, fall back to the full-width panel.
      if (c.maxWidth < 720 || c.maxHeight < 420) {
        // The trailer stage (which drives preview.takeover → sidebar chrome-dim,
        // and preview.showing → the AMBIENT chip) is unmounted in this
        // branch. Clear both post-frame so nothing sticks across the drop.
        if (preview.needsCompactReset) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!isCurrent()) return;
            preview.clearCompactEffects();
          });
        }
        return panel;
      }
      if (stage) {
        return _buildStage(
          context,
          c,
          panel,
          focused: focused,
          preview: preview,
          loadingIndicator: loadingIndicator,
          ambientIndicator: ambientIndicator,
        );
      }
      return buildDiscoverGridLayout(
        layoutContext,
        c: c,
        panel: panel,
        detailRail: ValueListenableBuilder<StremioMeta?>(
          valueListenable: focused,
          builder: (_, item, __) => DiscoverDetailRail(
            item: item,
            trailerStreams: preview.streams,
            trailerLoading: preview.loading,
            trailerVolume: preview.volume,
            trailerMeta: preview.meta,
            shownItem: preview.shown,
          ),
        ),
        backdrop: DiscoverStageBackdrop(shown: preview.shown),
        trailer: DiscoverTrailerStage(
          trailer: preview.streams,
          loading: preview.loading,
          volume: preview.volume,
          meta: preview.meta,
          railRect: Rect.zero,
          takeover: preview.takeover,
          fullStage: true,
          showing: preview.showing,
        ),
        veils: DiscoverStageVeils(
          showing: preview.showing,
          theater: preview.theater,
        ),
        theater: preview.theater,
        showing: preview.showing,
        loading: preview.loading,
        takeover: preview.takeover,
        loadingIndicator: loadingIndicator,
        ambientIndicator: ambientIndicator,
      );
    },
  );
}

/// The Discover STAGE layout (`discover_layout` = 'stage', TV only).
///
/// Same stage as the grid's two-pane — same backdrop, same full-canvas
/// trailer, same theater ladder — with the rail dissolved: the focused
/// title's art owns the whole frame, its identity block sits bottom-left over
/// it, and the results become ONE shelf across the bottom. The filter line
/// stays exactly where the grid put it (top-left of the panel), so UP from
/// the shelf lands on it just as UP from the grid does.
///
/// It is the SAME panel widget as the grid layout: the See-All screen keeps
/// owning fetch, filters and paging, and only the arrangement of its results
/// changes — declared by the shelf scope wrapped around it by the Stage composition.
Widget _buildStage(
  BuildContext context,
  BoxConstraints c,
  Widget panel, {
  required ValueListenable<StremioMeta?> focused,
  required DiscoverPreview preview,
  required Widget Function(bool visible) loadingIndicator,
  required Widget Function(bool visible) ambientIndicator,
}) => buildDiscoverStageLayout(
  context,
  constraints: c,
  panel: panel,
  buildIdentity: (maxWidth, budget) => ValueListenableBuilder<StremioMeta?>(
    valueListenable: focused,
    builder: (_, item, __) => DiscoverDetailRail(
      item: item,
      layout: DiscoverDetailLayout.stage,
      trailerShowing: preview.showing,
      stageMaxWidth: maxWidth,
      stageBudget: budget,
      // Holding a direction across the shelf settles identity updates;
      // the trailer still releases on the first keypress.
      settleDelay: const Duration(milliseconds: 260),
      trailerStreams: preview.streams,
      trailerLoading: preview.loading,
      trailerVolume: preview.volume,
      trailerMeta: preview.meta,
      shownItem: preview.shown,
    ),
  ),
  backdrop: DiscoverStageBackdrop(
    shown: preview.shown,
    // Identity already settles the feed: art and title land together.
    dwell: Duration.zero,
    crossfade: true,
  ),
  trailer: DiscoverTrailerStage(
    trailer: preview.streams,
    loading: preview.loading,
    volume: preview.volume,
    meta: preview.meta,
    railRect: Rect.zero,
    takeover: preview.takeover,
    fullStage: true,
    showing: preview.showing,
  ),
  veils: DiscoverStageVeils(
    showing: preview.showing,
    theater: preview.theater,
    stage: true,
  ),
  theater: preview.theater,
  showing: preview.showing,
  loading: preview.loading,
  takeover: preview.takeover,
  loadingIndicator: loadingIndicator,
  ambientIndicator: ambientIndicator,
);
