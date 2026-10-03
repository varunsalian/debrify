import 'dart:io';
import 'package:debrify/models/rd_file_node.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/torbox_downloads_fixture.dart';

void main() {
  testWidgets(
    'raw and A-Z folder order and deep search matching',
    (t) => torboxCase(t, (f) async {
      await f.mount(t);
      f.member('navigateIntoTorrent')(f.torrent(1));
      await t.pumpAndSettle();
      final raw = (f.member('currentItems') as List<RDFileNode>)
          .map((n) => n.name)
          .toList();
      expect(raw, ['Zebra.mkv', 'Alpha.mkv', 'Nested']);
      final sorted =
          f.member('applySortedView')(f.member('currentItems'))
              as List<RDFileNode>;
      expect(sorted.map((n) => n.name), ['Nested', 'Alpha.mkv', 'Zebra.mkv']);
      expect(
        (f.member('currentItems') as List<RDFileNode>).map((n) => n.name),
        raw,
      );
      f.member('performSearch')('s02e03');
      await t.pump();
      final results = f.member('searchResults') as List;
      expect(
        results.length,
        0,
        reason: 'Original stack starts with a null root node',
      );
      final stack = f.member('navigationStack') as List;
      stack[0] = (
        torrent: f.torrent(1),
        webDownload: null,
        path: <String>[],
        node: f.member('currentFolderNode') as RDFileNode,
      );
      f.member('performSearch')('s02e03');
      final searchable = f.member('searchResults') as List;
      expect(searchable.length, 1);
      expect(searchable.single.node.name, 'Show.S02E03.mkv');
      expect(searchable.single.path, contains('Nested'));
    }),
  );
  testWidgets(
    'series virtual folders and season episode parsing remain dormant',
    (t) => torboxCase(t, (f) async {
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
            fileId: 1,
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
  for (final web in [false, true]) {
    testWidgets(
      'scroll paging web=$web advances by page size',
      (t) => torboxCase(t, (f) async {
        final rows = [for (var i = 0; i < 50; i++) torboxRow(i + 1, files: 1)];
        if (web) {
          f.web = rows;
        } else {
          f.torrents = rows;
        }
        await f.mount(t);
        if (web) {
          await t.tap(find.text('Web Downloads'));
          await t.pumpAndSettle();
        }
        final controller =
            f.member(web ? 'webDownloadScrollController' : 'scrollController')
                as ScrollController;
        controller.jumpTo(controller.position.maxScrollExtent);
        await t.pumpAndSettle();
        final requests = f.requests
            .where(
              (r) =>
                  r.url.path ==
                  (web ? '/v1/api/webdl/mylist' : '/v1/api/torrents/mylist'),
            )
            .toList();
        expect(requests.map((r) => r.url.queryParameters['offset']), [
          '0',
          '50',
        ]);
        expect(f.member(web ? 'webDownloadOffset' : 'offset'), 100);
        expect(f.member(web ? 'hasMoreWebDownloads' : 'hasMore'), isFalse);
      }),
    );
  }
  for (final error in [false, true]) {
    testWidgets(
      'list empty or error error=$error',
      (t) => torboxCase(t, (f) async {
        f.torrents = [];
        f.web = [];
        f.failLists = error;
        await f.mount(t);
        expect(
          find.textContaining(error ? 'fixture failure' : 'No cached torrents'),
          findsWidgets,
        );
        await t.tap(find.text('Web Downloads'));
        await t.pumpAndSettle();
        expect(
          find.textContaining(
            error ? 'fixture failure' : 'No Web Downloads Yet',
          ),
          findsWidgets,
        );
      }),
    );
  }
  for (final view in ['torrents', 'folder', 'web_downloads', 'selection']) {
    testWidgets(
      'original $view reachable pixel golden',
      (t) => torboxCase(t, (f) async {
        await f.mount(t);
        if (view == 'folder') f.member('navigateIntoTorrent')(f.torrent(1));
        if (view == 'web_downloads') await t.tap(find.text('Web Downloads'));
        if (view == 'selection') f.member('toggleSelectionMode')();
        await t.pump(const Duration(milliseconds: 600));
        await t.pump();
        expect(t.takeException(), isNull);
        if (Platform.isLinux &&
            !File(
              'test/goldens/torbox_downloads/linux/$view.png',
            ).existsSync()) {
          markTestSkipped(
            'Pending original-code Ubuntu capture; no push authorized',
          );
          return;
        }
        await expectLater(
          find.byKey(const ValueKey('torbox-canvas')),
          matchesGoldenFile(
            '../../../../goldens/torbox_downloads/${Platform.isLinux ? 'linux' : 'macos'}/$view.png',
          ),
        );
      }),
    );
  }
}
