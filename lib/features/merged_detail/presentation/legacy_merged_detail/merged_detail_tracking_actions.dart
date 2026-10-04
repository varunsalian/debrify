import 'dart:async';
import 'package:debrify/features/merged_detail/application/merged_detail_simkl_labels.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_tracking_state.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/movie_completion_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MergedDetailTrackingActions {
  final MergedDetailDependencies _deps;
  MergedDetailTrackingActions(this._deps);
  bool get _isMovie => _deps.isMovie();
  StremioMeta get _item => _deps.presentedItem();
  bool get mounted => _deps.mounted();
  void Function(VoidCallback) get setState => _deps.setState;
  MergedDetailTrackingState get _k => _deps.parts.trackingState;

  /// Resolve the user's Trakt relationship to this title so the menu shows
  /// Add ↔ Remove toggles and the hero can badge Watchlist/Collection/Watched/
  /// rating. Silent on failure — the menu just stays add-only.
  Future<void> loadTraktStatus() async {
    final loader = _deps.traktStatusLoader();
    if (loader == null) return;
    try {
      final status = (await loader())?.preserveWatchedFrom(_k.traktStatus);
      if (!mounted || status == null) return;
      setState(() => _k.traktStatus = status);
    } catch (_) {
    } finally {
      // Resolved either way: a failed read is still an answered question as
      // far as the pill is concerned — it stops saying "Checking…" and falls
      // back to the untracked form rather than spinning forever.
      if (mounted && !_k.traktStatusResolved) {
        setState(() => _k.traktStatusResolved = true);
      }
    }
  }

  /// Resolve the user's Simkl relationship to this title — mirrors
  /// [_loadTraktStatus] exactly.
  Future<void> loadSimklStatus() async {
    final loader = _deps.simklStatusLoader();
    if (loader == null) return;
    try {
      final status = await loader();
      if (!mounted || status == null) return;
      setState(() => _k.simklStatus = status);
    } catch (_) {
    } finally {
      if (mounted && !_k.simklStatusResolved) {
        setState(() => _k.simklStatusResolved = true);
      }
    }
  }

  Future<void> loadMdblistStatus() async {
    final loader = _deps.mdblistStatusLoader();
    if (loader == null) return;
    try {
      final status = await loader();
      if (!mounted || status == null) return;
      setState(() => _k.mdblistStatus = status);
    } catch (_) {
    } finally {
      if (mounted && !_k.mdblistStatusResolved) {
        setState(() => _k.mdblistStatusResolved = true);
      }
    }
  }

  Future<void> loadLocalMovieFinished() async {
    final generation = ++_k.movieCompletionGeneration;
    if (!_isMovie) return;
    final imdbId =
        _item.effectiveImdbId ?? (_item.id.startsWith('tt') ? _item.id : null);
    if (imdbId == null || imdbId.isEmpty) return;
    final finished = await MovieCompletionService.load(imdbId);
    if (mounted &&
        generation == _k.movieCompletionGeneration &&
        finished != _k.localMovieFinished) {
      setState(() => _k.localMovieFinished = finished);
    }
  }

  void onMovieProgressPolicyChanged() {
    if (!mounted) return;
    setState(() => _k.localMovieFinished = false);
    loadLocalMovieFinished();
  }

  /// Whether Trakt holds any relationship to this title. Drives the pill's
  /// tinted (tracked) vs. outline (untracked) form.
  bool get traktTracked {
    final s = _k.traktStatus;
    return s != null &&
        (s.inWatchlist ||
            s.inCollection ||
            s.titleWatched == true ||
            s.rating != null);
  }

  bool get simklTracked =>
      _k.simklStatus?.currentStatus != null || _k.simklStatus?.rating != null;

  bool get mdblistTracked {
    final s = _k.mdblistStatus;
    return s != null &&
        (s.inWatchlist ||
            s.collected ||
            s.watched ||
            s.completed == true ||
            s.dropped == true ||
            s.rating != null);
  }

  /// The live Trakt state, compressed to fit inside the pill. Trakt allows
  /// several relationships at once, so they're joined with "·" and capped at
  /// two — the rating rides in the pill's own compartment, not here.
  ///
  /// While the loader is still out this reads "Checking…" rather than "Not
  /// tracked": the row keeps its geometry either way, and asserting the title
  /// *isn't* on your watchlist when it is — for however long the call takes —
  /// is worse than admitting we don't know yet.
  String get traktPillLabel {
    final s = _k.traktStatus;
    if (s == null &&
        !_k.traktStatusResolved &&
        _deps.traktStatusLoader() != null) {
      return 'Checking…';
    }
    if (s == null) return 'Not tracked';
    final parts = <String>[
      if (s.inWatchlist) 'Watchlist',
      if (s.inCollection) 'Collected',
      if (s.titleWatched == true) 'Watched',
    ];
    if (parts.isEmpty) {
      if (s.rating != null) return 'Rated';
      return s.titleWatched == null ? 'Status unavailable' : 'Not tracked';
    }
    return parts.take(2).join(' · ');
  }

  /// Simkl is single-state by definition, so its pill never needs to join
  /// anything — it's the one watchlist status, or nothing.
  String get simklPillLabel {
    final status = _k.simklStatus?.currentStatus;
    if (status != null) return MergedDetailSimklLabels.simklStatusLabel(status);
    if (_k.simklStatus?.rating != null) return 'Rated';
    if (!_k.simklStatusResolved && _deps.simklStatusLoader() != null) {
      return 'Checking…';
    }
    return 'Not tracked';
  }

  String get mdblistPillLabel {
    final s = _k.mdblistStatus;
    if (s == null &&
        !_k.mdblistStatusResolved &&
        _deps.mdblistStatusLoader() != null) {
      return 'Checking…';
    }
    if (s == null) return 'Not tracked';
    final parts = <String>[
      if (s.inWatchlist) 'Watchlist',
      if (s.collected) 'Collected',
      if (s.completed == true || s.watched) 'Watched',
      if (s.dropped == true) 'Dropped',
    ];
    if (parts.isEmpty) return s.rating == null ? 'Not tracked' : 'Rated';
    return parts.take(2).join(' · ');
  }
}
