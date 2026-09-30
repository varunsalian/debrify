import 'package:flutter/material.dart';
import 'dart:async';
import '../../../widgets/home/spotlight_board.dart';
import '../../../utils/platform_util.dart';
import 'home_display_section.dart';
import 'home_hero_preview.dart';
import 'home_spotlight_section.dart';
import 'home_item_actions.dart';
import 'home_stage_rails.dart';
import 'home_spotlight_rows.dart';
import 'home_board_media.dart';

typedef HomeSpotlightBoardsDeps = ({
  bool Function() mounted,
  bool Function() isTelevision,
  Future<void> Function(int) loadMoreRow,
  Future<bool> Function() loadMore,
  bool Function() rowsPending,
  HomeBoardMedia Function() media,
});

/// Composes the Home Spotlight board, trailer cadence and ambient publication.
class HomeSpotlightBoards {
  HomeSpotlightBoards(
    this._deps,
    this._stageRailsSection,
    this._displaySection,
    this._heroPreview,
    this._spotlightSection,
    this._itemActions,
    this._spotlightRows,
    this._shellArt,
    this._shellTint,
  );
  final HomeSpotlightBoardsDeps _deps;
  final HomeStageRails _stageRailsSection;
  final HomeDisplaySection _displaySection;
  final HomeHeroPreview _heroPreview;
  final HomeSpotlightSection _spotlightSection;
  final HomeItemActions _itemActions;
  final HomeSpotlightRows _spotlightRows;
  final ValueNotifier<String?> _shellArt;
  final ValueNotifier<Color?> _shellTint;

  Widget buildSpotlightBoard() {
    // Snapshot row descriptors with the shelf list: async inserts must not
    // make a callback page a different catalog than the shelf it came from.
    final rails = _stageRailsSection.canvasRails;
    return SpotlightBoard(
      largeScreenInteractions: true,
      key: _spotlightSection.spotlightKey,
      animationsEnabled: _displaySection.homeAnimationsEnabled,
      animationStyle: _displaySection.homeAnimationStyle,
      hero: _spotlightSection.spotlightHero,
      sections: _spotlightRows.spotlightShelves,
      heroNode: _spotlightSection.spotlightHeroNode,
      heroAddon: _spotlightSection.spotlightHeroSection?.addon,
      dpad: _deps.isTelevision(),
      showCardTitlesAndRatings: !_displaySection.hideHomeCardTitlesAndRatings,
      expandFocusedCard: _displaySection.spotlightFocusDetails,
      cardTrailerVolume: _heroPreview.heroTrailerVolume,
      onHeroOpen: _itemActions.openItem,
      onLoadMoreRow: (row) {
        if (row < 0 || row >= rails.length) return;
        final catalogRow = rails[row].sectionIndex;
        if (catalogRow != null) unawaited(_deps.loadMoreRow(catalogRow));
      },
      onLoadMoreShelves: _deps.loadMore,
      pendingShelves: PlatformUtil.isAndroidTvCached && _deps.rowsPending(),
      // The board owns the CADENCE; the resolve and the video stay here.
      //
      // Every other entry into `_heroPreview.scheduleHeroTrailer` is still excluded for
      // this style — init, section loads, focus changes, `_heroSection.applyHero`, route
      // return, sidebar return — so the board's clock is the single owner and
      // the two cannot start a trailer under different titles.
      // Suppression is enforced inside
      // _heroPreview.scheduleHeroTrailer. Folding it in here disarms the board's dwell
      // clock entirely — and the dwell is the only event that can LIFT the
      // suppression when the reel moves to a new title, so one post-playback
      // rebuild would have frozen trailers until the tab was recreated.
      trailersEnabled: _heroPreview.heroTrailerEnabled,
      onDwell: (item) =>
          _heroPreview.scheduleHeroTrailer(item, fromSpotlight: true),
      onTrailerStop: _heroPreview.clearHeroTrailer,
      // Full bleed on every form factor — a letterboxed 16:9 band was tried
      // on the phone and read as a TV set embedded in the artwork (user call).
      // The portrait cover-crop is the design; sharpness comes from the 1080p
      // resolve and medium-filter texture sampling.
      trailer: _heroPreview.heroTrailerRenderable
          ? _deps.media().trailerLayer(540, fullBleed: true)
          : null,
      // TV only: the glass stage the publish feeds exists behind the TV
      // sidebar rail. Off-TV there is no consumer, and writing the shared
      // notifiers from a phone Home would leave stale art for the next TV
      // session of a hot-restarted debug run.
      onAmbient: _deps.isTelevision()
          ? (art, tint) {
              if (!_deps.mounted()) return;
              _shellArt.value = art;
              _shellTint.value = tint;
            }
          : null,
    );
  }
}
