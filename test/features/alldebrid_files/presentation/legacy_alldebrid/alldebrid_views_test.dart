import 'dart:async';
import 'dart:io';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:debrify/widgets/cloud/cloud_row_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/alldebrid_files_fixture.dart';

const captureLinux = bool.fromEnvironment('ALLDEBRID_CAPTURE_ORIGINAL_LINUX');
const captureMac = bool.fromEnvironment('ALLDEBRID_CAPTURE_ORIGINAL_MACOS');
const reverseGoldens = bool.fromEnvironment('ALLDEBRID_GOLDEN_REVERSE');
void main() {
  testWidgets(
    'missing key keeps exact error Retry and marks lazy links loaded on failure',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      expect(
        find.text('Add your AllDebrid API key in Settings first.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(f.member('apiKey'), isNull);
      await f.tap(t, find.text('Retry'));
      expect(f.log, isEmpty);
      await f.web(t);
      expect(f.member('linksLoadedOnce'), isTrue);
      expect(
        f.member('linksError'),
        'Add your AllDebrid API key in Settings first.',
      );
      await f.torrents(t);
      await f.web(t);
      expect(f.log, isEmpty);
    }, credential: null),
  );
  for (final web in [false, true]) {
    testWidgets(
      'load failure Retry uses original entry and exact request list web=$web',
      (t) => allDebridCase(t, (f) async {
        final path = web ? '/v4/user/links' : '/v4.1/magnet/status';
        f.failures.add(path);
        await f.mount(t);
        if (web) {
          await f.web(t);
        }
        expect(
          find.textContaining(
            web
                ? 'Failed to load your saved links:'
                : 'Failed to load your AllDebrid library:',
          ),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
        if (web) {
          expect(f.member('linksLoadedOnce'), isTrue);
        }
        f.failures.clear();
        await f.tap(t, find.text('Retry'));
        await f.until(
          t,
          () => f.member(web ? 'loadingLinks' : 'loading') == false,
        );
        expect(find.text(web ? 'Saved w8.mkv' : 'Library z9'), findsOneWidget);
        expect(
          f.log,
          web ? [adList(), adLinks(), adLinks()] : [adList(), adList()],
        );
      }),
    );
  }
  testWidgets(
    'links load lazily once and view switching clears selection search and shared scroll',
    (t) => allDebridCase(t, (f) async {
      f.magnets = [
        for (var i = 0; i < 30; i++) adMagnet(i == 0 ? 'z9' : 'row-$i'),
      ];
      f.links = [for (var i = 0; i < 30; i++) adLink('link-$i')];
      await f.mount(t);
      expect(f.member('linksLoadedOnce'), isFalse);
      expect(f.log, [adList()]);
      await f.tap(t, find.byTooltip('Select items'));
      await f.tap(t, find.text('Library z9'));
      await f.search(t, ' Library ');
      f.scroll.jumpTo(180);
      await t.pump();
      expect(f.scroll.offset, 180);
      await f.web(t);
      expect(f.scroll.offset, 0);
      expect(f.member('selectionMode'), isFalse);
      expect(f.member('selectedIds'), isEmpty);
      expect(f.member('searchActive'), isFalse);
      expect(f.member('searchQuery'), '');
      expect(f.member('linksLoadedOnce'), isTrue);
      expect(find.text('Saved link-0.mkv'), findsOneWidget);
      f.scroll.jumpTo(190);
      await t.pump();
      await f.torrents(t);
      expect(f.scroll.offset, 0);
      expect(f.member('selectionMode'), isFalse);
      expect(f.member('selectedIds'), isEmpty);
      expect(f.member('searchActive'), isFalse);
      await f.web(t);
      expect(f.member('selectionMode'), isFalse);
      expect(f.log, [adList(), adLinks()]);
    }),
  );
  for (final web in [false, true]) {
    testWidgets(
      'reachable root toolbar refresh selects its own loader web=$web',
      (t) => allDebridCase(t, (f) async {
        await f.mount(t);
        if (web) {
          await f.web(t);
          f.links = [adLink('fresh')];
        } else {
          f.magnets = [adMagnet('fresh')];
        }
        await f.tap(t, find.byTooltip('Refresh'));
        await f.until(
          t,
          () => f.member(web ? 'loadingLinks' : 'loading') == false,
        );
        expect(
          find.text(web ? 'Saved fresh.mkv' : 'Library fresh'),
          findsOneWidget,
        );
        expect(
          f.log,
          web ? [adList(), adLinks(), adLinks()] : [adList(), adList()],
        );
      }),
    );
  }
  testWidgets(
    'magnet links and file rows retain exact keys and first focus binding',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      for (final id in ['z9', 'a2', 'm5']) {
        expect(find.byKey(ValueKey(id)), findsOneWidget);
      }
      expect(
        t.widget<CloudFileRow>(f.row('Library z9')).focusNode,
        same(f.focus('firstItemFocusNode')),
      );
      expect(t.widget<CloudFileRow>(f.row('Library a2')).focusNode, isNull);
      await f.web(t);
      expect(
        find.byKey(const ValueKey('https://locked.test/w8')),
        findsOneWidget,
      );
      expect(
        t.widget<CloudFileRow>(f.row('Saved w8.mkv')).focusNode,
        same(f.focus('firstItemFocusNode')),
      );
      await f.torrents(t);
      await f.open(t);
      expect((f.member('currentFiles') as List).map((dynamic f) => f.path), [
        'Root/A.S02E01.mkv',
        'Root/C.S01E01.mkv',
        'Root/B.S01E02.mkv',
        'Root/Notes.txt',
      ]);
      expect(
        find.byKey(const ValueKey('z9:Root/A.S02E01.mkv:0')),
        findsOneWidget,
      );
      expect(
        t.widget<CloudFileRow>(f.row('A.S02E01.mkv')).focusNode,
        same(f.focus('firstItemFocusNode')),
      );
      expect(find.byType(RefreshIndicator), findsNothing);
      expect(find.byTooltip('Refresh'), findsNothing);
      expect(f.log, [adList(), adLinks(), adFiles('z9')]);
    }),
  );
  testWidgets(
    'dormant forced-files refresh retains files during held load and cached credential',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      await f.open(t);
      await f.search(t, 'S01', file: true);
      final original = (f.member('currentFiles') as List)
          .map((dynamic f) => f.path)
          .toList();
      final retained = f.member('refresh') as Future<void> Function();
      var saved = false;
      AllDebridStorage.saveAllDebridApiKey('changed-key').then((_) {
        saved = true;
      });
      await f.until(t, () => saved);
      final held = Completer<http.Response>();
      f.held['/v4/magnet/files'] = held;
      final done = retained();
      await f.until(t, () => f.requests.length == 3);
      expect(f.member('loadingFiles'), isTrue);
      expect(find.byType(CloudRowSkeletonList), findsOneWidget);
      expect(
        (f.member('currentFiles') as List).map((dynamic f) => f.path),
        original,
      );
      expect(f.member('fileSearchActive'), isFalse);
      expect(f.member('fileSearchQuery'), '');
      expect(f.log, [adList(), adFiles('z9'), adFiles('z9')]);
      f.files = [adFile('new')];
      held.complete(f.filesResponse());
      await f.until(t, () => f.member('loadingFiles') == false);
      await done;
      await t.pump();
      expect(find.text('new.mkv'), findsOneWidget);
    }),
  );
  testWidgets(
    'three searches trim and ignore case with link host and file filename boundaries',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      await f.search(t, ' LIBRARY ');
      expect(f.member('visibleMagnets') as List, hasLength(3));
      await t.enterText(find.byType(TextField), '  A2  ');
      await t.pump();
      expect(find.text('Library a2'), findsOneWidget);
      expect(find.text('Library z9'), findsNothing);
      await f.web(t);
      f.links[2]['host'] =
          'OtHeR.HoSt'; // Reload through the real toolbar first.
      await f.tap(t, find.byTooltip('Refresh'));
      await f.until(t, () => f.member('loadingLinks') == false);
      await f.search(t, ' OTHER.HOST ');
      expect(find.text('Saved n6.mkv'), findsOneWidget);
      expect(find.text('Saved w8.mkv'), findsNothing);
      await t.enterText(find.byType(TextField), ' W8 ');
      await t.pump();
      expect(find.text('Saved w8.mkv'), findsOneWidget);
      await f.torrents(t);
      await f.open(t);
      await f.search(t, ' S01E02 ', file: true);
      expect(find.text('B.S01E02.mkv'), findsOneWidget);
      expect(find.text('C.S01E01.mkv'), findsNothing);
      await t.enterText(find.byType(TextField), 'Root');
      await t.pump();
      expect(find.text('No files match your search.'), findsOneWidget);
      expect(f.log, [adList(), adLinks(), adLinks(), adFiles('z9')]);
    }),
  );
  testWidgets(
    'empty root links and files keep original messages',
    (t) => allDebridCase(t, (f) async {
      f.magnets = [];
      f.links = [];
      await f.mount(t);
      expect(find.text('Your AllDebrid library is empty.'), findsOneWidget);
      await f.web(t);
      expect(find.text('No saved links yet.'), findsOneWidget);
      await f.torrents(t);
      f.magnets = [adMagnet('z9')];
      await f.tap(t, find.byTooltip('Refresh'));
      await f.until(t, () => f.member('loading') == false);
      f.files = [];
      await f.open(t);
      expect(find.text('No files in this magnet.'), findsOneWidget);
      expect(f.log, [adList(), adLinks(), adList(), adFiles('z9')]);
    }),
  );
  testWidgets(
    'open magnet failure clears loading and shows exact failure snack without reload',
    (t) => allDebridCase(t, (f) async {
      f.failures.add('/v4/magnet/files');
      await f.mount(t);
      await f.open(t);
      expect(f.member('loadingFiles'), isFalse);
      expect(f.member('currentMagnet'), isNotNull);
      expect(
        find.text('Failed to load files: Exception: fixture failure'),
        findsOneWidget,
      );
      expect(f.log, [adList(), adFiles('z9')]);
    }),
  );
  const views = [
    'magnet_root',
    'web_downloads',
    'magnet_files',
    'selection',
    'select_source',
    'error',
  ];
  for (final view in reverseGoldens ? views.reversed : views) {
    final host = Platform.isLinux ? 'linux' : 'macos';
    final path = 'test/goldens/alldebrid_files/$host/$view.png';
    testWidgets(
      'reachable pixel golden $view',
      (t) => allDebridCase(t, (f) async {
        if (view == 'error') {
          f.failures.add('/v4.1/magnet/status');
        }
        await f.mount(t, picker: view == 'select_source');
        if (view == 'web_downloads') {
          await f.web(t);
        }
        if (view == 'magnet_files') {
          await f.open(t);
        }
        if (view == 'selection') {
          await f.tap(t, find.byTooltip('Select items'));
          await f.tap(t, find.text('Library a2'));
        }
        await t.pump(const Duration(milliseconds: 600));
        await t.pump();
        expect(t.takeException(), isNull);
        expect(f.log, [
          adList(),
          if (view == 'web_downloads') adLinks(),
          if (view == 'magnet_files') adFiles('z9'),
        ]);
        if (!captureLinux && !captureMac) {
          expect(
            File(path).existsSync(),
            isTrue,
            reason: 'Original $host golden missing',
          );
        }
        await expectLater(
          find.byKey(const ValueKey('alldebrid-canvas')),
          matchesGoldenFile(
            '../../../../goldens/alldebrid_files/$host/$view.png',
          ),
        );
      }),
    );
  }
}
