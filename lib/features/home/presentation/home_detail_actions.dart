import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/stremio_addon.dart';
import '../../../widgets/trakt/trakt_menu_helpers.dart';
import '../../../services/simkl/simkl_menu_helpers.dart'
    show SimklItemMenuAction;
import '../../../services/mdblist/mdblist_menu_helpers.dart'
    show MdblistItemMenuAction;
import '../application/home_detail_providers.dart';
import '../models/home_catalog_session.dart';
import 'home_detail_action_bridge.dart';
import 'home_detail_route.dart';
import 'home_catalog_actions.dart';
import 'home_playback_navigation.dart';
import 'home_source_actions.dart';

typedef HomeDetailActionsDeps = ({
  BuildContext Function() context,
  HomeCatalogSession Function() session,
  HomeDetailActionBridge Function(HomeDetailRoute) bridge,
  Future<void> Function(TraktItemMenuAction, String, HomeDetailRoute)
  removeLocal,
  Future<void> Function(String, {HomeDetailRoute? detailRoute}) removeTrakt,
  Future<void> Function(StremioMeta) removeMdblist,
  Future<void> Function(StremioMeta, SimklItemMenuAction, HomeDetailRoute, int?)
  invokeSimkl,
  Future<void> Function(
    StremioMeta,
    MdblistItemMenuAction,
    HomeDetailRoute,
    int?,
  )
  invokeMdblist,
});

/// Detail menu dispatch through the existing guarded action bridge.
class HomeDetailActions {
  HomeDetailActions(
    this._ref,
    this._deps,
    this._playback,
    this._catalog,
    this._sources,
  );
  final WidgetRef _ref;
  final HomeDetailActionsDeps _deps;
  final HomePlaybackNavigation _playback;
  final HomeCatalogActions _catalog;
  final HomeSourceActions _sources;

  Future<void> trakt(
    StremioMeta item,
    StremioAddon addon,
    TraktItemMenuAction action, {
    required bool inCw,
    required HomeDetailRoute detailRoute,
    String? imdb,
    int? presetRating,
  }) => _deps
      .bridge(detailRoute)
      .trakt(
        action,
        removeLocal: () async {
          if (imdb != null) {
            await _deps.removeLocal(action, imdb, detailRoute);
          }
        },
        removeTrakt: () async {
          if (imdb != null) {
            await _deps.removeTrakt(imdb, detailRoute: detailRoute);
          }
        },
        invoke: (clearOnly) async {
          if (clearOnly) {
            await handleTraktMenuAction(
              _deps.context(),
              item,
              action,
              actions: _ref.read(
                homeDetailActionsProvider(_deps.session().owner),
              ),
              isCurrent: _playback.catalogNavigationCurrent,
            );
            return;
          }
          _playback.activeAddonId = addon.id;
          await handleTraktMenuAction(
            _deps.context(),
            item.withSourceAddon(addon),
            action,
            onSelectSource: (item) => _playback.openSourceBinding(
              item,
              isCurrent: () => detailRoute.isActive,
            ),
            onEditSource: (item) => _sources.editOrSelectSource(
              item,
              isCurrent: () => detailRoute.isActive,
            ),
            onPlayRandomEpisode: (m) =>
                _catalog.playRandomEpisodeFromDetail(m, addon),
            onSearchPacks: _catalog.searchPacksFromDetail,
            onAddToStremioTv: (item) =>
                _catalog.addToStremioTvFromDetail(item, detailRoute),
            actions: _ref.read(
              homeDetailActionsProvider(_deps.session().owner),
            ),
            presetRating: presetRating,
            isCurrent: _playback.catalogNavigationCurrent,
            canPrompt: () => detailRoute.isActive,
          );
        },
      );

  Future<void> simkl(
    StremioMeta item,
    SimklItemMenuAction action, {
    required HomeDetailRoute detailRoute,
    int? presetRating,
  }) => _deps
      .bridge(detailRoute)
      .simkl(
        action,
        invoke: () =>
            _deps.invokeSimkl(item, action, detailRoute, presetRating),
      );

  Future<void> mdblist(
    StremioMeta item,
    MdblistItemMenuAction action, {
    required HomeDetailRoute detailRoute,
    int? presetRating,
  }) => _deps
      .bridge(detailRoute)
      .mdblist(
        action,
        remove: () => _deps.removeMdblist(item),
        invoke: () =>
            _deps.invokeMdblist(item, action, detailRoute, presetRating),
      );
}
