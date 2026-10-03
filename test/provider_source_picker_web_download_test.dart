import 'support/torbox_downloads_fixture.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:debrify/screens/alldebrid/alldebrid_files_screen.dart';
import 'package:debrify/screens/debrid_downloads_screen.dart';
import 'package:debrify/screens/torbox/torbox_downloads_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Real-Debrid source picker exposes torrent and DDL libraries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DebridDownloadsScreen(
          isPushedRoute: true,
          selectSourceMode: true,
          onSourceSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Torrent Downloads'), findsOneWidget);
    expect(find.text('DDL Downloads'), findsOneWidget);

    await tester.tap(find.text('DDL Downloads'));
    await tester.pumpAndSettle();

    expect(find.text('Error Loading DDL Downloads'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('TorBox source picker exposes torrent and web libraries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TorboxDownloadsScreen(
          isPushedRoute: true,
          initialSearchQuery: 'Movie title',
          selectSourceMode: true,
          onSourceSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Torrents'), findsOneWidget);
    expect(find.text('Web Downloads'), findsOneWidget);
    expect(find.text('Movie title'), findsOneWidget);

    await tester.tap(find.text('Web Downloads'));
    await tester.pumpAndSettle();

    expect(find.text('Movie title'), findsNothing);
    expect(find.textContaining('view web downloads'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('AllDebrid source picker exposes magnet and web libraries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AllDebridFilesScreen(
          isPushedRoute: true,
          selectSourceMode: true,
          onSourceSelected: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Torrent Downloads'), findsOneWidget);
    expect(find.text('Web Downloads'), findsOneWidget);

    await tester.tap(find.text('Web Downloads'));
    await tester.pumpAndSettle();

    expect(
      find.text('Add your AllDebrid API key in Settings first.'),
      findsOneWidget,
    );
  });
  torboxSelectionCharacterization();
}

// TorBox's original HTTP-backed pushed-route selection contracts.
void torboxSelectionCharacterization() {
  for (final web in [false, true]) {
    testWidgets(
      'TorBox pushed picker web=$web returns identity once and pops',
      (tester) => torboxCase(tester, (f) async {
        final selected = <dynamic>[];
        await f.mount(
          tester,
          pushed: true,
          picker: true,
          query: web ? null : 'Library',
          selected: selected.add,
        );
        if (web) {
          await tester.tap(find.text('Web Downloads'));
          await tester.pumpAndSettle();
        } else {
          await tester.pumpAndSettle();
          expect(
            (f.member('torrentSearchController') as TextEditingController).text,
            'Library',
          );
        }
        final before = DateTime.now().millisecondsSinceEpoch;
        await tester.tap(find.text(web ? 'Library 11' : 'Library 1'));
        await tester.pumpAndSettle();
        final after = DateTime.now().millisecondsSinceEpoch;
        expect(selected.length, 1);
        final source = selected.single;
        expect(source.debridService, 'torbox');
        expect(source.debridTorrentId, web ? '11' : '1');
        expect(source.torrentHash, web ? '' : 'hash-1');
        expect(source.torrentName, web ? 'Library 11' : 'Library 1');
        expect(
          source.cloudSourceKind,
          web ? SeriesSource.cloudKindWebDownload : null,
        );
        expect(source.boundAt, inInclusiveRange(before, after));
        expect(f.key.currentState, isNull);
        expect(find.text('Caller'), findsOneWidget);
      }),
    );
  }
  testWidgets(
    'TorBox web picker row without playable files is disabled',
    (tester) => torboxCase(tester, (f) async {
      f.web = [torboxRow(11, files: 0)];
      var count = 0;
      await f.mount(
        tester,
        pushed: true,
        picker: true,
        selected: (_) => count++,
      );
      await tester.tap(find.text('Web Downloads'));
      await tester.pumpAndSettle();
      final row = tester.widget<CloudFileRow>(find.byType(CloudFileRow));
      expect(row.onTap, isNull);
      await tester.tap(find.text('Library 11'));
      await tester.pumpAndSettle();
      expect(count, 0);
      expect(f.key.currentState, isNotNull);
    }),
  );
}
