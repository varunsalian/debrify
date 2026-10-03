import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'debrid_downloads_fixture.dart';

void debridSelectionCharacterization() {
  for (final source in ['list', 'search', 'ddl']) {
    testWidgets(
      'pushed picker $source callback identity count pop and toolbars',
      (t) => debridCase(t, (f) async {
        final selected = <dynamic>[];
        await f.mount(
          t,
          pushed: true,
          picker: true,
          query: source == 'search' ? 'Library' : null,
          selected: selected.add,
        );
        await t.pumpAndSettle();
        if (source == 'ddl') await f.ddl(t);
        expect(find.text('Select Source from Real-Debrid'), findsOneWidget);
        expect(find.text('Select'), findsNothing);
        expect(find.byTooltip('Add Magnet'), findsNothing);
        if (source == 'search') {
          expect(
            (f.member('torrentSearchController') as TextEditingController).text,
            'Library',
          );
          expect(f.member('torrentSearchQuery'), 'Library');
          expect(f.member('isTorrentSearchActive'), isTrue);
          expect(
            f.requests
                .where(
                  (r) =>
                      r.method == 'GET' &&
                      r.url.path == '/rest/1.0/torrents' &&
                      r.url.queryParameters['limit'] == '2000',
                )
                .map((r) => r.url.queryParameters['page']),
            ['1'],
          );
          expect(
            (f.member('filteredSearchTorrents') as List).map(
              (dynamic row) => row.id,
            ),
            contains('z9'),
          );
          f.member('toggleTorrentSearch')();
          expect(f.member('isTorrentSearchActive'), isTrue);
        }
        final before = DateTime.now().millisecondsSinceEpoch;
        await t.tap(
          find.text(source == 'ddl' ? 'Download w8.mkv' : 'Library z9'),
        );
        await t.pumpAndSettle();
        final after = DateTime.now().millisecondsSinceEpoch;
        expect(selected.length, 1);
        final s = selected.single;
        expect(s.debridService, 'rd');
        expect(s.debridTorrentId, source == 'ddl' ? 'w8' : 'z9');
        expect(s.torrentHash, source == 'ddl' ? '' : 'hash-z9');
        expect(
          s.torrentName,
          source == 'ddl' ? 'Download w8.mkv' : 'Library z9',
        );
        expect(
          s.cloudSourceKind,
          source == 'ddl' ? SeriesSource.cloudKindWebDownload : null,
        );
        expect(s.boundAt, inInclusiveRange(before, after));
        expect(f.key.currentState, isNull);
        expect(find.text('Caller'), findsOneWidget);
      }),
    );
  }
  testWidgets(
    'nonplayable DDL picker is disabled',
    (t) => debridCase(t, (f) async {
      f.downloads = [debridDownload('w8', playable: false)];
      var count = 0;
      await f.mount(t, pushed: true, picker: true, selected: (_) => count++);
      await f.ddl(t);
      expect(t.widget<CloudFileRow>(find.byType(CloudFileRow)).onTap, isNull);
      await t.tap(find.text('Archive w8.zip'));
      await t.pumpAndSettle();
      expect(count, 0);
      expect(f.key.currentState, isNotNull);
    }),
  );
  testWidgets(
    'streamable zero mkv DDL picker remains enabled by extension',
    (t) => debridCase(t, (f) async {
      f.downloads = [debridDownload('w8')..['streamable'] = 0];
      final selected = <dynamic>[];
      await f.mount(t, pushed: true, picker: true, selected: selected.add);
      await f.ddl(t);
      expect(
        t.widget<CloudFileRow>(find.byType(CloudFileRow)).onTap,
        isNotNull,
      );
      await t.tap(find.text('Download w8.mkv'));
      await t.pumpAndSettle();
      expect(selected.length, 1);
      expect(selected.single.debridTorrentId, 'w8');
      expect(f.key.currentState, isNull);
      expect(find.text('Caller'), findsOneWidget);
    }),
  );
  testWidgets(
    'hidden provider rejects changed title query',
    (t) => debridCase(t, (f) async {
      await RealDebridStorage.setRealDebridHiddenFromNav(true);
      await f.mount(t, pushed: true, picker: true, query: 'Library');
      await t.pumpAndSettle();
      expect(f.member('hiddenFromNav'), isTrue);
      final before = f.requests.length;
      (f.member('torrentSearchController') as TextEditingController).text =
          'Unrelated';
      f.member('submitTorrentSearch')();
      await t.pump();
      expect(f.member('torrentSearchQuery'), 'Library');
      expect(f.requests.length, before);
    }),
  );
}
