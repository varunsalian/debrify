import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/advanced_search_selection.dart';
import '../../../models/series_source.dart';
import '../../../models/torrent.dart';
import '../application/saved_sources_controller.dart';
import '../application/source_batch_preparation.dart';
import '../application/source_binding_match_dependencies.dart';
import '../application/source_results_controller.dart';
import '../application/source_search_completion.dart';
import '../application/source_selection_match.dart';
import '../application/source_settings_controller.dart';
import '../models/source_presentation_settings.dart';
import '../models/sources_session.dart';
import 'source_results_focus.dart';
import 'source_row_focus_nodes.dart';

/// Per-view rendered projection and its focus transition ordering. Controllers
/// retain authoritative results, buffering and toolbar state. Focus resources,
/// subscription lifetime and loading/rebuild ownership stay with the view.
class SourceResultsPresentation {
  SourceResultsPresentation({
    required this.ref,
    required this.session,
    required this.focus,
    required this.rowFocus,
    required this.selection,
    required this.bindMode,
    required this.hasSeasonScope,
    required this.isTelevision,
    required this.isMounted,
    required this.searchToken,
    required this.redesign,
    required this.onChanged,
    required this.checkCache,
    required this.onEvent,
  });

  final WidgetRef ref;
  final SourcesSession session;
  final SourceResultsFocus focus;
  final SourceRowFocusNodes rowFocus;
  final AdvancedSearchSelection Function() selection;
  final bool Function() bindMode;
  final bool Function() hasSeasonScope;
  final bool Function() isTelevision;
  final bool Function() isMounted;
  final int Function() searchToken;
  final bool redesign;
  final void Function(bool finishLoading) onChanged;
  final void Function() checkCache;
  final void Function(String, Map<String, Object?>) onEvent;

  List<Torrent> _visible = [];
  Torrent? _selectedDirect;
  bool _showCachedEpisodeSource = false;
  List<Torrent> get visible => _visible;
  Torrent? get selected => _selectedDirect;
  bool get showCachedEpisode => _showCachedEpisodeSource;

  SourceResultsController get _resultsController =>
      ref.read(sourceResultsProvider(session).notifier);
  List<Torrent> get _torrents =>
      ref.read(sourceResultsProvider(session)).displayed;

  /// Post-processed FULL result set waiting behind the pill while frozen.
  List<Torrent>? get _pendingTorrents =>
      ref.read(sourceResultsProvider(session)).pending;
  bool get _streamFrozen => ref.read(sourceResultsProvider(session)).frozen;
  List<SeriesSource> get _bound =>
      ref.read(savedSourcesProvider(session)).sources;
  Torrent? get _cachedEpisodeSource =>
      ref.read(savedSourcesProvider(session)).cachedEpisode;
  SourcePresentationSettings get _settings =>
      ref.read(sourceSettingsProvider(session));
  Map<String, String> get _sourceAliases => _settings.priority.aliases;
  List<FocusNode> get _nodes => rowFocus.nodes;

  void resetForSearch() {
    rowFocus.resetForSearch();
    // An IPTV status can expose the body before the first non-empty batch.
    // Never retain rows whose focus nodes were just disposed.
    _visible = [];
  }

  void clearRetiredProfile() {
    _visible = [];
    _syncStreamNodes();
  }

  void updateSelected() {
    final matcher = ref.read(sourceBindingMatcherProvider);
    final match = matchSelectedSource(
      saved: _bound,
      torrents: _torrents,
      mediaServerKeyFor: matcher.mediaServerKeyFor,
      isIptvSource: matcher.isIptv,
    );
    _selectedDirect = match.source;
    if (match.diagnostics case final diagnostics?) {
      onEvent('match', diagnostics);
    }
  }

  // Lazy rows have no Focus context until built. Walk the viewport until the
  // target mounts, then align precisely using its actual (variable) height.
  Future<void> revealSelected({bool preserveFocus = false}) => focus.reveal(
    _selectedDirect == null ? null : _visible.indexOf(_selectedDirect!),
    preserveFocus: preserveFocus,
  );

  /// Post-processes a (provisional or final) raw result set exactly like the
  /// pre-streaming search did, then either applies it to the list or — when
  /// the user has started interacting ([_streamFrozen]) — parks it behind the
  /// "+N new sources" pill so rows never reshuffle mid-read.
  void present(List<Torrent> raw, int token) {
    if (!isMounted() || token != searchToken()) return;
    final prepared = ref
        .read(sourceBatchPreparationProvider)
        .prepare(session, raw, selection: selection(), bindMode: bindMode());
    if (prepared == null) return;
    final torrents = prepared.torrents;
    if (prepared.cachedEpisodeInserted) {
      onEvent('cached_episode_inserted', const {});
    }
    if (_resultsController.bufferIfFrozen(torrents)) {
      onEvent('batch_buffered', {'pending_results': torrents.length});
      if (isMounted()) onChanged(false); // pill count / banner update
      return;
    }
    _applyStreamingResults(torrents);
  }

