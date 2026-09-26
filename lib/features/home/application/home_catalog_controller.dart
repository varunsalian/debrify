import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/stremio_addon.dart';
import '../models/home_catalog_plan.dart';
import '../models/home_catalog_state.dart';
import '../models/home_catalog_session.dart';

final homeCatalogProvider = NotifierProvider.autoDispose
    .family<HomeCatalogController, HomeCatalogState, HomeCatalogSession>(
      HomeCatalogController.new,
      retry: (count, error) => null,
      dependencies: const [],
    );

/// Owns one view's catalog inventory, reservation and accepted snapshot.
/// Loading generations/profile acceptance remain with the calling workflow.
class HomeCatalogController extends Notifier<HomeCatalogState> {
  HomeCatalogController(this.session);
  final HomeCatalogSession session;

  @override
  HomeCatalogState build() {
    final initial = session.initialBoard;
    return initial == null
        ? const HomeCatalogState.empty()
        : const HomeCatalogState.empty().copyWith(
            references: initial.references,
            cursor: initial.cursor,
            committed: initial,
          );
  }

  // Pending legacy refresh loops can finish after their view is removed. They
  // see an exhausted inventory, without reading disposed provider state.
  HomeCatalogState get current =>
      ref.mounted ? state : const HomeCatalogState.empty();

  void install(List<HomeCatalogReference> references) {
    if (!ref.mounted) return;
    state = state.copyWith(references: references, cursor: 0);
  }

  List<HomeCatalogReference> reserve(int count) {
    if (!ref.mounted) return const [];
    final end = (state.cursor + count).clamp(0, state.references.length);
    final batch = state.references.sublist(state.cursor, end);
    state = state.copyWith(cursor: end);
    return batch;
  }

  void commit(Map<String, StremioAddon> addons) {
    if (!ref.mounted) return;
    state = state.copyWith(
      committed: HomeCatalogSnapshot(state.references, state.cursor, addons),
    );
  }

  /// Restoring a return snapshot or timeout recovery never adopts an in-flight
  /// reservation. The caller restores its shared metadata lookup from addons.
  void restore(HomeCatalogSnapshot snapshot) {
    if (!ref.mounted) return;
    state = state.copyWith(
      references: snapshot.references,
      cursor: snapshot.cursor,
      committed: snapshot,
    );
  }
}
