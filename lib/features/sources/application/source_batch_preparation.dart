import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/advanced_search_selection.dart';
import '../../../models/torrent.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/sources_session.dart';
import 'saved_sources_controller.dart';
import 'sources_providers.dart';
import 'source_result_preparation.dart';
import 'source_search_controller.dart';

final sourceBatchPreparationProvider = Provider<SourceBatchPreparation>(
  SourceBatchPreparation.new,
  dependencies: [
    sourceSearchProvider,
    savedSourcesProvider,
    sourceBindingMatcherProvider,
  ],
);

/// Stateless application operation. Reads current scoped inputs without adopting
/// rows or retaining results; presentation captures focus before explicit adoption.
class SourceBatchPreparation {
  SourceBatchPreparation(this._ref);
  final Ref _ref;

  ({List<Torrent> torrents, bool cachedEpisodeInserted})? prepare(
    SourcesSession session,
    List<Torrent> raw, {
    required AdvancedSearchSelection selection,
    required bool bindMode,
  }) {
    if (!_ref.mounted || session.owner != ProfileSessionMemory.captureOwner()) {
      return null;
    }
    final saved = _ref.read(savedSourcesProvider(session));
    return prepareSourceResults(
      raw,
      selection: selection,
      bindMode: bindMode,
      isIptvSource: _ref.read(sourceBindingMatcherProvider).isIptv,
      searching: _ref.read(sourceSearchProvider(session)).searching,
      cachedEpisodeSource: saved.cachedEpisode,
      bound: saved.sources,
    );
  }
}