  /// Swaps the displayed result set, preserving the focused row BY IDENTITY
  /// across the reshuffle (a late engine can insert rows above the D-pad
  /// focus; without this the remote lands on a different torrent).
  void _applyStreamingResults(List<Torrent> torrents) {
    focus.cancelReveal();
    // Identity-preserving refocus only makes sense for USER-placed focus —
    // i.e. after a freeze (adopt-pending / toolbar paths). During live
    // streaming the only focus is the programmatic TV anchor on row 0;
    // following it by identity would drag the viewport down as better rows
    // insert above (review round: "the anchor is not user intent").
    Torrent? focusedTorrent;
    if (_streamFrozen) {
      for (var i = 0; i < _nodes.length && i < _visible.length; i++) {
        if (_nodes[i].hasFocus) {
          focusedTorrent = _visible[i];
          break;
        }
      }
    }
    _resultsController.display(torrents);
    updateSelected();
    _showCachedEpisodeSource = torrents.any(
      (t) => identical(t, _cachedEpisodeSource),
    );
    _visible = redesign ? _applyToolbar(_torrents) : _torrents;
    _syncStreamNodes();
    onEvent('focus_decision', {
      'reason': focusedTorrent != null
          ? 'preserve_user_focus'
          : _streamFrozen
          ? 'user_interaction'
          : _selectedDirect == null
          ? 'no_match'
          : !_visible.contains(_selectedDirect)
          ? 'match_filtered_or_deduplicated'
          : 'reveal_match',
    });
    if (isMounted()) {
      onChanged(true);
    }
    if (focusedTorrent != null) {
      final idx = _visible.indexWhere(
        (t) =>
            identical(t, focusedTorrent) ||
            (t.hasRealInfoHash &&
                t.infohash.isNotEmpty &&
                t.infohash == focusedTorrent!.infohash),
      );
      if (idx >= 0) {
        focus.restoreAfterFrame(idx);
      }
    } else if (!_streamFrozen && _visible.contains(_selectedDirect)) {
      unawaited(revealSelected());
    } else if (isTelevision() && !_streamFrozen) {
      // Live streaming on TV: keep the remote anchored to the TOP row (the
      // best-ranked source right now) — the anchor exists from the first
      // batch instead of waiting for the slowest engine.
      focus.anchorStreamingAfterFrame();
    }
  }

  /// Grows/shrinks [_nodes] to match [_visible] without ever disposing the
  /// focused node unanchored. Removed nodes are disposed POST-FRAME — their
  /// row widgets are still mounted this frame, and unmounting a Focus widget
  /// whose node is already disposed asserts (same rule rebuildVisible
  /// documents).
  void _syncStreamNodes() => rowFocus.resize(_visible.length);

  /// Completion-only steps: season snapshot, cache badges, TV focus anchor.
  void complete(int token) {
    if (!isMounted() || token != searchToken()) return;
    final result = ref
        .read(sourceSearchCompletionProvider)
        .complete(
          session,
          selection: selection(),
          hasSeasonScope: hasSeasonScope(),
          aliases: _sourceAliases,
        );
    if (result == SourceCompletionResult.retired) return;
    if (result == SourceCompletionResult.rebuildProjection) {
      _visible = redesign ? _applyToolbar(_torrents) : _torrents;
      _syncStreamNodes();
    }
    // Final result set: sweep any hash not yet dispatched by a streaming batch
    // (non-blocking). In-flight batch checks share this generation and merge as
    // they land, so already-shown badges never flicker off.
    onChanged(true);
    checkCache();
    // On TV give the D-pad an initial anchor when nothing is focused yet.
    // With ZERO rows (e.g. a season scope with no packs) anchor the filter
    // funnel instead so the remote can still reach the toolbar and recover.
    // Never steal focus the user already placed somewhere mid-stream.
    focus.anchorCompletionAfterFrame();
  }

  /// First real user interaction → stop live-reshuffling; buffer new arrivals
  /// behind the pill instead.
  void freeze() {
    focus.cancelReveal();
    _resultsController.freeze();
  }

  /// Folds the parked result set into the list (pill tap / toolbar use) and
  /// refreshes the ⚡ badges for the fresh rows.
  void adoptPending() {
    final p = _pendingTorrents;
    if (p == null) return;
    _applyStreamingResults(p);
    // Parked rows were already badged as their batches streamed in; this is a
    // cheap additive mop-up for any straggler hash (skips already-checked).
    checkCache();
  }

  /// Derives the rendered list from [_torrents]: source-group filter →
  /// quality/rip/language filter → provider priority + stable dedupe →
  /// optional explicit field sort. "Addon order" is the default.
  List<Torrent> _applyToolbar(List<Torrent> src) =>
      _resultsController.project(src, _settings.priority);

  /// Recompute [_visible] and rebuild [_nodes] in lock-step after a toolbar
  /// change (source pill, sort, or filter). The ListView stays mounted (no
  /// loading flip), so the old nodes are disposed AFTER the rebuild frame —
  /// letting each reused row State and its Focus widget migrate onto the new
  /// node first (disposing mid-frame would assert / drop the listener).
  ///
  /// Deliberately does NOT move D-pad focus: this is always triggered from a
  /// toolbar control (pill / sort / funnel) which keeps its own focus. Yanking
  /// focus into the list would both disorient the user AND let the SELECT that
  /// triggered the change land on the newly-focused first row — activating it
  /// (adding the first result to the debrid) as an unwanted "double tap".
  void rebuildVisible() {
    // Toolbar use is a deliberate reshuffle: freeze live streaming updates
    // and fold any parked arrivals in first, so the user filters/sorts the
    // complete set they can see.
    freeze();
    if (_pendingTorrents != null) {
      _resultsController.display(_pendingTorrents!);
      checkCache();
    }
    _visible = _applyToolbar(_torrents);
    updateSelected();
    rowFocus.replaceAll(_visible.length);
    if (isMounted()) onChanged(false);
  }
}
