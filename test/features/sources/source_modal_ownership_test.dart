import 'package:debrify/features/sources/presentation/source_row_actions_sheet.dart';
import 'package:debrify/features/sources/presentation/source_toolbar_controls.dart';
import 'package:debrify/widgets/source_row.dart';
import 'package:debrify/widgets/torrent_filters_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/modal_sources_fixture.dart';

void main() {
  const actions = {
    'Play now': 'play',
    'Copy link': 'copy',
    'Pin as source': 'pin',
    'Download to device': 'download',
  };
  for (final retirement in ['active', 'disposed', 'profile']) {
    for (final action in actions.entries) {
      testWidgets('row menu $retirement owner: ${action.value}', (
        tester,
      ) async {
        final fixture = ModalSourcesFixture();
        await fixture.pump(tester);
        tester.widget<SourceRow>(find.byType(SourceRow)).onLongPress!();
        await tester.pumpAndSettle();
        await fixture.retire(tester, retirement);
        expect(find.byType(SourceRowActionsSheet), findsOneWidget);
        await tester.tap(find.text(action.key));
        await tester.pumpAndSettle();
        expect(fixture.calls, retirement == 'active' ? [action.value] : []);
        expect(find.byType(SourceRowActionsSheet), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('torrent menu rebuild survives its originating view', (
    tester,
  ) async {
    final fixture = ModalSourcesFixture();
    await fixture.pump(tester, direct: false);
    tester.widget<SourceRow>(find.byType(SourceRow)).onLongPress!();
    await tester.pumpAndSettle();
    await fixture.retire(tester, 'disposed');
    await fixture.rebuildModal(tester);
    expect(find.byType(SourceRowActionsSheet), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(fixture.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter dialog rebuild survives its originating view', (
    tester,
  ) async {
    final fixture = ModalSourcesFixture();
    await fixture.pump(tester);
    tester
        .widget<SourceToolbarControls>(find.byType(SourceToolbarControls))
        .onOpenFilters();
    await tester.pumpAndSettle();
    expect(find.byType(TorrentFiltersSheet), findsOneWidget);
    await fixture.retire(tester, 'disposed');
    await fixture.rebuildModal(tester);
    expect(find.byType(TorrentFiltersSheet), findsOneWidget);
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();
    expect(find.byType(TorrentFiltersSheet), findsNothing);
    expect(fixture.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final outcome in ['apply', 'cancel', 'profile']) {
    testWidgets('filter selection completion: $outcome', (tester) async {
      final fixture = ModalSourcesFixture();
      await fixture.pump(tester, direct: false);
      tester
          .widget<SourceToolbarControls>(find.byType(SourceToolbarControls))
          .onOpenFilters();
      await tester.pumpAndSettle();
      expect(
        find.text('Applies to movies only — ignored for series.'),
        findsOneWidget,
      );
      final qualityChip = find.widgetWithText(FilterChip, '720p');
      await tester.tap(qualityChip);
      await tester.pump();
      expect(tester.widget<FilterChip>(qualityChip).selected, isTrue);
      if (outcome == 'profile') await fixture.retire(tester, 'profile');
      if (outcome == 'cancel') {
        await tester.tap(find.byIcon(Icons.close_rounded));
      } else {
        await tester.tap(find.text('Apply Filters'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(TorrentFiltersSheet), findsNothing);
      if (outcome == 'apply') {
        expect(find.text('No matches for your filters.'), findsOneWidget);
        expect(
          tester
              .widget<SourceToolbarControls>(find.byType(SourceToolbarControls))
              .filtersActive,
          isTrue,
        );
      } else if (outcome == 'cancel') {
        expect(find.byType(SourceRow), findsOneWidget);
        expect(
          tester
              .widget<SourceToolbarControls>(find.byType(SourceToolbarControls))
              .filtersActive,
          isFalse,
        );
      } else {
        // clearAll retires action ownership without simulating route replacement.
        expect(find.byType(SourceRow), findsOneWidget);
        expect(
          tester
              .widget<SourceToolbarControls>(find.byType(SourceToolbarControls))
              .filtersActive,
          isFalse,
        );
      }
      expect(fixture.calls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final target in ['row menu', 'filters']) {
    testWidgets('retired view cannot open $target', (tester) async {
      final fixture = ModalSourcesFixture();
      await fixture.pump(tester);
      final open = target == 'row menu'
          ? tester.widget<SourceRow>(find.byType(SourceRow)).onLongPress!
          : tester
                .widget<SourceToolbarControls>(
                  find.byType(SourceToolbarControls),
                )
                .onOpenFilters;
      await fixture.retire(tester, 'disposed');
      open();
      await tester.pumpAndSettle();
      expect(find.byType(SourceRowActionsSheet), findsNothing);
      expect(find.byType(TorrentFiltersSheet), findsNothing);
      expect(fixture.calls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
