import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/addon_search_status.dart';
import '../../../models/advanced_search_selection.dart';
import '../../../models/torrent.dart';
import '../../../services/source_ordering.dart';
import '../../../services/torrent_result_merge.dart';
import '../data/source_search_repository.dart';
import '../models/source_search_request.dart';
import '../models/source_search_state.dart';
import '../models/sources_session.dart';
import '../models/webdav_source_status.dart';
import 'source_cache_controller.dart';
import 'source_results_controller.dart';
import 'source_retry_controller.dart';
import 'sources_providers.dart';

enum SourceRetryMode { ignore, restartSearch, addon }

final sourceSearchProvider = NotifierProvider.autoDispose
    .family<SourceSearchController, SourceSearchState, SourcesSession>(
      SourceSearchController.new,
      retry: (count, error) => null,
      dependencies: [
        sourceSearchRepositoryProvider,
        sourcesSessionActiveProvider,
        sourceCacheProvider,
        sourceRetryProvider,
        sourceResultsProvider,
      ],
    );

class SourceSearchController extends Notifier<SourceSearchState> {
  SourceSearchController(this.session);
  final SourcesSession session;
  late SourceSearchRepository _repository;
  final List<List<Torrent>> _batches = [];

  /// The completed result plus WebDAV rows that arrived after it, in that
  /// order, so late rows append instead of reshuffling the finished list.
  List<Torrent> _completed = const [];
  int _generation = 0;

  @override
  SourceSearchState build() {
    _repository = ref.watch(sourceSearchRepositoryProvider(session));
    ref.watch(sourcesSessionActiveProvider(session));
    _generation++;
    _batches.clear();
    ref.onDispose(() {
      _generation++;
      _batches.clear();
    });
    return SourceSearchState();
  }

  bool _accept(int generation) =>
      ref.mounted && _repository.isCurrent && generation == _generation;

  List<Torrent> _merge() => List.unmodifiable(
    mergeTorrentResults(_batches, preserveSourceOrder: true),
  );

  /// Reset query-owned results and background work before the view replaces
  /// focus resources. Search dispatch follows that synchronous view reset.
  bool prepareSearch() {
    if (!ref.mounted || !_repository.isCurrent) return false;
    ref.read(sourceCacheProvider(session).notifier).beginSearch();
    ref.read(sourceRetryProvider(session).notifier).beginSearch();
    ref.read(sourceResultsProvider(session).notifier).beginSearch();
    return true;
  }

  /// Media-server chips restart the whole search only when it is idle.
  SourceRetryMode retryMode(AddonSearchStatus status) {
    if (!ref.mounted || !_repository.isCurrent) return SourceRetryMode.ignore;
    if (status.sourceKey.startsWith('mediaserver:')) {
      return state.searching
          ? SourceRetryMode.ignore
          : SourceRetryMode.restartSearch;
    }
    return SourceRetryMode.addon;
  }

  /// Merge accepted addon retries through the same batch owner as live search.
  /// The view still adopts rows and schedules their cache check, in that order.
  Future<void> retryAddon(
    AdvancedSearchSelection selection,
    AddonSearchStatus status, {
    required bool Function() shouldContinue,
    required void Function(List<Torrent>) onRows,
    required void Function(List<Torrent>) onBatchAccepted,
  }) async {
    final generation = _generation;
    bool active() => _accept(generation) && shouldContinue();
    if (!active() || retryMode(status) != SourceRetryMode.addon) return;
    final batch = await ref
        .read(sourceRetryProvider(session).notifier)
        .retry(selection, status);
    if (batch == null || !active()) return;
    final rows = acceptRetry(status, batch);
    if (rows == null) return;
    onRows(rows);
    onBatchAccepted(batch);
  }

