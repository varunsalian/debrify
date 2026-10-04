import 'package:debrify/screens/pikpak/pikpak_files_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/pikpak_files_fixture.dart';

void main() {
  testWidgets(
    'passing JSON-map HTTP fixture loads real PikPak screen',
    (t) => pikpakCase(t, (f) async {
      await f.mount(t);
      expect(f.ids, ['z9', 'a2', 'm5']);
      expect(f.requests.length, 1);
      final r = f.requests.single;
      expect(r.method, 'GET');
      expect(r.url.path, '/drive/v1/files');
      expect(r.url.queryParameters, {
        'parent_id': '',
        'thumbnail_size': 'SIZE_SMALL',
        'limit': '50',
        'with_audit': 'true',
        'filters': '{"trashed":{"eq":false}}',
      });
      expect(r.headers['authorization'], 'Bearer fixture-access');
    }),
  );
  for (final pushed in [false, true]) {
    testWidgets(
      'route versus tab registration and sentinel disposal pushed=$pushed',
      (t) => pikpakCase(t, (f) async {
        var tabCalls = 0, routeCalls = 0, focusCalls = 0;
        bool tabSentinel() {
          tabCalls++;
          return true;
        }

        bool routeSentinel() {
          routeCalls++;
          return true;
        }

        void focusSentinel() {
          focusCalls++;
        }

        MainPageBridge.registerTabBackHandler('pikpak', tabSentinel);
        MainPageBridge.registerTvContentFocusHandler(6, focusSentinel);
        if (pushed) MainPageBridge.pushRouteBackHandler(routeSentinel);
        try {
          await f.mount(t, pushed: pushed);
          f.member('toggleSelectionMode')();
          await t.pump();
          expect(MainPageBridge.handleBackNavigation(), isTrue);
          expect(f.member('isSelectionMode'), isFalse);
          expect(tabCalls, 0);
          expect(routeCalls, 0);
          expect(MainPageBridge.requestTvContentFocus(), isTrue);
          await t.pump();
          expect(focusCalls, pushed ? 1 : 0);
          if (!pushed) {
            MainPageBridge.registerTabBackHandler('pikpak', tabSentinel);
          }
          await f.close(t);
          expect(MainPageBridge.handleBackNavigation(), pushed);
          expect(routeCalls, pushed ? 1 : 0);
          expect(tabCalls, 0);
          if (pushed) {
            MainPageBridge.popRouteBackHandler(routeSentinel);
            expect(MainPageBridge.handleBackNavigation(), isTrue);
            expect(tabCalls, 1);
            expect(MainPageBridge.requestTvContentFocus(), isTrue);
            expect(focusCalls, 2);
          } else {
            expect(MainPageBridge.requestTvContentFocus(), isFalse);
          }
        } finally {
          MainPageBridge.popRouteBackHandler(routeSentinel);
          MainPageBridge.unregisterTabBackHandler('pikpak');
          MainPageBridge.unregisterTvContentFocusHandler(6, focusSentinel);
        }
      }),
    );
  }
  testWidgets(
    'back priority selection then search then real folder then root',
    (t) => pikpakCase(t, (f) async {
      await f.mount(t);
      f.member('navigateIntoFolder')('z9', 'Folder z9');
      await f.until(t, () => f.member('isLoading') == false);
      await t.pump();
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
      expect(f.member('navigationStack'), isEmpty);
      expect(MainPageBridge.handleBackNavigation(), isFalse);
    }),
  );
  testWidgets(
    'restricted deep link with empty stack back goes to restricted root',
    (t) => pikpakCase(
      t,
      (f) async {
        await f.mount(t, pushed: true, initialId: 'z9', initialName: 'Target');
        expect(f.member('navigationStack'), isEmpty);
        expect(f.member('currentFolderId'), 'z9');
        expect(f.member('restrictedFolderId'), 'restricted');
        expect(f.member('isAtRestrictedRoot'), isFalse);
        expect(MainPageBridge.handleBackNavigation(), isTrue);
        await f.until(t, () => f.member('isLoading') == false);
        await t.pump();
        expect(f.member('currentFolderId'), 'restricted');
        expect(f.member('currentFolderName'), 'Restricted');
        expect(f.member('isAtRestrictedRoot'), isTrue);
        expect(f.member('navigationStack'), isEmpty);
        expect(find.byType(PikPakFilesScreen), findsOneWidget);
        expect(f.observer.popped, isEmpty);
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
            ('GET', '/drive/v1/files/restricted', null, null),
            ('GET', '/drive/v1/files', 'z9', null),
            ('GET', '/drive/v1/files', 'restricted', null),
          ],
        );
      },
      preferences: {
        'pikpak_restricted_folder_id': 'restricted',
        'pikpak_restricted_folder_name': 'Restricted',
      },
    ),
  );
  testWidgets(
    'pushed root with no current folder back returns false',
    (t) => pikpakCase(t, (f) async {
      await f.mount(t, pushed: true);
      expect(f.member('currentFolderId'), isNull);
      expect(f.member('navigationStack'), isEmpty);
      expect(MainPageBridge.handleBackNavigation(), isFalse);
      await t.pump(const Duration(milliseconds: 600));
      expect(f.member('currentFolderId'), isNull);
      expect(find.byType(PikPakFilesScreen), findsOneWidget);
      expect(f.observer.popped, isEmpty);
      expect(f.requests.map((r) => (r.method, r.url.path)), [
        ('GET', '/drive/v1/files'),
      ]);
    }),
  );
  testWidgets(
    'virtual folder back precedes real folder back and keeps cast alias',
    (t) => pikpakCase(t, (f) async {
      await f.mount(t);
      f.member('navigateIntoFolder')('z9', 'Folder z9');
      await f.until(t, () => f.member('isLoading') == false);
      final backing = <Map<String, dynamic>>[pikpakFile('n6')];
      f.member('navigateIntoVirtualFolder')({
        'name': 'Season 2',
        'virtual_files': backing,
      });
      await t.pump();
      expect(f.member('isInVirtualFolder'), isTrue);
      (f.member('virtualFolderFiles') as List).clear();
      expect(backing, isEmpty);
      expect(MainPageBridge.handleBackNavigation(), isTrue);
      expect(f.member('isInVirtualFolder'), isFalse);
      expect(f.member('currentFolderId'), 'z9');
      await f.until(t, () => f.member('isLoading') == false);
    }),
  );
  testWidgets(
    'pushed initialized root back pops route',
    (t) => pikpakCase(t, (f) async {
      await f.mount(t, pushed: true, initialId: 'z9', initialName: 'Target');
      expect(f.member('currentFolderId'), 'z9');
      expect(f.member('currentFolderName'), 'Target');
      expect(f.requests.single.url.queryParameters['parent_id'], 'z9');
      expect(MainPageBridge.handleBackNavigation(), isTrue);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Caller'), findsOneWidget);
      expect(f.observer.popped.length, 1);
    }),
  );
  testWidgets(
    'restricted tab root back switches torrent search and resets flag',
    (t) => pikpakCase(
      t,
      (f) async {
        await f.mount(t);
        expect(f.member('currentFolderId'), 'restricted');
        var switched = <int>[];
        MainPageBridge.switchTab = switched.add;
        MainPageBridge.returnToTorrentSearchOnBack = true;
        expect(MainPageBridge.handleBackNavigation(), isTrue);
        expect(switched, [MainTab.legacyTorrentSearch]);
        expect(MainPageBridge.returnToTorrentSearchOnBack, isFalse);
        expect(f.member('currentFolderId'), 'restricted');
        expect(MainPageBridge.handleBackNavigation(), isFalse);
      },
      preferences: {
        'pikpak_restricted_folder_id': 'restricted',
        'pikpak_restricted_folder_name': 'Restricted',
      },
    ),
  );
  for (final initial in [false, true]) {
    testWidgets(
      'uncancellable ten second timer exact deadline deepLink=$initial',
      (t) => pikpakCase(t, (f) async {
        // mount is intentionally outside runAsync, so Future.delayed uses fake time.
        await f.mount(
          t,
          pushed: true,
          initialId: initial ? 'z9' : null,
          wait: false,
        );
        await t.pump(const Duration(milliseconds: 9399));
        expect(find.byType(PikPakFilesScreen), findsOneWidget);
        expect(f.observer.popped, isEmpty);
        await t.pump(const Duration(milliseconds: 1));
        await t.pump();
        expect(f.observer.popped.length, initial ? 1 : 0);
        await t.pump(const Duration(milliseconds: 600));
        expect(
          find.byType(PikPakFilesScreen),
          initial ? findsNothing : findsOneWidget,
        );
      }, preferences: {'pikpak_enabled': false}),
    );
  }
  testWidgets(
    'tab initial folder id never schedules ten second pop',
    (t) => pikpakCase(t, (f) async {
      await f.mount(t, initialId: 'z9', wait: false);
      expect(f.member('currentFolderId'), isNull);
      await t.pump(const Duration(milliseconds: 9399));
      expect(find.byType(PikPakFilesScreen), findsOneWidget);
      expect(f.observer.popped, isEmpty);
      await t.pump(const Duration(milliseconds: 1));
      await t.pump();
      expect(find.byType(PikPakFilesScreen), findsOneWidget);
      expect(f.observer.popped, isEmpty);
      expect(f.member('currentFolderId'), isNull);
      expect(f.requests, isEmpty);
      expect(
        find.text('Failed to open folder. Please try again.'),
        findsNothing,
      );
    }, preferences: {'pikpak_enabled': false}),
  );
  testWidgets(
    'unmount before ten second deadline prevents delayed pop',
    (t) => pikpakCase(t, (f) async {
      await f.mount(t, pushed: true, initialId: 'z9', wait: false);
      expect(f.member('currentFolderId'), isNull);
      await t.pump(const Duration(milliseconds: 9399));
      expect(f.observer.popped, isEmpty);
      await t.pumpWidget(const SizedBox.shrink());
      expect(f.key.currentState, isNull);
      await t.pump(const Duration(milliseconds: 1));
      await t.pump();
      expect(f.observer.popped, isEmpty);
      expect(f.requests, isEmpty);
      expect(t.takeException(), isNull);
    }, preferences: {'pikpak_enabled': false}),
  );
  testWidgets(
    'assigned folder prevents timeout pop at deadline',
    (t) => pikpakCase(t, (f) async {
      await f.mount(t, pushed: true, initialId: 'z9', initialName: 'Target');
      await t.pump(const Duration(seconds: 10));
      expect(f.observer.popped, isEmpty);
      expect(f.member('currentFolderId'), 'z9');
    }),
  );
  testWidgets(
    'normal startup pending listing unmount rejects publication',
    (t) => pikpakCase(t, (f) async {
      final held = Completer<http.Response>();
      f.heldPages['|'] = held;
      await f.mount(t, wait: false);
      await f.until(t, () => f.requests.isNotEmpty);
      await t.pumpWidget(const SizedBox.shrink());
      held.complete(f.json(f.page(f.rows)));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump();
      expect(t.takeException(), isNull);
    }),
  );
  testWidgets(
    'TV first item focus and back arrow left sidebar handoff',
    (t) => pikpakCase(t, (f) async {
      await f.mount(t);
      MainPageBridge.requestTvContentFocus();
      t.binding.scheduleFrame();
      await t.pump();
      await t.pump();
      expect((f.member('firstItemFocusNode') as FocusNode).hasFocus, isTrue);
      f.member('navigateIntoFolder')('z9', 'Folder z9');
      await f.until(t, () => f.member('isLoading') == false);
      await t.pump();
      var calls = 0;
      MainPageBridge.focusTvSidebar = () {
        calls++;
      };
      (f.member('backButtonFocusNode') as FocusNode).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(calls, 1);
    }),
  );
  testWidgets(
    'focus request before pending load remains until items arrive',
    (t) => pikpakCase(t, (f) async {
      final held = Completer<http.Response>();
      f.heldPages['|'] = held;
      await f.mount(t, wait: false);
      await f.until(t, () => f.requests.isNotEmpty);
      MainPageBridge.requestTvContentFocus();
      t.binding.scheduleFrame();
      await t.pump();
      await t.pump();
      expect(f.member('shouldFocusOnLoad'), isTrue);
      held.complete(f.json(f.page(f.rows)));
      await f.until(t, () => f.member('isLoading') == false);
      t.binding.scheduleFrame();
      await t.pump();
      await t.pump();
      expect((f.member('firstItemFocusNode') as FocusNode).hasFocus, isTrue);
      expect(f.member('shouldFocusOnLoad'), isFalse);
    }),
  );
  testWidgets(
    'empty loaded list focuses add-link fallback',
    (t) => pikpakCase(t, (f) async {
      f.rows = [];
      await f.mount(t);
      MainPageBridge.requestTvContentFocus();
      t.binding.scheduleFrame();
      await t.pump();
      await t.pump();
      expect(
        (f.member('addLinkButtonFocusNode') as FocusNode).hasFocus,
        isTrue,
      );
      expect(f.member('shouldFocusOnLoad'), isFalse);
    }),
  );
}
