import 'package:debrify/features/home/models/home_favorite_row_ref.dart';
import 'package:debrify/features/home/presentation/home_rail_composition.dart';
import 'package:debrify/features/home/presentation/home_stage_rows.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'rail projection skips empty/unready rows and mounts queue nodes once',
    () {
      final node = FocusNode();
      addTearDown(node.dispose);
      const item = StremioMeta(id: 'one', type: 'movie', name: 'One');
      HomeContinuationRow row(List<StremioMeta> items) => HomeContinuationRow(
        rowId: 'cw:local',
        title: 'Continue',
        tag: null,
        kind: HomeContinuationKind.local,
        items: items,
        nodes: [node],
        progressOf: (_) => null,
        episodeOf: (_) => null,
        remainingMinutesOf: (_) => null,
        episodeArtworkOf: (_) => null,
        onOpen: (_) {},
        onQuickPlay: (_) {},
        onRemove: (_) async {},
      );
      final populated = row([item, item]);
      const favorite = HomeFavoriteRowRef(HomeFavoriteKind.iptv);
      final rails = HomeRailComposition.canonical(
        continuation: [row([]), populated],
        favorites: [
          favorite,
          const HomeFavoriteRowRef(HomeFavoriteKind.playlist),
        ],
        favoriteCount: (ref) => ref == favorite ? 1 : 0,
        sectionCount: 3,
        nodeRowCount: 2,
        sectionHasItems: (i) => i != 0,
        rowId: (rail) => rail.cw?.rowId ?? 'other',
      );
      expect(rails.length, 3);
      final cw = rails.singleWhere((rail) => rail.cw != null);
      expect(cw.cw, same(populated));
      expect(cw.cwIndex, 1);
      expect(
        rails.singleWhere((rail) => rail.sectionIndex != null).sectionIndex,
        1,
      );
      final queue = HomeRailComposition.tonightQueue(rails);
      expect(queue.length, 1); // The second item has no focus node yet.
      expect(queue.single.rail, same(cw));
      expect(queue.single.col, 0);
      expect(
        HomeRailComposition.stage(rails, tonight: true),
        isNot(contains(cw)),
      );
      expect(HomeRailComposition.stage(rails, tonight: false), same(rails));
      final classic = HomeRailComposition.classic(
        canonical: [
          cw,
          const HomeRail(favKind: favorite),
        ],
        reserveTrakt: true,
        mergeTrakt: false,
        disabled: {'trakt:movies'},
      );
      expect(classic.first, same(cw));
      expect(classic[1].traktSkeletonIndex, 1);
      expect(classic.last.favKind, favorite);
      expect(
        HomeRailComposition.classic(
          canonical: rails,
          reserveTrakt: true,
          mergeTrakt: true,
          disabled: {'trakt:movies'},
        ).where((rail) => rail.traktSkeletonIndex >= 0),
        isEmpty,
      );
    },
  );
}
