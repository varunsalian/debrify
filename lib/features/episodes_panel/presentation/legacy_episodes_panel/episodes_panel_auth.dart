import 'dart:async';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_services.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/services/mdblist/mdblist_continue_watching_service.dart';
import 'package:flutter/material.dart';

class EpisodesPanelAuth {
  final EpisodesPanelDeps _deps;
  EpisodesPanelAuth(this._deps);
  EpisodesPanelViewState get _s => _deps.parts.viewState;
  EpisodesPanelServices get _sv => _deps.parts.services;
  bool get mounted => _deps.mounted();

  /// Whether a Trakt account is connected. This screen is reachable from
  /// Discover/catalog without Trakt, so the Trakt-only episode menu (mark
  /// watched/unwatched, rate) is only offered when this is true.
  bool traktAuthenticated = false;

  bool get isTraktAuthenticated =>
      traktAuthenticated &&
      !CustomSeriesIdentity.isCustom((_s.selectedShow ?? _deps.show()).imdbId);

  /// Whether Simkl is connected, for watched-action destinations and options.
  bool simklAuthenticated = false;

  bool mdblistAuthenticated = false;

  bool get isSimklAuthenticated =>
      simklAuthenticated &&
      !CustomSeriesIdentity.isCustom((_s.selectedShow ?? _deps.show()).imdbId);

  bool get isMdblistAuthenticated =>
      mdblistAuthenticated &&
      !CustomSeriesIdentity.isCustom((_s.selectedShow ?? _deps.show()).imdbId);

  // MDBList can acknowledge a completed scrobble just before the player route
  // finishes popping, and its watched snapshot can trail that acknowledgement
  // briefly. Keep only the newest mutation refresh, wait until this panel's
  // route is visible, then perform one consistency retry. Without this, the
  // pre-stop refresh could leave a completed episode showing its old local
  // progress until the detail page was reopened.
  int mdblistRefreshToken = 0;

  void onMdblistPlaybackRevision() {
    if (!mounted || isDirectSource) return;
    MdblistContinueWatchingService.instance.invalidate();
    final token = ++mdblistRefreshToken;
    unawaited(refreshAfterMdblistMutation(token));
  }

  Future<void> refreshAfterMdblistMutation(int token) async {
    // A successful stop is reported while the player route may still cover the
    // detail page. Do not discard that notification; wait for the pop instead.
    for (var attempt = 0; attempt < 20; attempt++) {
      if (!mounted || token != mdblistRefreshToken) return;
      if (ModalRoute.of(_deps.context())?.isCurrent ?? true) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted || token != mdblistRefreshToken) return;
    if (!(ModalRoute.of(_deps.context())?.isCurrent ?? true)) return;

    // MDBList's /scrobble/stop response can precede /sync/watched becoming
    // readable, so an immediate refetch can paint pre-mutation data — wait out
    // the propagation window and do ONE authoritative refresh. (This used to
    // refresh immediately AND again after the delay; the first pass only ever
    // showed data the second pass replaced, at double the tracker requests.)
    await Future<void>.delayed(const Duration(milliseconds: 750));
    if (!mounted || token != mdblistRefreshToken) return;
    if (!(ModalRoute.of(_deps.context())?.isCurrent ?? true)) return;
    await _deps.refreshWatchProgress();
  }

  /// Direct-source mode (see [EpisodesPanel.seasonsLoader]) — episodes are
  /// playable URLs with no IMDb identity, so every IMDb-keyed pathway is off.
  bool get isDirectSource => _deps.seasonsLoader() != null;

  /// Resolve whether a Trakt account is connected (gates the episode menu).
  Future<void> resolveTraktAuth() async {
    if (isDirectSource) return; // no IMDb id — the Trakt menu can't act
    final authed = await _sv.traktService.isAuthenticated();
    if (mounted && authed != isTraktAuthenticated) {
      _deps.setState(() => traktAuthenticated = authed);
    }
  }

  /// Resolve whether a Simkl account is connected — mirrors [_resolveTraktAuth].
  Future<void> resolveSimklAuth() async {
    if (isDirectSource) return; // mirrors _resolveTraktAuth
    final authed = await _sv.simklService.isAuthenticated();
    if (mounted && authed != isSimklAuthenticated) {
      _deps.setState(() => simklAuthenticated = authed);
    }
  }

  Future<void> resolveMdblistAuth() async {
    if (isDirectSource) return;
    final authed = await _sv.mdblistService.isAuthenticated();
    if (mounted && authed != isMdblistAuthenticated) {
      _deps.setState(() => mdblistAuthenticated = authed);
    }
  }
}
