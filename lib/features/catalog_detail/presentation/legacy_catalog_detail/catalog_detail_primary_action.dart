import 'dart:async';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_dependencies.dart';
import 'package:debrify/services/movie_completion_service.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/widgets/rewatch_progress_dialog.dart';

class CatalogDetailPrimaryAction {
  final CatalogDetailDependencies _deps;

  CatalogDetailPrimaryAction(this._deps);

  CatalogDetailPrimaryAction get _p => _deps.parts.primaryAction;

  /// Primary-button resume state. Until loaded the button keeps its static "Play"
  /// label; once resolved it reads "Start Watching" (no progress) or "Resume"
  /// (+ an "S3E4" tag for series). Re-read when the player pops back.
  bool resumeLoaded = false;

  bool resumeStarted = false;

  int? resumeSeason;

  int? resumeEpisode;

  /// A resume lookup is in flight and unanswered. The primary button shows a
  /// spinner instead of a label so it never flashes "Start Watching" before
  /// flipping to "Resume · S1E7". Errors clear it (static label fallback).
  bool resumePending = false;

  bool get primaryBusy => resumePending && !resumeLoaded;

  /// Live Simkl status (drives the "Rewatch" relabel). Null until
  /// [simklStatusLoader] resolves — the button keeps "Play" until then.
  SimklTitleStatus? _simklStatus;

  // Completion from the selected Progress source(s), not Home tick settings.
  bool localMovieFinished = false;

  /// Policy-filtered completion shared across local and all three trackers.
  bool get isCompletedMovie =>
      _deps.presentedItem().type != 'series' && localMovieFinished;

  Future<void> loadSimklStatus() async {
    final loader = _deps.simklStatusLoader();
    if (loader == null) return;
    try {
      final status = await loader();
      if (!_deps.mounted() || status == null) return;
      _deps.setState(() => _simklStatus = status);
    } catch (_) {
      // Non-critical — leave the plain "Play" label.
    }
  }

  Future<void> loadLocalMovieFinished() async {
    final generation = ++movieCompletionGeneration;
    if (_deps.presentedItem().type == 'series') return;
    final imdbId =
        _deps.presentedItem().effectiveImdbId ??
        (_deps.presentedItem().id.startsWith('tt')
            ? _deps.presentedItem().id
            : null);
    if (imdbId == null || imdbId.isEmpty) return;
    final finished = await MovieCompletionService.load(imdbId);
    if (_deps.mounted() &&
        generation == movieCompletionGeneration &&
        finished != localMovieFinished) {
      _deps.setState(() => localMovieFinished = finished);
    }
  }

  int movieCompletionGeneration = 0;

  void onMovieProgressPolicyChanged() {
    if (!_deps.mounted()) return;
    _deps.setState(() => localMovieFinished = false);
    loadLocalMovieFinished();
  }

  Future<void> loadResumeInfo() async {
    final loader = _deps.resumeInfoLoader();
    if (loader == null) return;
    // setState, not a plain assignment — this runs from the post-init loader
    // fan (setState-safe), and the spinner must actually be scheduled to
    // paint rather than riding a sibling loader's rebuild.
    if (!resumeLoaded && _deps.mounted()) {
      _deps.setState(() => resumePending = true);
    }
    try {
      // Time-boxed: the guide advance inside the reconciler can hang on an
      // unbounded body read; a timeout throws into catch/finally, falling
      // back to the static label instead of spinning forever.
      final info = await loader().timeout(const Duration(seconds: 12));
      if (!_deps.mounted()) return;
      _deps.setState(() {
        resumeLoaded = true;
        resumeStarted = info.started;
        resumeSeason = info.season;
        resumeEpisode = info.episode;
      });
    } catch (_) {
      // Non-critical — leave the static label.
    } finally {
      if (resumePending) {
        if (_deps.mounted()) {
          _deps.setState(() => resumePending = false);
        } else {
          resumePending = false;
        }
      }
    }
  }

  /// The primary-button label: "Start Watching" before any progress, otherwise
  /// "Resume" with an OTT-style "· S3E4" tag for series. Falls back to the
  /// static "Play" until the resume state resolves.
  String get primaryLabel =>
      _deps.onRewatch() == null && resolvedPrimaryLabel == 'Rewatch'
      ? 'Play'
      : resolvedPrimaryLabel;

  String get resolvedPrimaryLabel {
    if (rewatchPending) return 'Rewatch';
    final isMovie = _deps.presentedItem().type != 'series';
    // Some entry points (for example the catalog browser) intentionally omit
    // a resume loader. Local/Simkl completion is still enough to distinguish
    // a new play from a rewatch, so do not hide that state behind the optional
    // resume lookup.
    if (!resumeLoaded) return isCompletedMovie ? 'Rewatch' : 'Play';
    if (!resumeStarted) {
      if (isCompletedMovie) return 'Rewatch';
      return isMovie ? 'Play' : 'Start Watching';
    }
    if (isMovie || resumeSeason == null || resumeEpisode == null) {
      return 'Resume';
    }
    return 'Resume · S${_p.resumeSeason}E${_p.resumeEpisode}';
  }

  bool rewatchPending = false;

  bool rewatchBusy = false;

  Future<void> playPrimary() async {
    if (rewatchBusy) return;
    final restart = _deps.onRewatch();
    if (restart == null ||
        _deps.presentedItem().type == 'series' ||
        primaryLabel != 'Rewatch') {
      _deps.onPlay()();
      return;
    }
    rewatchBusy = true;
    try {
      final cleared = await resetProgressForRewatch(
        _deps.context(),
        id: _deps.presentedItem().imdbId ?? _deps.presentedItem().id,
        title: _deps.presentedItem().name,
        isMovie: true,
        onConfirmed: () => _deps.setState(() => rewatchPending = true),
      );
      if (!_deps.mounted() || !cleared) return;
      ++movieCompletionGeneration; // Discard reads started before the reset.
      _deps.setState(() {
        rewatchPending = false;
        localMovieFinished = false;
        _simklStatus = null;
        resumeStarted = false;
      });
      restart();
    } finally {
      rewatchBusy = false;
    }
  }
}
