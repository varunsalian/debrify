import 'dart:async';
import 'dart:convert';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/screens/torbox/torbox_downloads_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../support/torbox_downloads_fixture.dart';

void main() {
  for (final pushed in [false, true]) {
    testWidgets(
      'back registration and unregistration pushed=$pushed',
      (t) => torboxCase(t, (f) async {
        var sentinelCalls = 0;
        bool sentinel() {
          sentinelCalls++;
          return true;
        }

        MainPageBridge.registerTabBackHandler('torbox', sentinel);
        await f.mount(t, pushed: pushed);
        MainPageBridge.setActiveTvTab(5);
        expect(f.member('tvContentFocusHandler'), pushed ? isNull : isNotNull);
        expect(MainPageBridge.requestTvContentFocus(), !pushed);
        f.member('toggleSelectionMode')();
        expect(MainPageBridge.handleBackNavigation(), isTrue);
        expect(f.member('isSelectionMode'), isFalse);
        expect(sentinelCalls, 0);
        // A pushed route must leave the existing tab registration untouched.
        if (pushed) {
          MainPageBridge.popRouteBackHandler(f.member('handleBackNavigation'));
          expect(MainPageBridge.handleBackNavigation(), isTrue);
          expect(sentinelCalls, 1);
          MainPageBridge.pushRouteBackHandler(f.member('handleBackNavigation'));
        }
        await f.close(t);
        expect(MainPageBridge.requestTvContentFocus(), isFalse);
        MainPageBridge.registerTabBackHandler('torbox', sentinel);
        expect(MainPageBridge.handleBackNavigation(), isTrue);
        expect(sentinelCalls, pushed ? 2 : 1);
        MainPageBridge.unregisterTabBackHandler('torbox', sentinel);
      }),
    );
  }
  testWidgets(
    'selection then torrent search then folder search then folder up',
    (t) => torboxCase(t, (f) async {
      await f.mount(t);
      f.member('navigateIntoTorrent')(f.torrent(1));
      final folder = (f.member('currentItems') as List)
          .whereType<RDFileNode>()
          .firstWhere((n) => n.isFolder);
      f.member('navigateIntoFolder')(folder);
      f.member('toggleSearch')();
      f.member('toggleTorrentSearch')();
      f.member('toggleSelectionMode')();
      expect(f.member('handleBackNavigation')(), isTrue);
      expect(f.member('isSelectionMode'), isFalse);
      expect(f.member('isTorrentSearchActive'), isTrue);
      expect(f.member('isSearchActive'), isTrue);
      expect(f.member('handleBackNavigation')(), isTrue);
      expect(f.member('isTorrentSearchActive'), isFalse);
      expect(f.member('isSearchActive'), isTrue);
      expect(f.member('handleBackNavigation')(), isTrue);
      expect(f.member('isSearchActive'), isFalse);
      expect((f.member('navigationStack') as List).length, 2);
      expect(f.member('handleBackNavigation')(), isTrue);
      expect((f.member('navigationStack') as List).length, 1);
      expect(f.member('handleBackNavigation')(), isTrue);
      expect(f.member('isAtRoot'), isTrue);
    }),
  );
  testWidgets(
    'picker back pops before selection',
    (t) => torboxCase(t, (f) async {
      await f.mount(t, pushed: true, picker: true);
      f.member('toggleSelectionMode')();
      expect(f.member('handleBackNavigation')(), isTrue);
      await t.pumpAndSettle();
      expect(find.text('Caller'), findsOneWidget);
      expect(f.key.currentState, isNull);
    }),
  );
  for (final deep in [false, true]) {
    testWidgets(
      'torrent root back deep=$deep',
      (t) => torboxCase(t, (f) async {
        await f.mount(t, pushed: true, initial: deep ? f.torrent(1) : null);
        if (!deep) f.member('navigateIntoTorrent')(f.torrent(1));
        await t.pump();
        expect(f.member('isAtRoot'), isFalse);
        expect(f.member('handleBackNavigation')(), isTrue);
        await t.pumpAndSettle();
        if (deep) {
          expect(find.text('Caller'), findsOneWidget);
          expect(f.key.currentState, isNull);
        } else {
          expect(f.member('isAtRoot'), isTrue);
          expect(f.key.currentState, isNotNull);
        }
      }),
    );
  }
  testWidgets(
    'return to search clears the bridge handoff',
    (t) => torboxCase(t, (f) async {
      await f.mount(t);
      f.member('navigateIntoTorrent')(f.torrent(1));
      final tabs = <int>[];
      MainPageBridge.switchTab = tabs.add;
      MainPageBridge.returnToTorrentSearchOnBack = true;
      expect(f.member('handleBackNavigation')(), isTrue);
      expect(tabs, [MainTab.legacyTorrentSearch]);
      expect(MainPageBridge.returnToTorrentSearchOnBack, isFalse);
    }),
  );
  testWidgets(
    'normal startup pending fetch can unmount',
    (t) => torboxCase(t, (f) async {
      f.holdLists = true;
      f.pending = Completer<http.Response>();
      await f.mount(t);
      await f.until(t, () => f.requests.length == 2);
      await t.pumpWidget(const SizedBox.shrink());
      f.pending!.complete(http.Response('{"success":true,"data":[]}', 200));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }),
  );
  testWidgets(
    'remount replaces credentials lists controllers and focus owners',
    (t) => torboxCase(t, (f) async {
      await f.mount(t);
      final oldState = f.key.currentState;
      final old = f.access;
      await t.pumpWidget(const SizedBox.shrink());
      SharedPreferences.setMockInitialValues({
        'torbox_api_key': 'incoming-key',
      });
      f.torrents = [torboxRow(99)];
      await f.mount(t);
      expect(identical(f.key.currentState, oldState), isFalse);
      expect(f.member('apiKey'), 'incoming-key');
      expect((f.member('torrents') as List).map((e) => e.id), [99]);
      for (final name in [
        'torrents',
        'firstItemFocusNode',
        'scrollController',
        'torrentSearchController',
      ]) {
        expect(identical(old[name], f.member(name)), isFalse);
      }
      expect(f.requests.last.headers['Authorization'], 'Bearer incoming-key');
    }),
  );
  testWidgets(
    'two independent routes own distinct state and resources',
    (t) => torboxCase(t, (f) async {
      await f.mount(t, pushed: true);
      final second = GlobalKey<State<TorboxDownloadsScreen>>();
      f.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              TorboxDownloadsScreen(key: second, isPushedRoute: true),
        ),
      );
      await t.pumpAndSettle();
      final other = torboxDownloadsTestAccess(second.currentState!);
      expect(identical(other['torrents'], f.member('torrents')), isFalse);
      expect(
        identical(other['firstItemFocusNode'], f.member('firstItemFocusNode')),
        isFalse,
      );
      f.member('toggleSelectionMode')();
      expect(
        torboxDownloadsTestAccess(second.currentState!)['isSelectionMode'],
        isFalse,
      );
      expect(f.member('isSelectionMode'), isTrue);
      f.navigatorKey.currentState!.pop();
      await t.pumpAndSettle();
    }),
  );
  testWidgets(
    'first row up and search up down handlers preserve focus',
    (t) => torboxCase(t, (f) async {
      await f.mount(t);
      f.member('toggleTorrentSearch')();
      (f.member('torrentSearchController') as TextEditingController).text =
          'Library';
      f.member('submitTorrentSearch')();
      await t.pumpAndSettle();
      final first = f.member('firstItemFocusNode') as FocusNode;
      final search = f.member('torrentSearchFocusNode') as FocusNode;
      final toggle = f.member('torrentSearchToggleFocusNode') as FocusNode;
      first.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump();
      expect(search.hasFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump();
      expect(toggle.hasFocus, isTrue);
      search.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      expect(first.hasFocus, isTrue);
    }),
  );
  testWidgets(
    'sidebar request focuses first loaded row',
    (t) => torboxCase(t, (f) async {
      await f.mount(t);
      MainPageBridge.setActiveTvTab(5);
      MainPageBridge.requestTvContentFocus();
      await t.pump();
      await t.pump();
      expect((f.member('firstItemFocusNode') as FocusNode).hasFocus, isTrue);
    }),
  );
  for (final pending in [false, true]) {
    testWidgets(
      'focus fallback empty or before load pending=$pending',
      (t) => torboxCase(t, (f) async {
        f.torrents = [];
        f.web = [];
        f.holdLists = pending;
        if (pending) f.pending = Completer<http.Response>();
        await f.mount(t);
        if (!pending) {
          await f.until(t, () => f.member('isLoadingWebDownloads') == false);
          f.member('navigateIntoTorrent')(f.torrent(99, files: 0));
          await t.pumpAndSettle();
        }
        MainPageBridge.setActiveTvTab(5);
        expect(MainPageBridge.requestTvContentFocus(), isTrue);
        t.binding.scheduleFrame();
        await t.pump();
        await t.pump();
        expect(f.member('shouldFocusOnLoad'), pending);
        if (pending) {
          expect(
            (f.member('firstItemFocusNode') as FocusNode).hasFocus,
            isFalse,
          );
          f.pending!.complete(
            http.Response(
              jsonEncode({
                'success': true,
                'data': [torboxRow(1)],
              }),
              200,
            ),
          );
          await f.until(
            t,
            () =>
                f.member('initialLoad') == false &&
                f.member('isLoadingWebDownloads') == false,
          );
          await t.pump();
          await t.pump();
        }
        expect(f.member('shouldFocusOnLoad'), isFalse);
        expect(
          (f.member(pending ? 'firstItemFocusNode' : 'searchButtonFocusNode')
                  as FocusNode)
              .hasFocus,
          isTrue,
        );
      }),
    );
  }
  testWidgets(
    'didUpdateWidget reopens each new initial torrent',
    (t) => torboxCase(t, (f) async {
      await f.mount(t, initial: f.torrent(1));
      expect((f.member('currentTorrent') as dynamic).id, 1);
      final state = f.key.currentState;
      await f.mount(t, initial: f.torrent(2));
      expect(identical(f.key.currentState, state), isTrue);
      expect((f.member('currentTorrent') as dynamic).id, 2);
      expect(f.member('initialActionHandled'), isTrue);
      await f.mount(t, initial: f.torrent(3));
      expect((f.member('currentTorrent') as dynamic).id, 3);
    }),
  );
}
