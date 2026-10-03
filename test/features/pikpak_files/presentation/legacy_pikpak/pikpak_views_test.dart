import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/pikpak_files_fixture.dart';

const captureLinux = bool.fromEnvironment('PIKPAK_CAPTURE_ORIGINAL_LINUX');
const captureMac = bool.fromEnvironment('PIKPAK_CAPTURE_ORIGINAL_MACOS');
const requireLinux = bool.fromEnvironment('PIKPAK_REQUIRE_ORIGINAL_LINUX');
void main() {
  testWidgets(
    'Raw aliases original list and choosing Raw clears it after sort',
    (t) => pikpakCase(t, (f) async {
      await f.mount(t);
      final identity = f.member('files');
      expect(
        identical(
          f.member('applyViewMode')(f.member('rawMode'), identity),
          identity,
        ),
        isTrue,
      );
      f.member('navigateIntoFolder')('z9', 'Folder z9');
      await f.until(t, () => f.member('isLoading') == false);
      expect(identical(f.member('files'), identity), isTrue);
      expect(f.ids, ['n6', 'b3']);
      await f.member('setViewMode')(f.member('sortedMode'));
      await t.pump();
      expect(f.ids, ['b3', 'n6']);
      expect(f.member('hasMore'), isFalse);
      expect(f.member('nextPageToken'), isNull);
      await f.member('setViewMode')(f.member('rawMode'));
      await t.pump();
      expect(f.ids, isEmpty);
      expect(identical(f.member('files'), identity), isTrue);
      expect(find.text('Folder is Empty'), findsOneWidget);
      await f.member('refreshFiles')();
      await f.until(t, () => f.member('isLoading') == false);
      expect(f.ids, ['n6', 'b3']);
      expect(identical(f.member('files'), identity), isTrue);
    }),
  );
  testWidgets(
    'numeric sorted folders precede numeric files',
    (t) => pikpakCase(t, (f) async {
      await f.mount(t);
      final rows = [
        pikpakFile('z9', name: '10. Ten.mkv'),
        pikpakFile('a2', name: '2. Two.mkv'),
        pikpakFile('m5', name: 'Season 10', folder: true),
        pikpakFile('n6', name: 'Season 2', folder: true),
        pikpakFile('b3', name: 'Alpha.mkv'),
      ];
      final sorted = f.member('applySortedView')(rows) as List;
      expect(sorted.map((dynamic r) => r['id']), [
        'n6',
        'm5',
        'a2',
        'z9',
        'b3',
      ]);
      expect(rows.map((r) => r['id']), ['z9', 'a2', 'm5', 'n6', 'b3']);
      expect(f.member('extractSeasonNumber')('Chapter_12'), 12);
      expect(f.member('extractSeasonNumber')('Season 10'), 10);
      expect(f.member('extractSeasonNumber')('Other'), isNull);
      expect(f.member('extractLeadingNumber')('05_Episode.mp4'), 5);
      expect(f.member('extractLeadingNumber')('Episode 05.mp4'), isNull);
    }),
  );
  testWidgets(
    'dormant series grouping keeps season episode order and real values',
    (t) => pikpakCase(t, (f) async {
      await f.mount(t);
      final rows = [
        pikpakFile('z9', name: 'Show.S02E10.mkv'),
        pikpakFile('a2', name: 'Show.S01E02.mkv'),
        pikpakFile('m5', name: 'Show.S02E01.mkv'),
      ];
      final arranged = f.member('applySeriesArrangeView')(rows) as List;
      expect(arranged.map((dynamic r) => r['season_number']), [1, 2]);
      expect(arranged.map((dynamic r) => r['kind']), [
        'virtual#season',
        'virtual#season',
      ]);
      expect(
        (arranged[1]['virtual_files'] as List).map((dynamic r) => r['id']),
        ['m5', 'z9'],
      );
      expect(arranged[1]['size'], 400 * 1024 * 1024);
    }),
  );
  for (final videosOnly in [false, true]) {
    for (final ignoreSmall in [false, true]) {
      testWidgets(
        'both filter settings videos=$videosOnly small=$ignoreSmall',
        (t) => pikpakCase(
          t,
          (f) async {
            f.rows = [
              pikpakFile('z9', folder: true),
              pikpakFile('a2', mib: 99),
              pikpakFile('m5', mib: 100),
              pikpakFile('n6', video: false),
              pikpakFile('b3', mib: null),
              pikpakFile('q7', complete: false),
            ];
            await f.mount(t);
            expect(f.ids, [
              'z9',
              if (!ignoreSmall) 'a2',
              'm5',
              if (!videosOnly) 'n6',
              'b3',
              'q7',
            ]);
            expect(
              (f.member('files') as List).singleWhere(
                (dynamic r) => r['id'] == 'm5',
              )['size'],
              '104857600',
            );
          },
          preferences: {
            'pikpak_show_videos_only': videosOnly,
            'pikpak_ignore_small_videos': ignoreSmall,
          },
        ),
      );
    }
  }
  testWidgets(
    'real scroll pages sequential tokens waits and end boundary',
    (t) => pikpakCase(t, (f) async {
      f.pages['|'] = f.page([
        for (var i = 0; i < 30; i++) pikpakFile('p0-$i'),
      ], next: 'token-n7');
      f.pages['|token-n7'] = f.page([
        for (var i = 0; i < 30; i++) pikpakFile('p1-$i'),
      ], next: 'token-q2');
      f.pages['|token-q2'] = f.page([pikpakFile('last')]);
      await f.mount(t);
      final c = f.member('scrollController') as ScrollController;
      final held = Completer<http.Response>();
      f.heldPages['|token-n7'] = held;
      c.jumpTo(c.position.maxScrollExtent);
      await f.until(t, () => f.requests.length == 2);
      expect(f.member('isLoadingMore'), isTrue);
      expect(f.ids.length, 30);
      f.member('loadMoreFiles')();
      await t.pump();
      expect(f.requests.length, 2);
      held.complete(f.json(f.pages['|token-n7']!));
      await f.until(t, () => f.member('isLoadingMore') == false);
      await t.pump();
      expect(f.ids.length, 60);
      expect(f.member('nextPageToken'), 'token-q2');
      c.jumpTo(c.position.maxScrollExtent);
      await f.until(
        t,
        () => f.member('isLoadingMore') == false && f.requests.length == 3,
      );
      await t.pump();
      expect(f.ids.length, 61);
      expect(f.ids.last, 'last');
      expect(f.member('hasMore'), isFalse);
      f.member('loadMoreFiles')();
      c.jumpTo(0);
      c.jumpTo(c.position.maxScrollExtent);
      await t.pump();
      expect(
        f.requests.map(
          (r) => (
            r.method,
            r.url.path,
            r.url.queryParameters['parent_id'],
            r.url.queryParameters['page_token'],
          ),
        ),
        [
          ('GET', '/drive/v1/files', '', null),
          ('GET', '/drive/v1/files', '', 'token-n7'),
          ('GET', '/drive/v1/files', '', 'token-q2'),
        ],
      );
    }),
  );
  testWidgets(
    'reset detaches paging then attaches exactly one original listener',
    (t) => pikpakCase(t, (f) async {
      f.pages['|'] = f.page([
        for (var i = 0; i < 30; i++) pikpakFile('p0-$i'),
      ], next: 'token-n7');
      f.pages['|token-n7'] = f.page([
        for (var i = 0; i < 30; i++) pikpakFile('p1-$i'),
      ], next: 'token-q2');
      f.pages['|token-q2'] = f.page([pikpakFile('last')]);
      await f.mount(t);
      final c = f.member('scrollController') as ScrollController;
      final callback = f.member('onScroll') as VoidCallback;
      c.position.correctPixels(c.position.maxScrollExtent);
      f.member('resetListScroll')();
      await t.pump();
      expect(c.offset, 0);
      expect(f.requests.length, 1);
      c.removeListener(callback);
      c.jumpTo(c.position.maxScrollExtent);
      await t.pump();
      expect(f.requests.length, 1);
      c.addListener(callback);
      c.jumpTo(0);
      c.jumpTo(c.position.maxScrollExtent);
      await f.until(
        t,
        () => f.requests.length == 2 && f.member('isLoadingMore') == false,
      );
      await t.pump();
      c.jumpTo(c.position.maxScrollExtent);
      await f.until(
        t,
        () => f.requests.length == 3 && f.member('isLoadingMore') == false,
      );
      expect(f.requests.map((r) => r.url.queryParameters['page_token']), [
        null,
        'token-n7',
        'token-q2',
      ]);
    }),
  );
  testWidgets(
    'navigation during pending load preserves stale listing behavior',
    (t) => pikpakCase(t, (f) async {
      final held = Completer<http.Response>();
      f.heldPages['|'] = held;
      await f.mount(t, wait: false);
      await f.until(t, () => f.requests.length == 1);
      f.member('navigateIntoFolder')('z9', 'Folder z9');
      await t.pump();
      expect(f.requests.length, 1);
      expect(f.member('currentFolderId'), 'z9');
      held.complete(f.json(f.page([pikpakFile('outgoing')])));
      await f.until(t, () => f.member('isLoading') == false);
      expect(f.ids, ['outgoing']);
      expect(f.member('currentFolderId'), 'z9');
    }),
  );
  testWidgets(
    'view dropdown root folder virtual visibility and autofocus',
    (t) => pikpakCase(t, (f) async {
      await f.mount(t);
      expect(
        find.byWidgetPredicate((w) => w is DropdownButtonFormField),
        findsNothing,
      );
      f.member('navigateIntoFolder')('z9', 'Folder z9');
      await f.until(t, () => f.member('isLoading') == false);
      await t.pump();
      expect(
        find.byWidgetPredicate((w) => w is DropdownButtonFormField),
        findsOneWidget,
      );
      expect(
        (t.widget(find.byWidgetPredicate((w) => w is DropdownButton))
                as DropdownButton)
            .autofocus,
        isTrue,
      );
      f.member('navigateIntoVirtualFolder')({
        'name': 'Season 1',
        'virtual_files': [pikpakFile('n6')],
      });
      await t.pump();
      expect(
        find.byWidgetPredicate((w) => w is DropdownButtonFormField),
        findsNothing,
      );
    }),
  );
  testWidgets(
    'search synchronously replaces results over loaded files and empty query',
    (t) => pikpakCase(t, (f) async {
      f.rows = [
        pikpakFile('z9', name: 'Folder z9', folder: true),
        {...pikpakFile('a2', name: 'Alpha.mkv'), 'parent_name': 'Season 2'},
        pikpakFile('m5', name: 'Beta.mkv'),
      ];
      await f.mount(t);
      f.pages['z9|'] = f.page(f.rows);
      f.member('navigateIntoFolder')('z9', 'Folder z9');
      await f.until(t, () => f.member('isLoading') == false);
      final count = f.requests.length;
      f.member('toggleSearch')();
      await t.pump();
      await t.enterText(find.byType(TextField), 'ALPHA');
      await t.pump();
      final results = f.member('searchResults') as List;
      expect(results.length, 1);
      expect(results.single.file['id'], 'a2');
      expect(results.single.path, 'Season 2');
      expect(f.requests.length, count);
      await t.enterText(find.byType(TextField), '');
      await t.pump();
      expect(f.member('searchResults'), isEmpty);
      expect(identical(f.member('searchResults'), results), isFalse);
    }),
  );
  for (final error in [false, true]) {
    testWidgets(
      'empty and error actual state error=$error',
      (t) => pikpakCase(t, (f) async {
        f.rows = [];
        f.failLists = error;
        await f.mount(t);
        expect(f.member('isLoading'), isFalse);
        expect(f.member('initialLoad'), isFalse);
        expect(f.ids, isEmpty);
        expect(
          f.member('errorMessage'),
          error ? contains('fixture list failure') : '',
        );
        expect(
          find.text(error ? 'Failed to Load Files' : 'No Files Yet'),
          findsOneWidget,
        );
      }),
    );
  }
  testWidgets(
    'not enabled settings button retains snackbar-only behavior',
    (t) => pikpakCase(t, (f) async {
      await f.mount(t);
      await f.until(t, () => find.text('Go to Settings').evaluate().isNotEmpty);
      expect(f.requests, isEmpty);
      await t.tap(find.text('Go to Settings'));
      await t.pump();
      expect(f.observer.popped, isEmpty);
      expect(find.text('Open Settings > PikPak to configure'), findsOneWidget);
    }, preferences: {'pikpak_enabled': false}),
  );
  for (final view in [
    'root',
    'folder',
    'selection',
    'select_source',
    'not_enabled',
  ]) {
    final host = Platform.isLinux ? 'linux' : 'macos';
    final path = 'test/goldens/pikpak_files/$host/$view.png';
    testWidgets(
      'reachable pixel golden $view',
      (t) => pikpakCase(t, (f) async {
        await f.mount(t, picker: view == 'select_source');
        if (view == 'not_enabled') {
          await f.until(
            t,
            () => find.text('Go to Settings').evaluate().isNotEmpty,
          );
        }
        if (view == 'folder') {
          f.member('navigateIntoFolder')('z9', 'Folder z9');
          await f.until(t, () => f.member('isLoading') == false);
        }
        if (view == 'selection') f.member('toggleSelectionMode')();
        await t.pump(const Duration(milliseconds: 600));
        await t.pump();
        expect(t.takeException(), isNull);
        if (Platform.isLinux &&
            !captureLinux &&
            !requireLinux &&
            !File(path).existsSync()) {
          debugPrint('PENDING original Linux golden $path');
          return;
        }
        if (!captureLinux && !captureMac) {
          expect(
            File(path).existsSync(),
            isTrue,
            reason: 'Original $host golden missing',
          );
        }
        await expectLater(
          find.byKey(const ValueKey('pikpak-canvas')),
          matchesGoldenFile('../../../../goldens/pikpak_files/$host/$view.png'),
        );
      }, preferences: {'pikpak_enabled': view != 'not_enabled'}),
    );
  }
}
