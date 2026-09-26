import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/torrent.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/source_results_state.dart';
import '../models/sources_session.dart';
import 'source_seasons_dependencies.dart';

final sourceResultsProvider = NotifierProvider.autoDispose
    .family<SourceResultsController, SourceResultsState, SourcesSession>(
      SourceResultsController.new,
      retry: (count, error) => null,
    );

/// Owns when prepared rows become adopted results. Rendering and focus stay
/// in the view; search generations are checked before offering a batch.
class SourceResultsController extends Notifier<SourceResultsState> {
  SourceResultsController(this.session);
  final SourcesSession session;

  @override
  SourceResultsState build() {
    ref.watch(sourcesSessionActiveProvider(session));
    return SourceResultsState();
  }

  bool get _active =>
      ref.mounted && session.owner == ProfileSessionMemory.captureOwner();

  void beginSearch() {
    if (!_active) return;
    state = SourceResultsState();
  }

  void freeze() {
    if (!_active || state.frozen) return;
    state = SourceResultsState(
      displayed: state.displayed,
      pending: state.pending,
      frozen: true,
    );
  }

  /// Park the full replacement once the user has interacted. A new batch
  /// replaces pending rows, rather than accumulating obsolete pending sets.
  bool bufferIfFrozen(List<Torrent> rows) {
    if (!_active || !state.frozen) return false;
    state = SourceResultsState(
      displayed: state.displayed,
      pending: rows,
      frozen: true,
    );
    return true;
  }

  /// Explicit display/adoption, after the view has captured its old focus.
  void display(List<Torrent> rows) {
    if (!_active) return;
    state = SourceResultsState(displayed: rows, frozen: state.frozen);
  }
}
