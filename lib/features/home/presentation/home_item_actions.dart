import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/media_identity.dart';
import '../../../screens/episodes_screen.dart';
import '../models/home_catalog_session.dart';
import '../application/home_catalog_origin_dependencies.dart';
import '../application/home_detail_dependencies.dart';
import 'home_detail_menus.dart';
import 'home_detail_navigation.dart';
import 'home_detail_presentation.dart';
import 'home_catalog_actions.dart';
import 'home_detail_actions.dart';
import 'home_playback_navigation.dart';
import 'home_source_actions.dart';

typedef HomeItemActionsDeps = ({
  BuildContext Function() context,
  HomeCatalogSession Function() session,
  bool Function() isTelevision,
  bool Function() pikpakOnly,
  bool Function() mergedSeriesPage,
  String? Function(StremioMeta) imdbOf,
  Set<String> Function() cwIds,
  Future<bool> Function(String) removeLocalHistory,
  Future<void> Function() onHistoryRemoved,
  void Function(int?) onClosed,
  HomeDetailMenus Function(StremioMeta, String?, bool) menus,
  int Function(StremioMeta) boundCountFor,
});

/// Opens catalog detail routes with the original menu, playback and return wiring.
class HomeItemActions {
  HomeItemActions(
    this._ref,
    this._deps,
    this._playback,
    this._catalog,
    this._details,
    this._sources,
  );
  final WidgetRef _ref;
  final HomeItemActionsDeps _deps;
  final HomePlaybackNavigation _playback;
  final HomeCatalogActions _catalog;
  final HomeDetailActions _details;
  final HomeSourceActions _sources;

  void openItem(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
    // Shared-element tag from the tapped board cell: the poster flies into the
    // detail page's backdrop. Null (non-board callers) = regular transition.
    String? heroTag,
    // For a series opened at a specific episode (Trakt Calendar): scroll the
    // episodes panel to this season/episode. Ignored by the movie/legacy paths.
    int? initialSeason,
    int? initialEpisode,
    // When set, switch back to this tab once the detail route closes — lets a
    // cross-tab opener (the Calendar) return the user to where they came from.
    int? returnToTabOnClose,
  }) {
    bool current() => _playback.catalogNavigationCurrent();
    if (!current()) return;
    final context = _deps.context();
    final navigation = HomeDetailNavigation(
      _ref.read(homeCatalogOriginRepositoryProvider(_deps.session().owner)),
    );
    unawaited(
      navigation.open(
        context: context,
        item: item,
        addon: addon,
        routeName: kCatalogDetailRouteName,
        isCurrent: current,
        hasLocalHistory: (item) => _deps.cwIds().contains(item.imdbId),
        removeLocalHistory: _deps.removeLocalHistory,
        onHistoryRemoved: _deps.onHistoryRemoved,
        showMessage: _playback.snack,
        onClosed: () => _deps.onClosed(returnToTabOnClose),
        prepareBuilder: (item, addon, detailRoute) {
          _playback.activeAddonId = addon.id;
          final imdb = _deps.imdbOf(item);
          // Show a "Remove from Continue Watching" action when this title is on the
          // Continue Watching row (regardless of which row opened it).
          final inCw = imdb != null && _deps.cwIds().contains(imdb);
          final menus = _deps.menus(item, imdb, inCw);

          // Choose the layout at opening time, as before, rather than on a route rebuild.
          final mergedDetail = _deps.mergedSeriesPage();
          final readers = _ref.read(
            homeDetailReadersProvider(_deps.session().owner),
          );
          bool detailCurrent() => detailRoute.isActive;
          return (_) => buildHomeDetail(
            item: item,
            addon: addon,
            merged: mergedDetail,
            isTelevision: _deps.isTelevision(),
            pikpakOnly: _deps.pikpakOnly(),
            hasBoundSource: menus.hasBoundSource,
            isTraktSource: isTraktSource,
            isMdblistSource: isMdblistSource,
            heroTag: heroTag,
            initialSeason: initialSeason,
            initialEpisode: initialEpisode,
            resumeInfo: () => _catalog.resolveResumeInfo(
              item,
              addon,
              isTraktSource: isTraktSource,
              isMdblistSource: isMdblistSource,
            ),
            play:
                ({
                  bool startFromBeginning = false,
                  bool preferTraktResume = false,
                  bool skipEpisodeFallback = false,
                  bool browseSourcesOnly = false,
                  HomeDetailPromise? promisedTarget,
                }) => _catalog.onCatalogPlay(
                  item,
                  addon,
                  isCurrent: () => detailRoute.isActive,
                  isTraktSource: isTraktSource,
                  isMdblistSource: isMdblistSource,
                  startFromBeginning: startFromBeginning,
                  preferTraktResume: preferTraktResume,
                  skipEpisodeFallback: skipEpisodeFallback,
                  browseSourcesOnly: browseSourcesOnly,
                  promisedTarget: promisedTarget,
                ),
            browse: () => _playback.onCatalogBrowse(
              item,
              addon,
              isTraktSource: isTraktSource,
              isMdblistSource: isMdblistSource,
            ),
            browseSelection: (selection) => _playback.browseSelection(
              selection,
              metadataAddonId: addon.id,
              catalogItem: item.withSourceAddon(addon),
            ),
            playSelection: (selection) => _playback.playSelection(
              selection,
              metadataAddonId: addon.id,
              catalogItem: item.withSourceAddon(addon),
            ),
            boundSourceCount: _deps.boundCountFor,
            selectSource: (show) {
              if (!detailRoute.isActive) return Future.value();
              _playback.activeAddonId = addon.id;
              return _sources.editOrSelectSource(
                show.withSourceAddon(addon),
                isCurrent: () => detailRoute.isActive,
              );
            },
            adoptArtwork: (art) => _playback.playbackArtwork.adopt(item, art),
            menus: menus,
            traktAction: (action, {rating}) => _details.trakt(
              item,
              addon,
              action,
              inCw: inCw,
              detailRoute: detailRoute,
              imdb: imdb,
              presetRating: rating,
            ),
            traktStatus:
                (menus.traktAuthenticated() &&
                    imdb != null &&
                    MediaIdentity.isImdb(imdb))
                ? () => readers.trakt(imdb, item.type, isCurrent: detailCurrent)
                : null,
            simklAction: (action, {rating}) => _details.simkl(
              item,
              action,
              detailRoute: detailRoute,
              presetRating: rating,
            ),
            simklStatus: (menus.simklAuthenticated() && imdb != null)
                ? () => readers.simkl(imdb, item.type, isCurrent: detailCurrent)
                : null,
            mdblistAction: (action, {rating}) => _details.mdblist(
              item,
              action,
              detailRoute: detailRoute,
              presetRating: rating,
            ),
            mdblistStatus:
                (menus.mdblistAuthenticated() &&
                    imdb != null &&
                    MediaIdentity.isImdb(imdb))
                ? () =>
                      readers.mdblist(imdb, item.type, isCurrent: detailCurrent)
                : null,
            recommendations: imdb != null && MediaIdentity.isImdb(imdb)
                ? () => readers.recommendations(
                    imdb,
                    item.type,
                    isCurrent: detailCurrent,
                  )
                : null,
            openRecommendation: (rec) =>
                openItem(rec, rec.sourceAddon ?? addon),
            enrich: (id, type) =>
                readers.metadata(id, type, isCurrent: detailCurrent),
          );
        },
      ),
    );
  }
}
