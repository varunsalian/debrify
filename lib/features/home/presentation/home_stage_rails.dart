import 'package:flutter/material.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/home_collection_rows.dart';
import '../models/home_favorite_row_ref.dart';
import '../application/home_row_order.dart';
import 'home_stage_rows.dart';
import 'home_rail_composition.dart';
import 'home_continuation_projection.dart';
import 'home_continuation_section.dart';
import 'home_saved_content_section.dart';

typedef HomeStageRailsDeps = ({
  List<CatalogSection> Function() sections,
  List<List<FocusNode>> Function() rowNodes,
  bool Function() orderActive,
  List<String> Function() order,
  Set<String> Function() disabled,
  String Function(CatalogSection) sectionRowId,
  String Function() style,
  bool Function() hideCollectionNames,
  String Function(CatalogSection) sectionTag,
});

/// Live rail identities, ordering, titles and borrowed focus-node projections.
class HomeStageRails {
  HomeStageRails(this._deps, this._continuation, this._state, this._saved);
  final HomeStageRailsDeps _deps;
  final HomeContinuationProjection _continuation;
  final HomeContinuationSection _state;
  final HomeSavedContentSection _saved;

  /// Every non-empty Home rail in the board's built-in order. Search's
  /// dedicated Lists mode has its own body and never enters this collection.
  /// FocusNode lists are reused from the classic board's per-row lists — only
  /// one view is ever mounted, and reuse keeps node counts synced through
  /// paging for free.
  List<HomeRail> get canonicalCanvasRails => HomeRailComposition.canonical(
    continuation: _continuation.cwVisible ? _continuation.cwRows : const [],
    favorites: _saved.favRowKinds,
    favoriteCount: canvasFavItemCount,
    sectionCount: _deps.sections().length,
    nodeRowCount: _deps.rowNodes().length,
    sectionHasItems: (index) => _deps.sections()[index].items.isNotEmpty,
    rowId: canvasRailRowId,
  );

  List<HomeRail> orderedHomeRails(List<HomeRail> rails) => _deps.orderActive()
      ? HomeRowOrder.apply(rails, _deps.order(), canvasRailRowId)
      : rails;

  List<HomeRail> get canvasRails => orderedHomeRails(canonicalCanvasRails);

  List<HomeRail> get classicHomeRails => orderedHomeRails(
    HomeRailComposition.classic(
      canonical: canonicalCanvasRails,
      reserveTrakt: _continuation.traktReserving,
      mergeTrakt: _state.cwMergeTrakt,
      disabled: _deps.disabled(),
    ),
  );

  String canvasRailRowId(HomeRail rail) {
    if (rail.cw != null) return rail.cw!.rowId;
    if (rail.favKind != null) return _saved.favRowId(rail.favKind!);
    if (rail.traktSkeletonIndex >= 0) {
      return rail.traktSkeletonIndex == 0 ? 'trakt:movies' : 'trakt:shows';
    }
    return _deps.sectionRowId(_deps.sections()[rail.sectionIndex!]);
  }

  List<HomeTonightQueueEntry> get tonightQueue => _continuation.cwVisible
      ? HomeRailComposition.tonightQueue(canvasRails)
      : [];

  List<HomeRail> get stageRails => HomeRailComposition.stage(
    canvasRails,
    tonight: _deps.style() == 'tonight',
  );

  int canvasFavItemCount(HomeFavoriteRowRef ref) {
    if (ref.isIptvList) {
      return _saved.iptvListRows[ref.list].channels.length;
    }
    switch (ref.kind) {
      case HomeFavoriteKind.watchlistMovies:
        return _saved.watchlistMovieItems.length;
      case HomeFavoriteKind.watchlistSeries:
        return _saved.watchlistSeriesItems.length;
      case HomeFavoriteKind.iptv:
        return _saved.iptvFavChannels.length;
      case HomeFavoriteKind.debrify:
        return _saved.tvFavChannels.length;
      case HomeFavoriteKind.stremio:
        return _saved.stvFavChannels.length;
      case HomeFavoriteKind.playlist:
        return _saved.playlistItems.length;
    }
  }

  String canvasFavTitle(HomeFavoriteRowRef ref) {
    if (ref.isIptvList) return _saved.iptvListRows[ref.list].title;
    switch (ref.kind) {
      case HomeFavoriteKind.watchlistMovies:
        return 'Watchlist Movies';
      case HomeFavoriteKind.watchlistSeries:
        return 'Watchlist Series';
      case HomeFavoriteKind.iptv:
        return 'IPTV Favorites';
      case HomeFavoriteKind.debrify:
        return 'Debrify TV';
      case HomeFavoriteKind.stremio:
        return 'Stremio TV';
      case HomeFavoriteKind.playlist:
        return 'Playlist';
    }
  }

  String canvasRailTitle(HomeRail rail) {
    if (rail.cw != null) return rail.cw!.title;
    if (rail.favKind != null) return canvasFavTitle(rail.favKind!);
    final section = _deps.sections()[rail.sectionIndex!];
    if (_deps.hideCollectionNames() && section is HomeCollectionSection) {
      return '';
    }
    return section.title;
  }

  List<StremioMeta> canvasRailItems(HomeRail rail) =>
      rail.cw?.items ?? _deps.sections()[rail.sectionIndex!].items;

  List<FocusNode> canvasRailNodes(HomeRail rail) {
    if (rail.cw != null) return rail.cw!.nodes;
    if (rail.favKind != null) return _saved.favNodesFor(rail.favKind!);
    return _deps.rowNodes()[rail.sectionIndex!];
  }

  /// Tab label for a rail, with colliding titles disambiguated by the
  /// section's provenance tag. Titles carry their content type themselves
  /// now ("Popular Movies" — [CatalogSection.rowTitle]), so the only way two
  /// tabs still collide is the same catalog name+type from two ADDONS — and
  /// the addon is exactly what tells those apart.
  String canvasTabTitle(List<HomeRail> rails, int i) {
    final title = canvasRailTitle(rails[i]);
    if (title.isEmpty) return '';
    final rail = rails[i];
    if (rail.sectionIndex == null) return title;
    final duplicated = rails.any(
      (r) => !identical(r, rail) && canvasRailTitle(r) == title,
    );
    if (!duplicated) return title;
    return '$title · ${_deps.sectionTag(_deps.sections()[rail.sectionIndex!])}';
  }
}
