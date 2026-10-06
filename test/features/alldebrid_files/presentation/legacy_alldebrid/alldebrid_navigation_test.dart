import 'dart:async';
import 'package:debrify/screens/alldebrid/alldebrid_files_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/widgets/cloud/cloud_row_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/alldebrid_files_fixture.dart';

void main() {
  for (final pushed in [false, true]) {
    testWidgets(
      'back registration and sentinel teardown pushed=$pushed',
      (t) => allDebridCase(t, (f) async {
        var tabCalls = 0, routeCalls = 0;
        bool tabSentinel() {
          tabCalls++;
          return true;
        }

        bool routeSentinel() {
          routeCalls++;
          return true;
        }

        MainPageBridge.registerTabBackHandler('alldebrid', tabSentinel);
        MainPageBridge.pushRouteBackHandler(routeSentinel);
        try {
          await f.mount(t, pushed: pushed);
          expect(MainPageBridge.focusAllDebridWebDownloads, isNotNull);
          // A foreign pushed sentinel has priority over a tab; a pushed screen
          // falls through its root-false handler to the original tab sentinel.
          expect(MainPageBridge.handleBackNavigation(), isTrue);
          expect((tabCalls, routeCalls), pushed ? (1, 0) : (0, 1));
          MainPageBridge.popRouteBackHandler(
            routeSentinel,
          ); // tab case only: top.
          if (!pushed) {
            expect(MainPageBridge.handleBackNavigation(), isFalse);
          }
          await f.close(t);
          expect(MainPageBridge.focusAllDebridWebDownloads, isNull);
          expect(
            MainPageBridge.handleBackNavigation(),
            pushed ? isTrue : isFalse,
          );
          expect((tabCalls, routeCalls), pushed ? (1, 1) : (0, 1));
          expect(f.log, [adList()]);
        } finally {
          MainPageBridge.popRouteBackHandler(routeSentinel);
          MainPageBridge.unregisterTabBackHandler('alldebrid');
        }
      }),
    );
  }
  testWidgets(
    'TV tab 12 stored closure focuses first row and identity removal preserves replacement',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      expect(f.focus('firstItemFocusNode').debugLabel, 'ad-first-item');
      expect(MainPageBridge.requestTvContentFocus(), isTrue);
      await t.pump();
      await t.pump();
      expect(f.focus('firstItemFocusNode').hasFocus, isTrue);
      var calls = 0;
      void replacement() {
        calls++;
      }

      MainPageBridge.registerTvContentFocusHandler(12, replacement);
      await f.close(t);
      expect(MainPageBridge.requestTvContentFocus(), isTrue);
      expect(calls, 1);
      MainPageBridge.unregisterTvContentFocusHandler(12, replacement);
      expect(MainPageBridge.requestTvContentFocus(), isFalse);
    }),
  );
  testWidgets(
    'back priority selection then file search then root search then magnet then false',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t, query: ' Library ');
      await f.tap(t, find.byTooltip('Select items'));
      await f.open(t); // selection tap selects; it does not open.
      expect(f.member('selectedIds'), {'z9'});
      expect(MainPageBridge.handleBackNavigation(), isTrue);
      expect(f.member('selectionMode'), isFalse);
      expect(f.member('selectedIds'), isEmpty);
      await t.pump();
      expect(f.member('searchActive'), isTrue);
      await f.open(t);
      await f.search(t, 's01', file: true);
      expect(MainPageBridge.handleBackNavigation(), isTrue);
      await t.pump();
      expect(f.member('fileSearchActive'), isFalse);
      expect(f.member('currentMagnet'), isNotNull);
      expect(f.member('searchActive'), isTrue);
      expect(MainPageBridge.handleBackNavigation(), isTrue);
      await t.pump();
      expect(f.member('searchActive'), isFalse);
      expect(f.member('currentMagnet'), isNotNull);
      expect(MainPageBridge.handleBackNavigation(), isTrue);
      await t.pump();
      await t.pump();
      expect(f.member('isAtRoot'), isTrue);
      expect(f.member('currentFiles'), isEmpty);
      expect(f.focus('firstItemFocusNode').hasFocus, isTrue);
      expect(MainPageBridge.handleBackNavigation(), isFalse);
      expect(f.log, [adList(), adFiles('z9')]);
    }),
  );
  testWidgets(
    'navigate up requests focus resets files search and root scroll',
    (t) => allDebridCase(t, (f) async {
      f.magnets = [
        for (var i = 0; i < 30; i++) adMagnet(i == 0 ? 'z9' : 'row-$i'),
      ];
      await f.mount(t);
      f.scroll.jumpTo(200);
      await t.pump();
      expect(f.scroll.offset, 200);
      // Open an already visible row with a real gesture, preserving the
      // outgoing root's nonzero offset. The files list borrows no controller.
      await t.tap(find.text('Library row-5'));
      await t.pump();
      await f.until(t, () => f.member('loadingFiles') == false);
      expect(f.scroll.hasClients, isFalse);
      await f.search(t, 's01', file: true);
      await f.tap(t, find.byTooltip('Back'));
      await t.pump();
      expect(f.scroll.offset, 0);
      expect(f.member('currentMagnet'), isNull);
      expect(f.member('currentFiles'), isEmpty);
      expect(f.member('loadingFiles'), isFalse);
      expect(f.member('fileSearchActive'), isFalse);
      expect(f.member('fileSearchQuery'), '');
      expect(f.focus('firstItemFocusNode').hasFocus, isTrue);
      expect(f.log, [adList(), adFiles('row-5')]);
    }),
  );
  testWidgets(
    'initial query is trimmed and a same-key widget update does not reapply it',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t, query: '  a2  ');
      expect(f.member('searchQuery'), 'a2');
      expect(f.member('searchActive'), isTrue);
      expect(find.text('Library a2'), findsOneWidget);
      expect(find.text('Library z9'), findsNothing);
      final state = f.key.currentState;
      await f.update(t, query: 'm5');
      expect(identical(f.key.currentState, state), isTrue);
      expect(f.member('searchQuery'), 'a2');
      expect(find.text('Library a2'), findsOneWidget);
      expect(f.log, [adList()]);
    }),
  );
  for (final pushed in [false, true]) {
    testWidgets(
      'pending deep link consumes once and starts both loads concurrently pushed=$pushed',
      (t) => allDebridCase(t, (f) async {
        MainPageBridge.notifyAllDebridFocusWebDownloads();
        final held = Completer<http.Response>();
        f.held['/v4.1/magnet/status'] = held;
        await f.mount(t, pushed: pushed);
        await f.until(
          t,
          () => f.requests.length == 2 && f.member('loadingLinks') == false,
        );
        expect(f.member('loading'), isTrue);
        expect(f.member('selectedView'), 'webDownloads');
        expect(MainPageBridge.getAndClearAllDebridFocusWebDownloads(), isFalse);
        expect(
          f.log,
          anyOf(equals([adList(), adLinks()]), equals([adLinks(), adList()])),
        );
        // Original startup launches both storage reads without serialization.
        held.complete(f.listResponse());
        await f.until(t, () => f.member('loading') == false);
        await f.torrents(t);
        await f.web(t);
        expect(f.requests.length, 2);
      }),
    );
  }
  testWidgets(
    'own disposal clears live handler then a notification becomes pending for next mount',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      final handler = MainPageBridge.focusAllDebridWebDownloads;
      expect(handler, isNotNull);
      await f.close(t);
      expect(MainPageBridge.focusAllDebridWebDownloads, isNull);
      MainPageBridge.notifyAllDebridFocusWebDownloads();
      await f.mount(t);
      await f.until(t, () => f.member('loadingLinks') == false);
      expect(f.member('selectedView'), 'webDownloads');
      expect(MainPageBridge.getAndClearAllDebridFocusWebDownloads(), isFalse);
      expect(f.log, [adList(), adList(), adLinks()]);
    }),
  );
  testWidgets(
    'second mounted deep-link registration survives first disposal and last disposal clears it',
    (t) => allDebridCase(t, (f) async {
      final second = GlobalKey<State<AllDebridFilesScreen>>();
      var firstPresent = true, secondPresent = true;
      Widget tree() => MaterialApp(
        theme: ThemeData.dark(),
        home: Row(
          children: [
            if (firstPresent) Expanded(child: AllDebridFilesScreen(key: f.key)),
            if (secondPresent)
              Expanded(child: AllDebridFilesScreen(key: second)),
          ],
        ),
      );
      await t.pumpWidget(tree());
      await f.until(
        t,
        () => f.requests.length == 2 && f.member('loading') == false,
      );
      final secondAccess = allDebridFilesTestAccess(second.currentState!);
      expect(secondAccess['scrollController'], isNot(same(f.scroll)));
      expect(
        secondAccess['firstItemFocusNode'],
        isNot(same(f.focus('firstItemFocusNode'))),
      );
      final latest = MainPageBridge.focusAllDebridWebDownloads;
      firstPresent = false;
      await t.pumpWidget(tree());
      await t.pump();
      expect(MainPageBridge.focusAllDebridWebDownloads, same(latest));
      await latest!();
      await t.pump();
      expect(
        allDebridFilesTestAccess(second.currentState!)['selectedView'],
        'webDownloads',
      );
      secondPresent = false;
      await t.pumpWidget(tree());
      await t.pump();
      expect(MainPageBridge.focusAllDebridWebDownloads, isNull);
      expect(f.log, [adList(), adList(), adLinks()]);
    }),
  );
  testWidgets(
    'repeated live notifications reset root and magnet state preserve file search and always reload',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t, query: 'Library');
      await f.tap(t, find.byTooltip('Select items'));
      await f.tap(t, find.text('Library m5'));
      MainPageBridge.notifyAllDebridFocusWebDownloads();
      await f.until(
        t,
        () => f.requests.length == 2 && f.member('loadingLinks') == false,
      );
      expect(f.member('selectionMode'), isFalse);
      expect(f.member('selectedIds'), isEmpty);
      expect(f.member('searchActive'), isFalse);
      expect(f.member('searchQuery'), '');
      await f.torrents(t);
      await f.open(t);
      await f.search(t, 's01', file: true);
      MainPageBridge.notifyAllDebridFocusWebDownloads();
      await f.until(
        t,
        () => f.requests.length == 4 && f.member('loadingLinks') == false,
      );
      expect(f.member('currentMagnet'), isNull);
      expect(f.member('currentFiles'), isEmpty);
      expect(f.member('fileSearchActive'), isTrue);
      expect(f.member('fileSearchQuery'), 's01');
      MainPageBridge.notifyAllDebridFocusWebDownloads();
      await f.until(
        t,
        () => f.requests.length == 5 && f.member('loadingLinks') == false,
      );
      expect(f.log, [adList(), adLinks(), adFiles('z9'), adLinks(), adLinks()]);
    }),
  );
  testWidgets(
    'held live links reload detaches scrolled list skeleton then restarts at zero',
    (t) => allDebridCase(t, (f) async {
      f.links = [for (var i = 0; i < 30; i++) adLink('link-$i')];
      await f.mount(t);
      await f.web(t);
      f.scroll.jumpTo(220);
      await t.pump();
      expect(f.scroll.offset, 220);
      final held = Completer<http.Response>();
      f.held['/v4/user/links'] = held;
      MainPageBridge.notifyAllDebridFocusWebDownloads();
      await f.until(t, () => f.requests.length == 3);
      expect(f.member('loadingLinks'), isTrue);
      expect(find.byType(CloudRowSkeletonList), findsOneWidget);
      expect(f.scroll.hasClients, isFalse);
      held.complete(f.linksResponse());
      await f.until(t, () => f.member('loadingLinks') == false);
      await t.pump();
      expect(f.scroll.offset, 0);
      expect(f.log, [adList(), adLinks(), adLinks()]);
    }),
  );
  testWidgets(
    'unmount during pending original load rejects publication without throwing',
    (t) => allDebridCase(t, (f) async {
      final held = Completer<http.Response>();
      f.held['/v4.1/magnet/status'] = held;
      await f.mount(t);
      await f.until(t, () => f.requests.length == 1);
      // Observe uncaught application errors as data, then assert none. This
      // makes a stale publication fail the named assertion rather than merely
      // aborting the test runner. Every captured error remains a failure.
      final reports = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reports.add;
      try {
        await f.close(t);
        held.complete(f.listResponse());
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump();
      } finally {
        FlutterError.onError = previous;
      }
      expect(
        reports,
        isEmpty,
        reason: 'Disposed load must not report an error',
      );
      expect(t.takeException(), isNull);
      expect(f.log, [adList()]);
    }),
  );
}
