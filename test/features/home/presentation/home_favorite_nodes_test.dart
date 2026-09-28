import 'package:debrify/features/home/presentation/home_favorite_nodes.dart';
import 'package:debrify/features/home/models/home_favorite_row_ref.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final kind in [
    HomeFavoriteKind.watchlistMovies,
    HomeFavoriteKind.playlist,
  ]) {
    testWidgets(
      'removing focused last $kind card retains remaining node identity',
      (tester) async {
        final owner = HomeFavoriteNodes();
        var fallback = 0;
        void sync(int count) => owner.sync(
          kind,
          count,
          isCurrent: () => true,
          onEmpty: () => fallback++,
        );
        Widget view() => Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              for (final node in owner.nodes(kind))
                Focus(focusNode: node, child: const SizedBox()),
            ],
          ),
        );
        sync(2);
        final first = owner.nodes(kind).first;
        await tester.pumpWidget(view());
        owner.nodes(kind).last.requestFocus();
        await tester.pump();
        sync(1);
        await tester.pumpWidget(view());
        await tester.pump();
        expect(owner.nodes(kind).single, same(first));
        expect(first.hasFocus, isTrue);
        sync(0);
        await tester.pumpWidget(view());
        await tester.pump();
        expect(fallback, kind == HomeFavoriteKind.watchlistMovies ? 1 : 0);
        await tester.pumpWidget(const SizedBox());
        owner.disposeNodes();
        owner.clearNodes();
      },
    );
  }
}
