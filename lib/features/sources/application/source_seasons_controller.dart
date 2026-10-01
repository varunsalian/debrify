import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/torrent.dart';
import '../data/source_seasons_repository.dart';
import '../models/source_seasons_state.dart';
import '../models/sources_session.dart';
import 'source_seasons.dart';
import 'sources_providers.dart';

final sourceSeasonsProvider = NotifierProvider.autoDispose
    .family<SourceSeasonsController, SourceSeasonsState, SourcesSession>(
      SourceSeasonsController.new,
      retry: (count, error) => null,
      dependencies: [
        sourceSeasonsRepositoryProvider,
        sourcesSessionActiveProvider,
      ],
    );

class SourceSeasonsController extends Notifier<SourceSeasonsState> {
  SourceSeasonsController(this.session);
  final SourcesSession session;
  late SourceSeasonsRepository _repository;
  int _generation = 0;

  @override
  SourceSeasonsState build() {
    _repository = ref.watch(sourceSeasonsRepositoryProvider(session));
    final active = ref.watch(sourcesSessionActiveProvider(session));
    ref.onDispose(() => _generation++);
    return SourceSeasonsState(
      selected: active ? session.selection.season : null,
    );
  }

  bool get _current => ref.mounted && _repository.isCurrent;

  Future<void> load() async {
    if (!_current ||
        !session.hasSeasonScope ||
        session.selection.imdbId.isEmpty) {
      return;
    }
    final generation = ++_generation;
    try {
      final guide = await _repository.load();
      if (!_current || generation != _generation || guide == null) return;
      // Inventory recording remains non-blocking; the menu need not wait for
      // preferences/progress recalculation. The adapter guards its commit edge.
      unawaited(_record(guide));
      if (guide.seasons.isNotEmpty) {
        state = SourceSeasonsState(
          selected: state.selected,
          available: guide.seasons,
          derived: state.derived,
        );
      }
    } catch (_) {
      // Keep the result-derived fallback when metadata is unavailable.
    }
  }

  Future<void> _record(SourceSeasonGuide guide) async {
    try {
      await guide.record();
    } catch (_) {
      debugPrint('Sources season inventory recording failed');
    }
  }

  bool select(int? selected) {
    if (!_current || state.selected == selected) return false;
    state = SourceSeasonsState(
      selected: selected,
      available: state.available,
      derived: state.derived,
    );
    return true;
  }

  void acceptResults(List<Torrent> full, {required bool unscoped}) {
    if (!_current || !session.hasSeasonScope || !unscoped) return;
    state = SourceSeasonsState(
      selected: state.selected,
      available: state.available,
      derived: deriveSourceSeasons(full),
    );
  }
}
