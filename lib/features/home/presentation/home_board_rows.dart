import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/home_collection_rows.dart';
import '../../../widgets/home/home_row_focus.dart'
    show homeRowHeight, preserveHomeInsertionAnchor;
import '../../search/presentation/catalog_search_section.dart';
import 'home_board_section.dart';
import 'home_board_loading.dart';
import 'home_board_paging.dart';
import 'home_display_section.dart';
import 'home_stage_section.dart';
import 'home_stage_rails.dart';
import 'home_stage_favorites.dart';
import 'home_spotlight_section.dart';
import 'home_hero_section.dart';
import 'home_hero_preview.dart';
import 'home_hero_live.dart';

typedef HomeBoardRowsDeps = ({
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  String Function(CatalogSection) rowId,
  double Function(BuildContext, {CatalogSection? section}) classicRowExtent,
  Future<void> Function() refreshBoundSources,
});

/// Reconciles displayed rows and their focus/scroll anchors, then seeds the hero.
class HomeBoardRows {
  HomeBoardRows(
    this._deps,
    this._boardSection,
    this._boardLoading,
    this._boardPaging,
    this._catalogSection,
    this._displaySection,
    this._stageSection,
    this._stageRailsSection,
    this._stageFavorites,
    this._spotlightSection,
    this._heroSection,
    this._heroPreview,
    this._heroLive,
  );
  final HomeBoardRowsDeps _deps;
  final HomeBoardSection _boardSection;
  final HomeBoardLoading _boardLoading;
  final HomeBoardPaging _boardPaging;
  final CatalogSearchSection _catalogSection;
  final HomeDisplaySection _displaySection;
  final HomeStageSection _stageSection;
  final HomeStageRails _stageRailsSection;
  final HomeStageFavorites _stageFavorites;
  final HomeSpotlightSection _spotlightSection;
  final HomeHeroSection _heroSection;
  final HomeHeroPreview _heroPreview;
  final HomeHeroLive _heroLive;

