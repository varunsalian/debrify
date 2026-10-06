import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/widgets/cloud/cloud_row_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/premiumize_files_fixture.dart';

const captureLinux = bool.fromEnvironment('PREMIUMIZE_CAPTURE_ORIGINAL_LINUX');
const captureMac = bool.fromEnvironment('PREMIUMIZE_CAPTURE_ORIGINAL_MACOS');
const requireLinux = bool.fromEnvironment(
  'PREMIUMIZE_REQUIRE_ORIGINAL_LINUX',
  defaultValue: false,
);
void main() {
  testWidgets(
    'Raw copies collection Sort orders numbers and per folder memory',
    (t) => premiumizeCase(t, (f) async {
      final rows = [
        premiumizeFile('z9', name: '10. Ten.mkv'),
        premiumizeFile('a2', name: '2. Two.mkv'),
        premiumizeFile('m5', name: 'Season 10', folder: true),
        premiumizeFile('n6', name: 'Season 2', folder: true),
        premiumizeFile('q7', name: 'Zulu', folder: true),
        premiumizeFile('b3', name: 'Alpha.mkv'),
      ];
      f.pages['z9'] = rows;
      await f.mount(t);
      f.member('setViewMode')(f.member('sortedMode'));
      expect(f.member('folderViewModes'), isEmpty);
      final identity = f.member('items');
      expect(
        identical(
          f.member('applyViewMode')(f.member('rawMode'), identity),
          identity,
        ),
        isFalse,
        reason: 'Raw returns a copy',
      );
      f.member('navigateIntoFolder')(premiumizeItem('z9', folder: true));
      await f.until(t, () => f.member('isLoading') == false);
      f.member('setViewMode')(f.member('sortedMode'));
      await t.pump();
      expect(f.ids, ['n6', 'm5', 'q7', 'a2', 'z9', 'b3']);
      expect(identical(f.member('items'), identity), isTrue);
      f.member('setViewMode')(f.member('rawMode'));
      await t.pump();
      expect(
        f.ids,
        ['n6', 'm5', 'q7', 'a2', 'z9', 'b3'],
        reason:
            'Raw copies currently sorted rows without restoring server order',
      );
      f.member('setViewMode')(f.member('sortedMode'));
      f.member('navigateUp')();
      await f.until(t, () => f.member('isLoading') == false);
      f.member('navigateIntoFolder')(premiumizeItem('z9', folder: true));
      await f.until(t, () => f.member('isLoading') == false);
      expect(f.ids, ['n6', 'm5', 'q7', 'a2', 'z9', 'b3']);
      expect(f.member('getCurrentViewMode')(), f.member('sortedMode'));
      expect(f.member('extractSeasonNumber')('Chapter_12'), 12);
      expect(f.member('extractLeadingNumber')('05_Episode.mkv'), 5);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/list', {'id': 'z9'}),
        f.getRequest('folder/list'),
        f.getRequest('folder/list', {'id': 'z9'}),
      ]);
    }),
  );
  testWidgets(
    'navigating held folder shows skeleton before matching listing',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      final h = Completer<http.Response>();
      f.held['folder/list|z9'] = h;
      await t.tap(find.text('Folder z9'));
      await f.until(t, () => f.requests.length == 2);
      await t.pump();
      expect(f.ids, isEmpty);
      expect(find.byType(CloudRowSkeletonList), findsOneWidget);
      h.complete(f.json(f.page([premiumizeFile('fresh')])));
      await f.until(t, () => f.member('isLoading') == false);
      expect(f.ids, ['fresh']);
      expect(find.byType(CloudRowSkeletonList), findsNothing);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/list', {'id': 'z9'}),
      ]);
    }),
  );
  testWidgets(
    'stale folder listing wins while new navigation load is guarded',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      final future = f.member('loadFolder')();
      f.member('navigateIntoFolder')(premiumizeItem('z9', folder: true));
      await future;
      await t.pump();
      expect(f.member('currentFolderId'), 'z9');
      expect(f.ids, ['z9', 'a2', 'm5']);
      expect(f.log, [f.getRequest('folder/list'), f.getRequest('folder/list')]);
    }),
  );
  for (final transfers in [false, true]) {
    testWidgets(
      'empty and error retry states transfers=$transfers',
      (t) => premiumizeCase(t, (f) async {
        f.rows = [];
        f.transfers = [];
        await f.mount(t);
        expect(find.text('No Files Yet'), findsOneWidget);
        if (transfers) {
          f.member('switchView')(f.member('transfersView'));
          await f.until(t, () => f.member('isLoadingTransfers') == false);
          expect(find.text('No Transfers'), findsOneWidget);
        }
        f.failures.add('${transfers ? 'transfer/list' : 'folder/list'}|');
        await f.member('refresh')();
        await t.pump();
        expect(find.text('Failed to Load'), findsOneWidget);
        expect(
          f.member('errorMessage'),
          contains(
            transfers
                ? 'Premiumize transfer/list failed:'
                : 'Premiumize folder/list failed:',
          ),
        );
        expect(find.text(f.member('errorMessage') as String), findsOneWidget);
        await t.pump();
        expect(
          (f.member('retryButtonFocusNode') as FocusNode).hasFocus,
          isTrue,
        );
        f.failures.clear();
        await t.tap(find.text('Retry'));
        await f.until(
          t,
          () =>
              f.member('isLoading') == false &&
              f.member('isLoadingTransfers') == false,
        );
        expect(
          find.text(transfers ? 'No Transfers' : 'No Files Yet'),
          findsOneWidget,
        );
        expect(f.log, [
          f.getRequest('folder/list'),
          if (transfers) f.getRequest('transfer/list'),
          f.getRequest(transfers ? 'transfer/list' : 'folder/list'),
          f.getRequest(transfers ? 'transfer/list' : 'folder/list'),
        ]);
      }),
    );
  }
  testWidgets(
    'not configured Go to Settings autofocus remains snackbar',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      await t.pump();
      expect(
        (f.member('settingsButtonFocusNode') as FocusNode).hasFocus,
        isTrue,
      );
      await t.tap(find.text('Go to Settings'));
      await t.pump();
      expect(
        find.text('Open Settings > Premiumize to configure'),
        findsOneWidget,
      );
      expect(f.log, isEmpty);
    }, preferences: {'premiumize_integration_enabled': false}),
  );
  testWidgets(
    'folder dropdown arrows back sidebar first focus and empty fallback',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      expect(
        find.byWidgetPredicate((w) => w is DropdownButtonFormField),
        findsNothing,
      );
      f.member('navigateIntoFolder')(premiumizeItem('z9', folder: true));
      await f.until(t, () => f.member('isLoading') == false);
      await t.pump();
      await t.pump();
      expect(
        find.byWidgetPredicate((w) => w is DropdownButtonFormField),
        findsOneWidget,
      );
      expect((f.member('firstItemFocusNode') as FocusNode).hasFocus, isTrue);
      (f.member('viewModeDropdownFocusNode') as FocusNode).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pump();
      expect((f.member('backButtonFocusNode') as FocusNode).hasFocus, isTrue);
      var sidebar = 0;
      MainPageBridge.focusTvSidebar = () {
        sidebar++;
      };
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(sidebar, 1);
      f.pages['empty'] = [];
      f.member('navigateIntoFolder')(premiumizeItem('empty', folder: true));
      await f.until(t, () => f.member('isLoading') == false);
      await t.pump();
      await t.pump();
      expect(
        (f.member('addLinkButtonFocusNode') as FocusNode).hasFocus,
        isTrue,
      );
      expect(find.text('Folder is Empty'), findsOneWidget);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/list', {'id': 'z9'}),
        f.getRequest('folder/list', {'id': 'empty'}),
      ]);
    }),
  );
  testWidgets(
    'TV tab 11 closure requests first row focus',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      expect(MainPageBridge.requestTvContentFocus(), isTrue);
      await t.pump();
      await t.pump();
      expect((f.member('firstItemFocusNode') as FocusNode).hasFocus, isTrue);
      expect(f.member('shouldFocusOnLoad'), isFalse);
      expect(f.log, [f.getRequest('folder/list')]);
    }),
  );
  testWidgets(
    'transfers statuses progress fallback Clear finished visibility',
    (t) => premiumizeCase(t, (f) async {
      f.transfers = [
        ...f.transfers,
        {
          'id': 't0',
          'name': 'Queued fixture',
          'status': 'queued',
          'progress': 0,
        },
      ];
      await f.mount(t);
      await t.tap(find.text('Transfers'));
      await f.until(t, () => f.member('isLoadingTransfers') == false);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.downloading_rounded), findsNWidgets(2));
      expect(
        t
            .widgetList<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .map((w) => w.value),
        [0.5, null],
      );
      expect(find.text('Finished'), findsOneWidget);
      expect(find.text('Error'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('Clear finished'), findsOneWidget);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('transfer/list'),
      ]);
    }),
  );
  testWidgets(
    'fixed old date yields date only and zero is empty',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      final date = DateTime(2026, 1, 15);
      expect(
        f.member('formatUnixDate')(date.millisecondsSinceEpoch ~/ 1000),
        '1/15/2026',
      );
      expect(f.member('formatUnixDate')(0), '');
    }),
  );
  for (final view in [
    'root',
    'folder',
    'selection',
    'transfers',
    'select-source',
    'search-results',
    'not-configured',
  ]) {
    final host = Platform.isLinux ? 'linux' : 'macos';
    final path = 'test/goldens/premiumize_files/$host/$view.png';
    testWidgets(
      'reachable pixel golden $view',
      (t) => premiumizeCase(
        t,
        (f) async {
          await f.mount(t, picker: view == 'select-source');
          if (view == 'folder') {
            f.member('navigateIntoFolder')(premiumizeItem('z9', folder: true));
            await f.until(t, () => f.member('isLoading') == false);
          }
          if (view == 'selection') {
            f.member('toggleSelectionMode')();
            f.member('toggleSelection')('a2');
          }
          if (view == 'transfers') {
            f.member('switchView')(f.member('transfersView'));
            await f.until(t, () => f.member('isLoadingTransfers') == false);
          }
          if (view == 'search-results') {
            f.member('toggleSearch')();
            await t.pump();
            await t.enterText(find.byType(TextField), 'Alpha');
            await t.pump(const Duration(milliseconds: 350));
            await f.until(t, () => f.member('isSearching') == false);
          }
          await t.pump();
          FocusManager.instance.primaryFocus?.unfocus();
          await t.pump();
          await t.pump(const Duration(milliseconds: 500));
          if (Platform.isLinux &&
              !requireLinux &&
              !captureLinux &&
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
            find.byKey(const ValueKey('premiumize-canvas')),
            matchesGoldenFile(
              '../../../../goldens/premiumize_files/$host/$view.png',
            ),
          );
        },
        preferences: view == 'not-configured'
            ? {'premiumize_integration_enabled': false}
            : {},
      ),
    );
  }
}
