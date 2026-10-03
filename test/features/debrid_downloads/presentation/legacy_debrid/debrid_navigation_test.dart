import 'dart:async';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/screens/debrid_downloads_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/debrid_downloads_fixture.dart';

void main() {
  for (final pushed in [false, true]) {
    testWidgets(
      'route versus tab sentinel registration disposal pushed=$pushed',
      (t) => debridCase(t, (f) async {
        var calls = 0;
        bool sentinel() {
          calls++;
          return true;
        }

        MainPageBridge.registerTabBackHandler('realdebrid', sentinel);
        await f.mount(t, pushed: pushed);
        MainPageBridge.setActiveTvTab(4);
        expect(f.member('tvContentFocusHandler'), pushed ? isNull : isNotNull);
        expect(MainPageBridge.requestTvContentFocus(), !pushed);
        f.member('toggleSelectionMode')();
        expect(MainPageBridge.handleBackNavigation(), isTrue);
        expect(f.member('isSelectionMode'), isFalse);
        expect(calls, 0);
        // Make a leaked route callback observably invalid after disposal.
        f.member('toggleSelectionMode')();
        await f.close(t);
        expect(MainPageBridge.requestTvContentFocus(), isFalse);
        expect(MainPageBridge.handleBackNavigation(), pushed);
        expect(calls, pushed ? 1 : 0);
        MainPageBridge.unregisterTabBackHandler('realdebrid', sentinel);
      }),
    );
  }
  testWidgets(
    'back priority selection folder search subfolder browse root and false keeps torrent search',
    (t) => debridCase(t, (f) async {
      await f.mount(t);
      await f.member('navigateIntoTorrent')(f.torrent('z9'));
      await t.pumpAndSettle();
      final folder = (f.member('currentViewNodes') as List<RDFileNode>)
          .firstWhere((n) => n.isFolder);
      f.member('navigateIntoFolder')(folder);
      f.member('toggleSearch')();
      f.member('toggleTorrentSearch')();
      f.member('toggleSelectionMode')();
      expect(f.member('handleBackNavigation')(), isTrue);
      expect(f.member('isSelectionMode'), isFalse);
      expect(f.member('isSearchActive'), isTrue);
      expect(f.member('isTorrentSearchActive'), isTrue);
      expect(f.member('handleBackNavigation')(), isTrue);
      expect(f.member('isSearchActive'), isFalse);
      expect(f.member('isTorrentSearchActive'), isTrue);
      expect(f.member('folderPath'), ['Nested']);
      expect(f.member('handleBackNavigation')(), isTrue);
      expect(f.member('folderPath'), isEmpty);
      expect(f.member('currentTorrentId'), 'z9');
      expect(f.member('handleBackNavigation')(), isTrue);
      expect(f.member('currentTorrentId'), isNull);
      expect(f.member('isTorrentSearchActive'), isTrue);
      expect(f.member('handleBackNavigation')(), isFalse);
      expect(f.member('isTorrentSearchActive'), isTrue);
    }),
  );
  testWidgets(
    'picker back pops before exiting selection',
    (t) => debridCase(t, (f) async {
      await f.mount(t, pushed: true, picker: true);
      f.member('toggleSelectionMode')();
      expect(f.member('handleBackNavigation')(), isTrue);
      await t.pumpAndSettle();
      expect(f.key.currentState, isNull);
      expect(find.text('Caller'), findsOneWidget);
    }),
  );
  for (final deep in [false, true]) {
    testWidgets(
      'pushed root back deep=$deep and two-info normal open',
      (t) => debridCase(t, (f) async {
        await f.mount(t, pushed: true, initial: deep ? f.torrent('z9') : null);
        if (deep) {
          await f.until(t, () => f.member('currentTorrentId') == 'z9');
        } else {
          await f.member('navigateIntoTorrent')(f.torrent('z9'));
        }
        await t.pumpAndSettle();
        expect(
          f.requests
              .where((r) => r.url.path.endsWith('/torrents/info/z9'))
              .length,
          2,
        );
        expect(f.member('handleBackNavigation')(), isTrue);
        await t.pumpAndSettle();
        if (deep) {
          expect(f.key.currentState, isNull);
          expect(find.text('Caller'), findsOneWidget);
        } else {
          expect(f.key.currentState, isNotNull);
          expect(f.member('currentTorrentId'), isNull);
        }
      }),
    );
  }
  testWidgets(
    'return to legacy search clears actual bridge flag',
    (t) => debridCase(t, (f) async {
      await f.mount(t);
      await f.member('navigateIntoTorrent')(f.torrent('z9'));
      final tabs = <int>[];
      MainPageBridge.switchTab = tabs.add;
      MainPageBridge.returnToTorrentSearchOnBack = true;
      expect(f.member('handleBackNavigation')(), isTrue);
      expect(tabs, [MainTab.legacyTorrentSearch]);
      expect(MainPageBridge.returnToTorrentSearchOnBack, isFalse);
      expect(f.member('currentTorrentId'), 'z9');
    }),
  );
  testWidgets(
    'deep-link root pop wins over return-to-search flag',
    (t) => debridCase(t, (f) async {
      await f.mount(t, pushed: true, initial: f.torrent('z9'));
      await f.until(t, () => f.member('currentTorrentId') == 'z9');
      await t.pumpAndSettle();
      final tabs = <int>[];
      MainPageBridge.switchTab = tabs.add;
      MainPageBridge.returnToTorrentSearchOnBack = true;
      expect(f.member('handleBackNavigation')(), isTrue);
      await t.pumpAndSettle();
      expect(f.key.currentState, isNull);
      expect(find.text('Caller'), findsOneWidget);
      expect(tabs, isEmpty);
      expect(MainPageBridge.returnToTorrentSearchOnBack, isTrue);
    }),
  );
  for (final copy in [false, true]) {
    testWidgets(
      'RAR copy=$copy request order clipboard no folder open',
      (t) => debridCase(t, (f) async {
        f.rar = true;
        await f.mount(t);
        expect(DownloadService.instance.allRecordDetailsSnapshot(), isEmpty);
        final before = f.requests.length;
        final action =
            f.member('navigateIntoTorrent')(f.torrent('z9')) as Future<void>;
        await f.until(
          t,
          () => find.text('RAR Archive Detected').evaluate().isNotEmpty,
        );
        await t.pumpAndSettle();
        await t.tap(
          find.widgetWithText(
            TextButton,
            copy ? 'Copy Download Link' : 'Cancel',
          ),
        );
        await t.pumpAndSettle();
        await action;
        if (copy) await f.until(t, () => f.clipboard.isNotEmpty);
        expect(
          f.requests.skip(before).map((r) => '${r.method} ${r.url.path}'),
          copy
              ? [
                  'GET /rest/1.0/torrents/info/z9',
                  'POST /rest/1.0/unrestrict/link',
                ]
              : ['GET /rest/1.0/torrents/info/z9'],
        );
        expect(
          f.clipboard,
          copy ? ['https://example.test/unrestricted.mkv'] : [],
        );
        expect(f.member('currentTorrentId'), isNull);
        expect(f.member('isLoadingFolder'), isFalse);
        expect(f.deletes, isEmpty);
        expect(DownloadService.instance.allRecordDetailsSnapshot(), isEmpty);
      }),
    );
  }
  testWidgets(
    'normal startup pending fetch completes safely after unmount',
    (t) => debridCase(t, (f) async {
      f.holdLists = true;
      f.pending = Completer<http.Response>();
      await f.mount(t);
      await f.until(t, () => f.requests.length == 1);
      await t.pumpWidget(const SizedBox.shrink());
      f.pending!.complete(http.Response('[]', 200));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }),
  );
  testWidgets(
    'two independently pushed routes own distinct resources',
    (t) => debridCase(t, (f) async {
      await f.mount(t, pushed: true);
      final second = GlobalKey<State<DebridDownloadsScreen>>();
      f.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              DebridDownloadsScreen(key: second, isPushedRoute: true),
        ),
      );
      await t.pumpAndSettle();
      final other = debridDownloadsTestAccess(second.currentState!);
      for (final name in [
        'torrents',
        'downloads',
        'firstItemFocusNode',
        'torrentScrollController',
        'torrentSearchController',
      ]) {
        expect(identical(other[name], f.member(name)), isFalse, reason: name);
      }
      f.member('toggleSelectionMode')();
      expect(
        debridDownloadsTestAccess(second.currentState!)['isSelectionMode'],
        isFalse,
      );
      expect(f.member('isSelectionMode'), isTrue);
      f.navigatorKey.currentState!.pop();
      await t.pumpAndSettle();
    }),
  );
  testWidgets(
    'torrent search down focuses first row and up escapes field',
    (t) => debridCase(t, (f) async {
      await f.mount(t);
      f.member('toggleTorrentSearch')();
      (f.member('torrentSearchController') as TextEditingController).text =
          'Library';
      f.member('submitTorrentSearch')();
      await t.pumpAndSettle();
      final first = f.member('firstItemFocusNode') as FocusNode;
      final search = f.member('torrentSearchFocusNode') as FocusNode;
      search.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      expect(first.hasFocus, isTrue);
      search.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump();
      expect(search.hasFocus, isFalse);
    }),
  );
  testWidgets(
    'TV focus request focuses first loaded row',
    (t) => debridCase(t, (f) async {
      await f.mount(t);
      MainPageBridge.setActiveTvTab(4);
      expect(MainPageBridge.requestTvContentFocus(), isTrue);
      await t.pump();
      await t.pump();
      expect((f.member('firstItemFocusNode') as FocusNode).hasFocus, isTrue);
      expect(f.member('shouldFocusOnLoad'), isFalse);
    }),
  );
  testWidgets(
    'empty folder focus falls back to search button',
    (t) => debridCase(t, (f) async {
      f.torrents = [];
      f.downloads = [];
      f.emptyFolder = true;
      await f.mount(t);
      await f.member('navigateIntoTorrent')(f.torrent('z9'));
      await t.pumpAndSettle();
      MainPageBridge.setActiveTvTab(4);
      MainPageBridge.requestTvContentFocus();
      t.binding.scheduleFrame();
      await t.pump();
      await t.pump();
      expect(f.member('shouldFocusOnLoad'), isFalse);
      expect((f.member('searchButtonFocusNode') as FocusNode).hasFocus, isTrue);
    }),
  );
}
