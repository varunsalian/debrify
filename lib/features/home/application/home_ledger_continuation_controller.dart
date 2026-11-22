import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_ledger_continuation_reader.dart';
import '../models/home_continuation_session.dart';
import '../models/home_ledger_continuation.dart';
import 'home_continuation_providers.dart';

final homeLedgerContinuationProvider = NotifierProvider.autoDispose
    .family<
      HomeLedgerContinuationController,
      HomeLedgerContinuation,
      HomeContinuationSession
    >(
      HomeLedgerContinuationController.new,
      retry: (count, error) => null,
      dependencies: [homeLedgerContinuationReaderProvider],
    );

/// Owns the accepted Ledger shelf and request retirement, like the Simkl
/// controller: no startup reads or automatic retries; the view keeps focus,
/// artwork and navigation effects.
class HomeLedgerContinuationController
    extends Notifier<HomeLedgerContinuation> {
  HomeLedgerContinuationController(this.session);
  final HomeContinuationSession session;
  late HomeLedgerContinuationReader _read;
  int _generation = 0;

  @override
  HomeLedgerContinuation build() {
    _read = ref.watch(homeLedgerContinuationReaderProvider);
    ref.onDispose(() => _generation++);
    return const HomeLedgerContinuation.empty();
  }

  HomeLedgerContinuation get current =>
      ref.mounted ? state : const HomeLedgerContinuation.empty();

  Future<void> load({
    required bool Function() isCurrent,
    required void Function(HomeLedgerContinuation next) beforeRows,
    required void Function(
      HomeLedgerContinuation next,
      bool hadRows,
      bool Function() isCurrent,
    )
    onRows,
  }) async {
    final generation = ++_generation;
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        session.owner == ProfileSessionMemory.captureOwner() &&
        isCurrent();
    if (!current()) return;
    final items = await _read();
    if (!current() || items == null) return;
    final next = HomeLedgerContinuation.fromItems(items);
    final hadRows = !state.isEmpty;
    // Nothing to publish (the usual case without a Ledger account): keep the
    // board exactly as it is — no rebuild, focus pass or badge refresh.
    if (!hadRows && next.isEmpty) return;
    beforeRows(next);
    if (!current()) return;
    state = next;
    onRows(next, hadRows, current);
  }
}
