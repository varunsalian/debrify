import 'dart:async';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/premiumize_files_fixture.dart';

void main() {
  testWidgets(
    'passing HTTP fixture loads original Premiumize screen',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      expect(f.ids, ['z9', 'a2', 'm5']);
      expect(f.log, [f.getRequest('folder/list')]);
      expect(find.text('Video a2.mkv'), findsOneWidget);
    }),
  );
  for (final pushed in [false, true]) {
    testWidgets(
      'route tab and TV sentinel teardown pushed=$pushed',
      (t) => premiumizeCase(t, (f) async {
        var tabs = 0, routes = 0, focus = 0;
        bool tab() {
          tabs++;
          return true;
        }

        bool route() {
          routes++;
          return true;
        }

        void tv() {
          focus++;
        }

        MainPageBridge.registerTabBackHandler('premiumize', tab);
        MainPageBridge.registerTvContentFocusHandler(11, tv);
        if (pushed) MainPageBridge.pushRouteBackHandler(route);
        try {
          await f.mount(t, pushed: pushed);
          await f.transitions(t);
          f.member('toggleSelectionMode')();
          await t.pump();
          expect(MainPageBridge.handleBackNavigation(), isTrue);
          expect(f.member('isSelectionMode'), isFalse);
          expect(tabs, 0);
          expect(routes, 0);
          expect(MainPageBridge.requestTvContentFocus(), isTrue);
          await t.pump();
          expect(focus, pushed ? 1 : 0);
          if (!pushed) MainPageBridge.registerTabBackHandler('premiumize', tab);
          await f.close(t);
          expect(MainPageBridge.handleBackNavigation(), pushed);
          expect(routes, pushed ? 1 : 0);
          expect(tabs, 0);
          if (pushed) {
            MainPageBridge.popRouteBackHandler(route);
            expect(MainPageBridge.handleBackNavigation(), isTrue);
            expect(tabs, 1);
          }
          expect(MainPageBridge.requestTvContentFocus(), pushed);
        } finally {
          MainPageBridge.popRouteBackHandler(route);
          MainPageBridge.unregisterTabBackHandler('premiumize');
          MainPageBridge.unregisterTvContentFocusHandler(11, tv);
        }
      }),
    );
  }
  testWidgets(
    'back priority selection search folder tab and false',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      f.member('navigateIntoFolder')(premiumizeItem('z9', folder: true));
      await f.until(t, () => f.member('isLoading') == false);
      f.member('toggleSearch')();
      f.member('toggleSelectionMode')();
      await t.pump();
      expect(MainPageBridge.handleBackNavigation(), isTrue);
      expect(f.member('isSelectionMode'), isFalse);
      expect(f.member('isSearchActive'), isTrue);
      expect(f.member('currentFolderId'), 'z9');
      expect(MainPageBridge.handleBackNavigation(), isTrue);
      expect(f.member('isSearchActive'), isFalse);
      expect(f.member('currentFolderId'), 'z9');
      expect(MainPageBridge.handleBackNavigation(), isTrue);
      await f.until(t, () => f.member('isLoading') == false);
      expect(f.member('currentFolderId'), isNull);
      int? switched;
      MainPageBridge.switchTab = (v) => switched = v;
      MainPageBridge.returnToTorrentSearchOnBack = true;
      expect(MainPageBridge.handleBackNavigation(), isTrue);
      expect(switched, MainTab.legacyTorrentSearch);
      expect(MainPageBridge.returnToTorrentSearchOnBack, isFalse);
      expect(MainPageBridge.handleBackNavigation(), isFalse);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/list', {'id': 'z9'}),
        f.getRequest('folder/list'),
      ]);
    }),
  );
  testWidgets(
    'pushed root Back pops caller and browse back maybePop',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t, pushed: true);
      await f.transitions(t);
      expect(f.member('isBrowsePush'), isTrue);
      await t.tap(find.byIcon(Icons.arrow_back).first);
      await f.transitions(t);
      expect(f.observer.popped.whereType<PageRoute>().length, 1);
      expect(find.text('Caller'), findsOneWidget);
    }),
  );
  testWidgets(
    'Opening folder scaffold own Back pops before root load',
    (t) => premiumizeCase(t, (f) async {
      final h = Completer<http.Response>();
      f.held['folder/list|'] = h;
      await f.mount(t, pushed: true, wait: false);
      await f.until(t, () => f.requests.length == 1);
      await f.transitions(t);
      expect(find.text('Opening folder...'), findsOneWidget);
      expect(f.member('initialLoad'), isTrue);
      expect(f.member('currentFolderId'), isNull);
      await t.tap(find.byIcon(Icons.arrow_back));
      await f.transitions(t);
      h.complete(f.json(f.page([premiumizeFile('a2')])));
      await t.pump();
      expect(f.observer.popped.whereType<PageRoute>().length, 1);
      expect(find.text('Caller'), findsOneWidget);
      expect(f.log, [f.getRequest('folder/list')]);
    }),
  );
  for (final action in ['switchView', 'navigateIntoFolder', 'navigateUp']) {
    testWidgets(
      'scroll resets before navigation fields $action',
      (t) => premiumizeCase(t, (f) async {
        f.rows = [for (var i = 0; i < 35; i++) premiumizeFile('r$i')];
        f.pages['z9'] = f.rows;
        await f.mount(t);
        if (action == 'navigateUp') {
          f.member('navigateIntoFolder')(premiumizeItem('z9', folder: true));
          await f.until(t, () => f.member('isLoading') == false);
          await t.pump();
        }
        final c = f.member('scrollController') as ScrollController;
        expect(c.position.maxScrollExtent, greaterThan(0));
        c.jumpTo(180);
        expect(c.offset, greaterThan(0));
        final before = (
          f.member('selectedView'),
          f.member('currentFolderId'),
          (f.member('navigationStack') as List).length,
        );
        final observed = <(double, Object?, Object?, int)>[];
        void listener() {
          observed.add((
            c.offset,
            f.member('selectedView'),
            f.member('currentFolderId'),
            (f.member('navigationStack') as List).length,
          ));
        }

        c.addListener(listener);
        if (action == 'switchView') {
          f.member(action)(f.member('transfersView'));
        } else if (action == 'navigateIntoFolder') {
          f.member(action)(premiumizeItem('z9', folder: true));
        } else {
          f.member(action)();
        }
        c.removeListener(listener);
        expect(observed, [
          (0, before.$1, before.$2, before.$3),
        ], reason: 'offset reset precedes navigation setState');
        await f.until(
          t,
          () =>
              f.member('isLoading') == false &&
              f.member('isLoadingTransfers') == false,
        );
        expect(
          f.member('currentFolderId'),
          action == 'navigateIntoFolder' ? 'z9' : null,
        );
      }),
    );
  }
  for (final config in ['disabled', 'missing', 'empty', 'enabled']) {
    testWidgets(
      'settings integration and key $config',
      (t) => premiumizeCase(
        t,
        (f) async {
          await f.mount(t);
          expect(f.member('premiumizeEnabled'), config == 'enabled');
          expect(f.member('initialLoad'), isFalse);
          expect(
            f.log,
            config == 'enabled' ? [f.getRequest('folder/list')] : isEmpty,
          );
          if (config != 'enabled') {
            expect(find.text('Premiumize Not Configured'), findsOneWidget);
          }
        },
        omitApiKey: config == 'missing',
        preferences: config == 'enabled' || config == 'missing'
            ? {}
            : config == 'disabled'
            ? {'premiumize_integration_enabled': false}
            : {'premiumize_api_key': ''},
      ),
    );
  }
  for (final pair in [(null, 'Name'), ('z9', null), ('z9', 'Name')]) {
    testWidgets(
      'initial folder requires both id and name ${pair.$1}/${pair.$2}',
      (t) => premiumizeCase(t, (f) async {
        await f.mount(t, initialId: pair.$1, initialName: pair.$2);
        expect(
          f.member('currentFolderId'),
          pair.$1 != null && pair.$2 != null ? 'z9' : null,
        );
        expect(
          f.member('currentFolderName'),
          pair.$1 != null && pair.$2 != null ? 'Name' : 'My Files',
        );
        expect(f.log, [
          f.getRequest(
            'folder/list',
            pair.$1 != null && pair.$2 != null ? {'id': 'z9'} : {},
          ),
        ]);
      }),
    );
  }
  testWidgets(
    'initial root trimmed query schedules debounce after listing',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t, initialQuery: '  Alpha  ');
      expect(f.member('isSearchActive'), isTrue);
      expect(
        (f.member('searchController') as TextEditingController).text,
        'Alpha',
      );
      expect(f.log, [f.getRequest('folder/list')]);
      await t.pump(const Duration(milliseconds: 349));
      expect(f.requests.length, 1);
      await t.pump(const Duration(milliseconds: 1));
      await f.until(t, () => f.requests.length == 2);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/search', {'q': 'Alpha'}),
      ]);
    }),
  );
  testWidgets(
    'initial folder query remains empty after matching listing',
    (t) => premiumizeCase(t, (f) async {
      final h = Completer<http.Response>();
      f.held['folder/list|z9'] = h;
      await f.mount(
        t,
        initialId: 'z9',
        initialName: 'Name',
        initialQuery: 'Alpha',
        wait: false,
      );
      await f.until(t, () => f.requests.length == 1);
      expect(f.resultIds, isEmpty);
      h.complete(f.json(f.page([premiumizeFile('a2', name: 'Alpha.mkv')])));
      await f.until(t, () => f.member('isLoading') == false);
      expect(f.ids, ['a2']);
      expect(f.resultIds, isEmpty);
      expect(f.log, [
        f.getRequest('folder/list', {'id': 'z9'}),
      ]);
    }),
  );
  for (final transfers in [false, true]) {
    testWidgets(
      'load guard identity refresh and unmount transfers=$transfers',
      (t) => premiumizeCase(t, (f) async {
        await f.mount(t);
        final identity = f.member(transfers ? 'transfers' : 'items');
        final h = Completer<http.Response>();
        f.held['${transfers ? 'transfer/list' : 'folder/list'}|'] = h;
        if (transfers) {
          f.member('switchView')(f.member('transfersView'));
        } else {
          f.member('loadFolder')();
        }
        await f.until(t, () => f.requests.length == 2);
        f.member(transfers ? 'loadTransfers' : 'loadFolder')();
        await t.pump();
        expect(f.requests.length, 2);
        h.complete(
          f.json(
            transfers
                ? {'status': 'success', 'transfers': f.transfers}
                : f.page([premiumizeFile('fresh')]),
          ),
        );
        await f.until(
          t,
          () =>
              f.member(transfers ? 'isLoadingTransfers' : 'isLoading') == false,
        );
        expect(
          identical(f.member(transfers ? 'transfers' : 'items'), identity),
          isTrue,
          reason: 'listing keeps original collection identity',
        );
        f.held.clear();
        f.member('toggleSelectionMode')();
        await f.member('refresh')();
        await t.pump();
        expect(f.member('isSelectionMode'), isFalse);
        expect(f.log, [
          f.getRequest('folder/list'),
          f.getRequest(transfers ? 'transfer/list' : 'folder/list'),
          f.getRequest(transfers ? 'transfer/list' : 'folder/list'),
        ]);
        f.member('switchView')(
          f.member(transfers ? 'transfersView' : 'filesView'),
        );
        await t.pump();
        expect(f.requests.length, 3);
      }),
    );
  }
  testWidgets(
    'pending load and debounce unmount cancel requests',
    (t) => premiumizeCase(t, (f) async {
      final h = Completer<http.Response>();
      f.held['folder/list|'] = h;
      await f.mount(t, wait: false);
      await f.until(t, () => f.requests.length == 1);
      f.member('toggleSearch')();
      (f.member('searchController') as TextEditingController).text = 'Alpha';
      f.member('performSearch')('Alpha');
      await f.close(t);
      await t.pump(const Duration(milliseconds: 350));
      h.complete(f.json(f.page(f.rows)));
      await t.pump();
      expect(f.log, [f.getRequest('folder/list')]);
      expect(t.takeException(), isNull);
    }),
  );
}
