import '../application/home_row_order.dart';
import '../models/home_favorite_row_ref.dart';
import 'home_stage_rows.dart';

/// Home's shared rail projection. Descriptors borrow the original rows/nodes;
/// ordering never copies the underlying content or creates focus resources.
abstract final class HomeRailComposition {
  static List<HomeRail> canonical({
    required List<HomeContinuationRow> continuation,
    required List<HomeFavoriteRowRef> favorites,
    required int Function(HomeFavoriteRowRef) favoriteCount,
    required int sectionCount,
    required int nodeRowCount,
    required bool Function(int) sectionHasItems,
    required String Function(HomeRail) rowId,
  }) {
    final rails = <HomeRail>[];
    for (var i = 0; i < continuation.length; i++) {
      if (continuation[i].items.isEmpty) continue;
      rails.add(HomeRail(cw: continuation[i], cwIndex: i));
    }
    for (final ref in favorites) {
      if (favoriteCount(ref) == 0) continue;
      rails.add(HomeRail(favKind: ref));
    }
    for (var i = 0; i < sectionCount; i++) {
      if (!sectionHasItems(i) || i >= nodeRowCount) continue;
      rails.add(HomeRail(sectionIndex: i));
    }
    return HomeRowOrder.defaults(rails, rowId);
  }

  static List<HomeRail> classic({
    required List<HomeRail> canonical,
    required bool reserveTrakt,
    required bool mergeTrakt,
    required Set<String> disabled,
  }) {
    if (!reserveTrakt) return canonical;
    final skeletons = <HomeRail>[
      if (!disabled.contains('trakt:movies'))
        const HomeRail(traktSkeletonIndex: 0),
      if (!mergeTrakt && !disabled.contains('trakt:shows'))
        const HomeRail(traktSkeletonIndex: 1),
    ];
    // Placeholders follow the real continuation block in the built-in order.
    // The host applies the saved order afterwards, including placeholder ids.
    return HomeRowOrder.insertAfterLeadingRun(
      canonical,
      skeletons,
      (rail) => rail.cw != null,
    );
  }

  static List<HomeTonightQueueEntry> tonightQueue(List<HomeRail> rails) {
    final out = <HomeTonightQueueEntry>[];
    for (final rail in rails) {
      final cw = rail.cw;
      if (cw == null) continue;
      for (var col = 0; col < cw.items.length && col < cw.nodes.length; col++) {
        out.add(HomeTonightQueueEntry(rail: rail, col: col));
      }
    }
    return out;
  }

  /// Tonight renders continuation nodes only in its separate queue.
  static List<HomeRail> stage(List<HomeRail> rails, {required bool tonight}) =>
      tonight
      ? [
          for (final rail in rails)
            if (rail.cw == null) rail,
        ]
      : rails;
}
