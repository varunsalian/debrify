import 'package:flutter/material.dart';
import '../../../widgets/skeleton_poster.dart' show BrandLoadingStage;
import 'home_stage_rows.dart';
import 'home_stage_section.dart';
import 'home_stage_rails.dart';
import 'home_stage_geometry.dart';
import 'home_stage_cells.dart';
import 'home_stage_favorites.dart';
import 'home_hero_preview.dart';
import 'home_board_media.dart';
import 'package:flutter/services.dart';
import 'home_tonight_board.dart';
import 'home_tonight_queue_list.dart';
import 'home_tonight_queue_row.dart';
import 'home_tonight_rail.dart';
import 'home_stage_row_label.dart';
import 'home_hero_section.dart';
import 'home_continuation_menu.dart';
import 'home_catalog_item_actions.dart';

typedef HomeTonightSectionDeps = ({
  BuildContext Function() context,
  bool Function() isTelevision,
  HomeBoardMedia Function() media,
  VoidCallback sidebar,
  HomeCatalogItemActions items,
});

/// Tonight's queue/rail layout composition and held-key dispatch.
class HomeTonightSection {
  HomeTonightSection(
    this._deps,
    this._stageSection,
    this._stageRailsSection,
    this._stageGeometry,
    this._stageCells,
    this._stageFavorites,
    this._heroPreview,
    this._heroSection,
    this._continuationMenu,
  );
  final HomeTonightSectionDeps _deps;
  final HomeStageSection _stageSection;
  final HomeStageRails _stageRailsSection;
  final HomeStageGeometry _stageGeometry;
  final HomeStageCells _stageCells;
  final HomeStageFavorites _stageFavorites;
  final HomeHeroPreview _heroPreview;
  final HomeHeroSection _heroSection;
  final HomeContinuationMenu _continuationMenu;

  /// TONIGHT: resume-first. A large card carries whatever has focus, a
  /// vertical Continue queue stands beside it, and one rail runs underneath.
  /// UP/DOWN walks the two zones as a single column, so the Continue rows sit
  /// "above" the first rail exactly as they read.
  Widget buildTonightBoard() {
    final context = _deps.context();
    final queue = _stageRailsSection.tonightQueue;
    final rails = _stageRailsSection.stageRails;
    if (queue.isEmpty && rails.isEmpty) {
      return BrandLoadingStage(isTelevision: _deps.isTelevision());
    }
    // A zone that no longer exists can't hold focus.
    if (_stageSection.tonightZoneIsQueue && queue.isEmpty) {
      _stageSection.tonightZoneIsQueue = false;
    }
    if (!_stageSection.tonightZoneIsQueue && rails.isEmpty) {
      _stageSection.tonightZoneIsQueue = true;
    }
    final view = rails.isEmpty ? null : _stageSection.resolveStageRail();
    _stageSection.seedStageFocusOnce();

    return buildHomeTonightBoard(
      hostContext: context,
      queueCount: queue.length,
      hasRail: rails.isNotEmpty,
      media: () => _deps.media(),
      trailerActive: () => _heroPreview.heroTrailerActive,
      cardInfo: _stageSection.tonightCard,
      labelHeight: atriumLabelHeight,
      labelGap: kAtriumLabelGap,
      railBoxHeight: _stageGeometry.stageRailBoxH,
      onQueueHidden: () => _stageSection.tonightZoneIsQueue = false,
      queueBuilder: (height, width) =>
          tonightQueueList(queue, height, width, rails.isNotEmpty),
      railBuilder: view == null
          ? null
          : (height, queueAbove) =>
                tonightRail(view, height, queueAbove: queueAbove),
    );
  }