  /// Swap the displayed sections (homepage or search results): rebuild the
  /// per-row focus nodes and reset the hero to the first item.
  void applySections(
    List<CatalogSection> sections, {
    bool preserveFocus = false,
    bool incremental = false,
  }) {
    String? anchor;
    double? anchorHeight;
    double anchorTailPadding = 0;
    List<String> previousOrder = const [];
    if (incremental && _displaySection.homeStyleEffective == 'classic') {
      final rails = _stageRailsSection.classicHomeRails;
      for (final rail in rails) {
        if (rail.traktSkeletonIndex >= 0) continue;
        final focused = _stageRailsSection
            .canvasRailNodes(rail)
            .where((node) => node.hasFocus);
        if (focused.isEmpty) continue;
        anchor = _stageRailsSection.canvasRailRowId(rail);
        // Newly published rows are catalog/list/collection rows even if the
        // focused anchor is Continue Watching or a favourite in a custom order.
        if (rail.sectionIndex != null) {
          anchorHeight = homeRowHeight(
            focused.first.context,
            ValueKey('board-reveal-${_boardSection.boardGen}-$anchor'),
          );
        }
        anchorHeight ??= _deps.classicRowExtent(
          focused.first.context ?? _deps.context(),
          section: rail.sectionIndex == null
              ? null
              : _boardSection.sections[rail.sectionIndex!],
        );
        break;
      }
      previousOrder = rails.map(_stageRailsSection.canvasRailRowId).toList();
      if (anchor != null &&
          _boardSection.boardScroll.hasClients &&
          _boardSection.boardScroll.position.maxScrollExtent <= 0) {
        // A short first batch leaves unused viewport space below its rows.
        // Retain that space as tail padding when rows are inserted above the
        // anchor, otherwise scroll physics clamps away the preserved offset.
        final heights = <double>[];
        for (final rail in rails) {
          if (rail.traktSkeletonIndex >= 0) break;
          final nodes = _stageRailsSection.canvasRailNodes(rail);
          final height = nodes
              .map(
                (node) => homeRowHeight(
                  node.context,
                  ValueKey(
                    'board-reveal-${_boardSection.boardGen}-${_stageRailsSection.canvasRailRowId(rail)}',
                  ),
                ),
              )
              .whereType<double>()
              .firstOrNull;
          if (height == null) break;
          heights.add(height);
        }
        if (heights.length == rails.length) {
          anchorTailPadding = max(
            _boardSection.classicAnchorTailPadding,
            _boardSection.boardScroll.position.viewportDimension -
                38 -
                heights.fold<double>(0, (sum, height) => sum + height),
          );
        }
      }
    }
    // Streaming arrivals are not a fresh board: preserve keyed row elements,
    // entrance state, and any pending user-directed move to the next rail.
    if (!incremental) {
      _boardSection.boardGen++;
      _boardSection.boardAppliedAt = DateTime.now();
      // Rail keys are content-addressed by stable Home-row id, so a reload can
      // preserve the active rail even when its numeric section index changes.
      _stageSection.stageDeferredAdvance.invalidateForBoardReseed();
      _stageSection.stageFocusRequests.invalidate();
    }
    _boardSection.boardViewport.replaceRows(
      previous: _boardSection.sections,
      next: sections,
      rowId: _deps.rowId,
      preserveFocus: preserveFocus,
      incremental: incremental,
    );
    _deps.setState(() {
      _boardSection.sections = sections;
      if (anchor != null && anchorHeight != null) {
        final nextOrder = _stageRailsSection.classicHomeRails
            .map(_stageRailsSection.canvasRailRowId)
            .toList();
        if (nextOrder
            .takeWhile((id) => id != anchor)
            .any((id) => !previousOrder.contains(id))) {
          _boardSection.classicAnchorTailPadding = max(
            _boardSection.classicAnchorTailPadding,
            anchorTailPadding,
          );
        }
        preserveHomeInsertionAnchor(
          scroll: _boardSection.boardScroll,
          previous: previousOrder,
          next: nextOrder,
          anchor: anchor,
          extentOf: (_) => anchorHeight!,
        );
      }
    });
    _spotlightSection.publishTopShelfSpotlight();
    unawaited(_deps.refreshBoundSources());
    if (preserveFocus &&
        _heroSection.heroItem.value != null &&
        sections.any(
          (section) => section.items.any(
            (item) =>
                item.id == _heroSection.heroItem.value!.id &&
                item.type == _heroSection.heroItem.value!.type,
          ),
        )) {
      return;
    }
    // Seed the hero with the first item so it isn't blank before DPAD focus
    // lands (see [_heroSection.heroActive] for when the hero is shown).
    if (_heroSection.heroActive) {
      // Seed from the first real title: a pinned collection row can lead the
      // board, and folder tiles can't drive the hero.
      StremioMeta? first;
      for (final section in sections) {
        if (section is HomeCollectionSection) continue;
        if (section.items.isNotEmpty) {
          first = section.items.first;
          break;
        }
      }
      _heroSection.heroItem.value = first;
      _heroSection.heroEnriched.value = null;
      // Outside the null-check: a board that reloads EMPTY must clear the
      // shell stage too (null item → null art), not keep the last title's.
      _heroSection.publishAmbientArt(first, null);
      if (first != null) {
        _heroSection.enrichHero(first);
        _heroSection.updateHeroTint(first);
        // Billboard effect: the seeded spotlight starts its trailer too, so
        // opening Home settles into a living hero without any DPAD input.
        // A board reload is a fresh visit — lift any after-the-feature
        // suppression, and drop any Canvas favourites override + live feed
        // (a reload landing while a favourite held focus would otherwise
        // keep its stale art/title on the stage — or resume its stream —
        // with no cell focused, and let the seeded trailer start beneath).
        _heroPreview.heroPreviewPolicy.allowNewHero();
        _stageFavorites.canvasFavFocus.value = null;
        _heroLive.clearHeroLiveIptv();
        _heroPreview.scheduleHeroTrailer(first);
      } else {
        _heroPreview.clearHeroTrailer();
        // Clear the COLOUR too, not just the art — an empty reload otherwise
        // left the departed title's tint on the shell stage + sidebar glass.
        _heroSection.heroTint.value = null;
        _heroSection.publishHeroTintToShell(null);
      }
    }
  }

  /// Cancel any pending search and return to the homepage board.
  void restoreHome() {
    _catalogSection.catalogController.clear();
    // A settings/integration reload arrived mid-search and was deferred so it
    // couldn't stomp the results view — run it now instead of restoring the
    // stale cached board.
    if (_boardSection.pendingBoardReload) {
      _boardSection.pendingBoardReload = false;
      _boardLoading.load();
      return;
    }
    applySections(_boardSection.homeSections);
    _boardPaging.maybeAutoFillBoard();
  }
}
