import 'package:debrify/widgets/cinema_sources_layout.dart';
import 'package:debrify/widgets/source_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/modal_sources_fixture.dart';

void main() {
  for (final bindMode in [false, true]) {
    testWidgets('compact/cinema roundtrip retains search and rows: $bindMode', (
      tester,
    ) async {
      final fixture = ModalSourcesFixture();
      await fixture.pump(tester, bindMode: bindMode);
      final initial = tester.widget<SourceRow>(find.byType(SourceRow));
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(CinemaSourcesLayout), findsNothing);
      expect(fixture.searchRequests, 1);

      for (final size in [const Size(960, 700), const Size(500, 900)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpAndSettle();
        final row = tester.widget<SourceRow>(find.byType(SourceRow));
        expect(row.focusNode, same(initial.focusNode));
        expect(row.title, initial.title);
        expect(row.showPlayPill, !bindMode);
        expect(row.cinemaLayout, size.width >= 600);
        expect(fixture.searchRequests, 1);
        if (size.width >= 600) {
          expect(find.byType(AppBar), findsNothing);
          final cinema = tester.widget<CinemaSourcesLayout>(
            find.byType(CinemaSourcesLayout),
          );
          expect(cinema.title, bindMode ? 'Pick a source' : 'Choose a source');
          expect(cinema.contextTitle, 'Fixture');
          expect(cinema.resultCount, 1);
        } else {
          expect(find.byType(AppBar), findsOneWidget);
          expect(find.byType(CinemaSourcesLayout), findsNothing);
        }
        expect(tester.takeException(), isNull);
      }
      tester.widget<SourceRow>(find.byType(SourceRow)).onCopy!();
      await tester.pumpAndSettle();
      expect(fixture.calls, ['copy']);
    });
  }
}