  Widget tonightQueueList(
    List<HomeTonightQueueEntry> queue,
    double rowH,
    double queueW,
    bool hasRail,
  ) {
    return buildHomeTonightQueueList(
      itemCount: queue.length,
      rowHeight: rowH,
      queueWidth: queueW,
      itemBuilder: (context, i, thumbW) {
        final e = queue[i];
        final cw = e.rail.cw!;
        final item = cw.items[e.col];
        return HomeTonightQueueRow(
          item: item,
          height: rowH,
          thumbWidth: thumbW,
          focusNode: cw.nodes[e.col],
          episode: cw.episodeOf(item),
          progress: cw.progressOf(item),
          hasBoundSource: _deps.items.isBound(item),
          onFocused: () {
            _stageSection.tonightFocus.selectQueue(e, i, item);
            _heroSection.setHero(item);
          },
          onOpen: () => cw.onOpen(item),
          onLongPress: () =>
              _continuationMenu.openCwCardMenu(cw, item, e.rail.cwIndex, e.col),
          onUp: () {
            if (_stageSection.stageHold.swallows(LogicalKeyboardKey.arrowUp)) {
              return;
            }
            if (i > 0) {
              _stageSection
                  .nearestMountedNode(
                    queue[i - 1].rail.cw!.nodes,
                    queue[i - 1].col,
                  )
                  ?.requestFocus();
            }
          },
          onDown: () {
            if (_stageSection.stageHold.swallows(
              LogicalKeyboardKey.arrowDown,
            )) {
              return;
            }
            if (i + 1 < queue.length) {
              _stageSection
                  .nearestMountedNode(
                    queue[i + 1].rail.cw!.nodes,
                    queue[i + 1].col,
                  )
                  ?.requestFocus();
            } else if (hasRail) {
              _stageSection.tonightFocusRail();
            }
          },
          // HELD down: leave the queue for the rail in one gesture.
          // The queue is every Continue Watching item from every
          // source flattened into one column, so stepping past it a
          // row at a time can be a long walk.
          onDownHold: hasRail
              ? () => _stageSection.stageHold.jump(
                  LogicalKeyboardKey.arrowDown,
                  _stageSection.tonightFocusRail,
                )
              : null,
          onLeft: _deps.sidebar,
        );
      },
    );
  }

  Widget tonightRail(
    HomeStageRailView view,
    double boxH, {
    required bool queueAbove,
  }) {
    final context = _deps.context();
    final rail = view.rail;
    final railKey = view.key;
    final favRail = rail.favKind != null;
    final items = view.items;
    final nodes = view.nodes;
    final count = favRail
        ? _stageRailsSection.canvasFavItemCount(rail.favKind!)
        : items.length;
    // UP walks back through the rails and then into the queue — the two zones
    // are one vertical column.
    void up() {
      if (_stageSection.stageHold.swallows(LogicalKeyboardKey.arrowUp)) return;
      if (view.index > 0) {
        _stageSection.stageSwitchRail(-1);
      } else if (queueAbove) {
        _stageSection.tonightFocusQueue();
      }
    }

    void down() {
      if (_stageSection.stageHold.swallows(LogicalKeyboardKey.arrowDown)) {
        return;
      }
      _stageSection.stageSwitchRail(1);
    }

    // HELD up: back to the Continue queue from any rail, the mirror of the
    // queue's held DOWN.
    final upHold = queueAbove
        ? () => _stageSection.stageHold.jump(
            LogicalKeyboardKey.arrowUp,
            _stageSection.tonightFocusQueue,
          )
        : null;

    return buildHomeTonightRail(
      railHeight: boxH,
      labelGap: kAtriumLabelGap,
      railKey: railKey,
      itemCount: count,
      label: buildHomeStageRowLabel(
        context: context,
        title: _stageRailsSection.canvasTabTitle(view.rails, view.index),
      ),
      itemBuilder: (context, col) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Center(
          child: SizedBox(
            width: favRail
                ? _stageGeometry.stageFavW(context, boxH)
                : boxH * _stageGeometry.stageCardAspect(rail),
            child: favRail
                ? _stageFavorites.canvasFavCell(
                    rail.favKind!,
                    railKey,
                    col,
                    onUp: up,
                    onDown: down,
                    onUpHold: upHold,
                  )
                : SizedBox(
                    height: boxH,
                    child: _stageCells.stageShelfCell(
                      rail,
                      railKey,
                      items,
                      nodes,
                      col,
                      onUp: up,
                      onDown: down,
                      onUpHold: upHold,
                      onFocusedExtra: () {
                        _stageSection.tonightFocus.selectRail(rail, items[col]);
                      },
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
