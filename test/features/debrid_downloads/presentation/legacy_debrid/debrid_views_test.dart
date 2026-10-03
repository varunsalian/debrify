import 'dart:io';
import 'package:debrify/models/rd_file_node.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/debrid_downloads_fixture.dart';

const captureLinux = bool.fromEnvironment('DEBRID_CAPTURE_ORIGINAL_LINUX');
const captureMac = bool.fromEnvironment('DEBRID_CAPTURE_ORIGINAL_MACOS');
const requireLinux = bool.fromEnvironment(
  'DEBRID_REQUIRE_ORIGINAL_LINUX',
  defaultValue: false,
);
void main() {
  testWidgets(
    'Raw A-Z order and deep folder search use fresh state',
    (t) => debridCase(t, (f) async {
      await f.mount(t);
      await f.member('navigateIntoTorrent')(f.torrent('z9'));
      await t.pumpAndSettle();
      expect(
        (f.member('currentViewNodes') as List<RDFileNode>).map((n) => n.name),
        ['Zebra.mkv', 'Alpha.mkv', 'Nested'],
      );
      f.member('setViewMode')(f.member('sortedMode'));
      await t.pump();
      expect(
        (f.member('currentViewNodes') as List<RDFileNode>).map((n) => n.name),
        ['Nested', 'Alpha.mkv', 'Zebra.mkv'],
      );
      f.member('setViewMode')(f.member('rawMode'));
      await t.pump();
      expect(
        (f.member('currentViewNodes') as List<RDFileNode>).map((n) => n.name),
        ['Zebra.mkv', 'Alpha.mkv', 'Nested'],
      );
      f.member('performSearch')('s02e03');
      await t.pump();
      final results = f.member('searchResults') as List;
      expect(results.length, 1);
      expect(results.single.node.name, 'Show.S02E03.mkv');
      expect(results.single.path, 'Nested');
      f.member('performSearch')('absent');
      await t.pump();
      expect(f.member('searchResults'), isEmpty);
    }),
  );
  testWidgets(
    'dormant series arrangement and parsing retain nonmonotonic order',
    (t) => debridCase(t, (f) async {
      await f.mount(t);
      final nodes = [
        for (final name in [
          'Show.S02E10.mkv',
          'Show.S01E02.mkv',
          'Show.S02E01.mkv',
        ])
          RDFileNode.file(
            name: name,
            bytes: 1,
            fileId: 71,
            path: name,
            linkIndex: 0,
          ),
      ];
      final arranged =
          f.member('applySeriesArrangedView')(nodes) as List<RDFileNode>;
      expect(arranged.map((n) => n.name), ['Season 1', 'Season 2']);
      expect(arranged[1].children.map((n) => n.name), [
        'Show.S02E01.mkv',
        'Show.S02E10.mkv',
      ]);
      expect(f.member('extractSeasonNumber')('Chapter_12'), 12);
      expect(f.member('extractSeasonNumber')('Season 10'), 10);
      expect(f.member('extractSeasonNumber')('Other'), isNull);
      expect(f.member('extractLeadingNumber')('05_Episode.mp4'), 5);
      expect(f.member('extractLeadingNumber')('Episode 05.mp4'), isNull);
    }),
  );
  for (final ddl in [false, true]) {
    testWidgets(
      'scroll paging ddl=$ddl limit and page',
      (t) => debridCase(t, (f) async {
        if (ddl) {
          f.downloads = [for (var i = 0; i < 50; i++) debridDownload('d-$i')];
        } else {
          f.torrents = [for (var i = 0; i < 50; i++) debridTorrent('t-$i')];
        }
        await f.mount(t);
        if (ddl) await f.ddl(t);
        final c =
            f.member(
                  ddl ? 'downloadScrollController' : 'torrentScrollController',
                )
                as ScrollController;
        c.jumpTo(c.position.maxScrollExtent);
        await t.pumpAndSettle();
        final req = f.requests
            .where((r) => r.url.path.endsWith(ddl ? '/downloads' : '/torrents'))
            .toList();
        expect(req.map((r) => r.url.queryParameters['page']), ['1', '2']);
        expect(req.map((r) => r.url.queryParameters['limit']), ['50', '50']);
        expect(f.member(ddl ? 'downloadPage' : 'torrentPage'), 3);
        expect(f.member(ddl ? 'hasMoreDownloads' : 'hasMoreTorrents'), isFalse);
      }),
    );
    testWidgets(
      'reset during scroll detaches paging and reattaches once ddl=$ddl',
      (t) => debridCase(t, (f) async {
        f.torrents = [for (var i = 0; i < 50; i++) debridTorrent('t-$i')];
        f.downloads = [for (var i = 0; i < 50; i++) debridDownload('d-$i')];
        f.fullPages = true;
        await f.mount(t);
        if (ddl) await f.ddl(t);
        final c =
            f.member(
                  ddl ? 'downloadScrollController' : 'torrentScrollController',
                )
                as ScrollController;
        final path = ddl ? '/downloads' : '/torrents';
        List<String?> pages() => f.requests
            .where((r) => r.url.path.endsWith(path))
            .map((r) => r.url.queryParameters['page'])
            .toList();
        c.position.correctPixels(c.position.maxScrollExtent);
        f.member('resetListScroll')();
        await t.pump();
        expect(c.offset, 0);
        expect(pages(), ['1']);
        // Detached callback can be counted without inspecting private notifier storage:
        // remove the expected tear-off once; a duplicate would still page at bottom.
        final callback =
            f.member(ddl ? 'onDownloadScroll' : 'onTorrentScroll')
                as VoidCallback;
        c.removeListener(callback);
        c.jumpTo(c.position.maxScrollExtent);
        await t.pump();
        expect(pages(), ['1']);
        c.addListener(callback);
        c.jumpTo(0);
        c.jumpTo(c.position.maxScrollExtent);
        await t.pumpAndSettle();
        expect(pages(), ['1', '2']);
        expect((c as dynamic).hasListeners, isTrue);
      }),
    );
  }
  for (final error in [false, true]) {
    testWidgets(
      'empty and error lists error=$error',
      (t) => debridCase(t, (f) async {
        f.torrents = [];
        f.downloads = [];
        f.failLists = error;
        await f.mount(t);
        expect(
          find.textContaining(
            error
                ? 'Error Loading Torrent Downloads'
                : 'No torrent downloads yet',
          ),
          findsWidgets,
        );
        await f.ddl(t);
        expect(
          find.textContaining(
            error ? 'Error Loading DDL Downloads' : 'No DDL downloads yet',
          ),
          findsWidgets,
        );
      }),
    );
  }
  testWidgets(
    'torrent search caps three 2000 pages and filters actual results',
    (t) => debridCase(t, (f) async {
      await f.mount(t);
      f.fullPages = true;
      f.torrents = [for (var i = 0; i < 2000; i++) debridTorrent('q-$i')];
      f.member('toggleTorrentSearch')();
      (f.member('torrentSearchController') as TextEditingController).text =
          'q-1999';
      f.member('submitTorrentSearch')();
      await f.until(t, () => f.member('isLoadingSearch') == false);
      await t.pumpAndSettle();
      final req = f.requests
          .where((r) => r.url.queryParameters['limit'] == '2000')
          .toList();
      expect(req.map((r) => r.url.queryParameters['page']), ['1', '2', '3']);
      expect(
        (f.member('filteredSearchTorrents') as List).map((dynamic r) => r.id),
        ['q-1999'],
      );
      expect(f.member('torrentSearchQuery'), 'q-1999');
    }),
  );
  for (final view in [
    'torrents',
    'ddl',
    'folder',
    'selection',
    'select_source',
  ]) {
    final host = Platform.isLinux ? 'linux' : 'macos';
    final path = 'test/goldens/debrid_downloads/$host/$view.png';
    testWidgets(
      'reachable pixel golden $view',
      (t) => debridCase(t, (f) async {
        await f.mount(t, picker: view == 'select_source');
        if (view == 'folder') {
          await f.member('navigateIntoTorrent')(f.torrent('z9'));
        }
        if (view == 'ddl') await f.ddl(t);
        if (view == 'selection') f.member('toggleSelectionMode')();
        await t.pump(const Duration(milliseconds: 600));
        await t.pump();
        expect(t.takeException(), isNull);
        if (!captureLinux && !captureMac) {
          expect(
            File(path).existsSync(),
            isTrue,
            reason: 'Original $host golden missing: $path',
          );
        }
        await expectLater(
          find.byKey(const ValueKey('debrid-canvas')),
          matchesGoldenFile(
            '../../../../goldens/debrid_downloads/$host/$view.png',
          ),
        );
      }),
      skip:
          Platform.isLinux &&
          !captureLinux &&
          !requireLinux &&
          !File(path).existsSync(),
    );
  }
}
