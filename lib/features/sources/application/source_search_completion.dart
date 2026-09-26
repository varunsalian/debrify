import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/advanced_search_selection.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/sources_session.dart';
import 'source_results_controller.dart';
import 'source_seasons_controller.dart';

enum SourceCompletionResult { retired, keepProjection, rebuildProjection }

final sourceSearchCompletionProvider = Provider<SourceSearchCompletion>(
  SourceSearchCompletion.new,
  dependencies: [sourceResultsProvider, sourceSeasonsProvider],
);

/// Explicit final-result bookkeeping; never adopts rows or dispatches UI effects.
class SourceSearchCompletion {
  SourceSearchCompletion(this._ref);
  final Ref _ref;

  SourceCompletionResult complete(
    SourcesSession session, {
    required AdvancedSearchSelection selection,
    required bool hasSeasonScope,
    required Map<String, String> aliases,
  }) {
    if (!_ref.mounted || session.owner != ProfileSessionMemory.captureOwner()) {
      return SourceCompletionResult.retired;
    }
    final results = _ref.read(sourceResultsProvider(session));
    // Include parked rows; a scoped search must not shrink the fallback menu.
    final fullSet = results.pending ?? results.displayed;
    if (hasSeasonScope && selection.season == null) {
      _ref
          .read(sourceSeasonsProvider(session).notifier)
          .acceptResults(fullSet, unscoped: true);
    }
    // Only the authoritative completion can remove a previous provider filter.
    final changed = _ref
        .read(sourceResultsProvider(session).notifier)
        .reconcileProvider(fullSet, aliases);
    return changed && _ref.read(sourceResultsProvider(session)).pending == null
        ? SourceCompletionResult.rebuildProjection
        : SourceCompletionResult.keepProjection;
  }
}
