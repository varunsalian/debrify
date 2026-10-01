import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/advanced_search_selection.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/trakt_continue_watching_item.dart';
import '../../../screens/stremio_tv/widgets/stremio_tv_catalog_picker_dialog.dart';
import '../models/home_catalog_session.dart';
import '../models/home_series_resume_signals.dart';
import '../data/home_series_resume_repository.dart';
import '../data/home_tracking_policy_repository.dart';
import '../application/home_playback_providers.dart';
import '../application/home_detail_providers.dart';
import 'home_detail_route.dart';
import 'home_playback_navigation.dart';
import 'home_catalog_play_action.dart';
import 'home_random_playback_action.dart';

typedef HomeCatalogActionsDeps = ({
  bool Function() mounted,
  bool Function() profileCurrent,
  BuildContext Function() context,
  HomeCatalogSession Function() session,
  String? Function(StremioMeta) imdbOf,
  HomeResumeAvailability Function() availability,
  TraktContinueWatchingItem? Function(StremioMeta) cachedTrakt,
});

/// Catalog target resolution and detail-only play actions, using existing adapters.
class HomeCatalogActions {
  HomeCatalogActions(this._ref, this._deps, this._playback);
  final WidgetRef _ref;
  final HomeCatalogActionsDeps _deps;
  final HomePlaybackNavigation _playback;
  Future<void> addToStremioTvFromDetail(
    StremioMeta item,
    HomeDetailRoute route,
  ) async {
    bool current() => _playback.catalogNavigationCurrent() && route.isActive;
    if (!current()) return;
    final context = _deps.context();
    final result = await StremioTvCatalogPickerDialog.show(
      context,
      item: item,
      isCurrent: current,
    );
    if (!current() || result == null) return;
    _playback.snack(result.message);
  }

  void searchPacksFromDetail(StremioMeta item) {
    final imdb = _deps.imdbOf(item);
    if (imdb == null) {
      _playback.snack('No IMDb match to find packs for "${item.name}".');
      return;
    }
    _playback.browseSelection(
      AdvancedSearchSelection(
        imdbId: imdb,
        isSeries: true,
        title: item.name,
        year: item.year,
        contentType: item.type,
        posterUrl: item.poster,
      ),
    );
  }

  Future<void> playRandomEpisodeFromDetail(
    StremioMeta item,
    StremioAddon addon,
  ) {
    bool current() => _deps.mounted() && _deps.profileCurrent();
    if (!current()) return Future.value();
    final context = _deps.context();
    return runHomeRandomPlayback(
      context: context,
      item: item,
      addon: addon,
      isCurrent: current,
      prepare: (continuous) => _ref
          .read(homeRandomPlaybackRepositoryProvider(_deps.session().owner))
          .prepare(
            item: item,
            addon: addon,
            progressId: _deps.imdbOf(item),
            continuous: continuous,
            isCurrent: current,
          ),
      showMessage: _playback.snack,
      launch: _playback.playSelection,
    );
  }

  Future<void> onCatalogPlay(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
    bool startFromBeginning = false,
    bool skipEpisodeFallback = false,
    bool preferTraktResume = false,
    ({bool started, int season, int episode})? promisedTarget,
    bool browseSourcesOnly = false,
    bool Function()? isCurrent,
  }) async {
    bool current() =>
        _playback.catalogNavigationCurrent() && (isCurrent?.call() ?? true);
    if (!current()) return;
    final context = _deps.context();
    await HomeCatalogPlayAction(
      log: debugPrint,
      origin: _ref.read(
        homeCatalogOriginRepositoryProvider(_deps.session().owner),
      ),
      policies: _ref.read(
        homeTrackingPolicyRepositoryProvider(_deps.session().owner),
      ),
      targets: _ref.read(homeCatalogPlaybackResolverProvider(_deps.session())),
      identity: _ref.read(
        homeCatalogEpisodeIdentityProvider(_deps.session().owner),
      ),
      artwork: _playback.playbackArtwork,
    ).run(
      context,
      item,
      addon,
      isCurrent: current,
      availability: _deps.availability,
      cachedTrakt: _deps.cachedTrakt,
      showMessage: _playback.snack,
      activateAddon: (id) => _playback.activeAddonId = id,
      openEpisodes: _playback.openEpisodes,
      browse: _playback.browseSelection,
      play: _playback.playSelection,
      isTraktSource: isTraktSource,
      isMdblistSource: isMdblistSource,
      startFromBeginning: startFromBeginning,
      skipEpisodeFallback: skipEpisodeFallback,
      preferTraktResume: preferTraktResume,
      promisedTarget: promisedTarget,
      browseSourcesOnly: browseSourcesOnly,
    );
  }

  HomeSeriesResumeRepository get seriesResumeRepository =>
      _ref.read(homeSeriesResumeRepositoryProvider(_deps.session().owner));

  Future<HomeResumePosition> resolveResumeInfo(
    StremioMeta item,
    StremioAddon addon, {
    bool isTraktSource = false,
    bool isMdblistSource = false,
  }) => HomeTrackingPolicyRepository.resolveLabel(
    loadPolicy: () async {
      bool current() => _deps.mounted() && _deps.profileCurrent();
      if (!current()) return null;
      return _ref
          .read(homeTrackingPolicyRepositoryProvider(_deps.session().owner))
          .loadForContent(item.progressId, isCurrent: current);
    },
    isCurrent: _playback.catalogNavigationCurrent,
    label: (trackingPolicy) => _ref
        .read(homeCatalogPlaybackResolverProvider(_deps.session()))
        .label(
          item,
          addon,
          trackingPolicy: trackingPolicy,
          availability: _deps.availability,
          cachedTrakt: () => _deps.cachedTrakt(item),
          isCurrent: _playback.catalogNavigationCurrent,
          isTraktSource: isTraktSource,
          isMdblistSource: isMdblistSource,
        ),
  );
}