  /// Explicit search action. Callbacks hand accepted rows to presentation and
  /// cache checks in their original order; no context, focus or navigation is
  /// retained in state. Final rows remain authoritative, not a batch union.
  Future<void> search(
    SourceSearchRequest request, {
    required List<String> priority,
    required Map<String, String> aliases,
    required void Function(List<Torrent> rows, bool complete) onRows,
    required void Function(List<Torrent> batch) onBatchAccepted,
    bool Function()? shouldContinue,
  }) async {
    if (!ref.mounted || !_repository.isCurrent) return;
    final generation = ++_generation;
    bool active() => _accept(generation) && (shouldContinue?.call() ?? true);
    if (!active()) return;
    _batches.clear();
    _completed = const [];
    state = SourceSearchState(searching: true);
    try {
      final result = await _repository.search(
        request,
        // WebDAV outlives the main result, so this tracks the generation only.
        shouldContinue: active,
        onBatch: (source, batch) {
          if (!active() || batch.isEmpty) return;
          if (state.searching) {
            _batches.add(List.unmodifiable(batch));
            onRows(_merge(), false);
            if (active() && state.searching) onBatchAccepted(batch);
            return;
          }
          // Only WebDAV keeps searching after completion. Its late rows are
          // appended to the finished list; the batch union keeps them for a
          // later addon retry too.
          if (!source.startsWith('webdav:')) return;
          _batches.add(List.unmodifiable(batch));
          _completed = _appendCompleted(batch);
          onRows(_completed, false);
          if (active()) onBatchAccepted(batch);
        },
        onIptvResult: (result) {
          if (!active() || !state.searching) return;
          state = SourceSearchState(
            searching: true,
            addonStatuses: state.addonStatuses,
            iptv: [...state.iptv, result],
            webDav: state.webDav,
          );
        },
        onWebDavStatus: (status) {
          if (!active()) return;
          state = SourceSearchState(
            searching: state.searching,
            error: state.error,
            addonStatuses: state.addonStatuses,
            iptv: state.iptv,
            webDav: _withWebDav(state.webDav, status),
          );
        },
      );
      if (result == null || !active()) return;
      _completed = result.torrents;
      state = SourceSearchState(
        iptv: result.iptv,
        // Live statuses are at least as new as the result's snapshot.
        webDav: state.webDav.isEmpty ? result.webDav : state.webDav,
        addonStatuses: SourceOrdering.orderBy(
          result.addonStatuses
              .where(
                (status) =>
                    !SourceOrdering.isRecommendationOnlyAddon(status.addonId),
              )
              .toList(growable: false),
          (status) => status.sourceKey,
          priority,
          aliases: aliases,
        ),
      );
      onRows(result.torrents, true);
    } catch (error) {
      if (!active()) return;
      state = SourceSearchState(
        error: error.toString(),
        addonStatuses: state.addonStatuses,
        iptv: state.iptv,
        webDav: state.webDav,
      );
    }
  }

  /// Retry completion uses accumulated engine batches, as before. In
  /// particular, the final authoritative response is not seeded as a batch.
  List<Torrent>? acceptRetry(AddonSearchStatus status, List<Torrent> batch) {
    if (!_accept(_generation)) return null;
    state = SourceSearchState(
      searching: state.searching,
      error: state.error,
      iptv: state.iptv,
      webDav: state.webDav,
      addonStatuses: [
        for (final current in state.addonStatuses)
          current.requestKey == status.requestKey
              ? status.withResult(batch.length)
              : current,
      ],
    );
    if (batch.isEmpty) return null;
    _batches.add(List.unmodifiable(batch));
    // Late WebDAV rows build on the completed list; keep retried rows in it.
    if (!state.searching) _completed = _appendCompleted(batch);
    return _merge();
  }

  List<Torrent> _appendCompleted(List<Torrent> batch) => List.unmodifiable(
    mergeTorrentResults([_completed, batch], preserveSourceOrder: true),
  );
}

/// Replaces [status]'s server entry in place, keeping first-seen order.
List<WebDavSourceStatus> _withWebDav(
  List<WebDavSourceStatus> current,
  WebDavSourceStatus status,
) {
  final index = current.indexWhere((entry) => entry.key == status.key);
  if (index < 0) return [...current, status];
  return [...current]..[index] = status;
}
