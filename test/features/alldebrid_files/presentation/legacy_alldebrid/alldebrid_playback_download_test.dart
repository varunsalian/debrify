import 'dart:async';
import 'package:debrify/widgets/file_selection_dialog.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/alldebrid_files_fixture.dart';

void main() {
  for (final series in [false, true]) {
    testWidgets(
      'multi-file play unlocks start first then sequential fallback with all failures series=$series',
      (t) => allDebridCase(t, (f) async {
        if (!series) {
          f.files = [
            adFile('z9', name: 'Zeta.mkv'),
            adFile('a2', name: 'Alpha.mkv'),
            adFile('m5', name: 'Beta.mkv'),
          ];
        }
        final held = Completer<http.Response>();
        f.held['/v4/link/unlock|https://locked.test/file-a2'] = held;
        await f.mount(t);
        await f.action(t, 'Library z9', 'Play');
        await f.until(t, () => f.requests.length == 3);
        expect(f.log, [
          adList(),
          adFiles('z9'),
          adUnlock('https://locked.test/file-a2'),
        ]);
        expect(find.text('Unlocking…'), findsOneWidget);
        await t.pump();
        expect(f.requests.length, 3);
        held.complete(AllDebridFixture.success({'link': ''}));
        await f.until(
          t,
          () =>
              f.requests.length == 5 && f.member('loadingDialogOpen') == false,
        );
        expect(f.log, [
          adList(),
          adFiles('z9'),
          for (final id in ['a2', 'm5', 'z9'])
            adUnlock('https://locked.test/file-$id'),
        ]);
        expect(
          find.text('Failed to resolve playable links from AllDebrid.'),
          findsOneWidget,
        );
      }),
    );
  }
  testWidgets(
    'magnet Play with no videos shows original snack without unlocking',
    (t) => allDebridCase(t, (f) async {
      f.files = [adFile('notes', name: 'Notes.txt')];
      await f.mount(t);
      await f.action(t, 'Library z9', 'Play');
      await f.until(
        t,
        () => find.text('No playable video files found.').evaluate().isNotEmpty,
      );
      expect(f.log, [adList(), adFiles('z9')]);
    }),
  );
  testWidgets(
    'single-video magnet shortcuts to file unlock failure snack',
    (t) => allDebridCase(t, (f) async {
      f.files = [adFile('single'), adFile('notes', name: 'Notes.txt')];
      await f.mount(t);
      await f.action(t, 'Library z9', 'Play');
      await f.until(
        t,
        () => find.text('Failed to unlock this file.').evaluate().isNotEmpty,
      );
      expect(f.log, [
        adList(),
        adFiles('z9'),
        adUnlock('https://locked.test/file-single'),
      ]);
    }),
  );
  for (final kind in [
    'file_play',
    'file_download',
    'link_play',
    'link_download',
  ]) {
    testWidgets(
      'real row action unlock failure retains exact request and message kind=$kind',
      (t) => allDebridCase(t, (f) async {
        await f.mount(t);
        final web = kind.startsWith('link');
        if (web) {
          await f.web(t);
        } else {
          await f.open(t);
        }
        final title = web ? 'Saved w8.mkv' : 'A.S02E01.mkv';
        if (kind.endsWith('play')) {
          await f.tap(t, find.text(title));
        } else {
          await f.action(t, title, web ? 'Download to device' : 'Download');
        }
        await f.until(
          t,
          () => find
              .text(
                web
                    ? 'Failed to unlock this link.'
                    : 'Failed to unlock this file.',
              )
              .evaluate()
              .isNotEmpty,
        );
        expect(f.log, [
          adList(),
          web ? adLinks() : adFiles('z9'),
          adUnlock(
            web ? 'https://locked.test/w8' : 'https://locked.test/file-z9',
          ),
        ]);
      }),
    );
  }
  testWidgets(
    'magnet Download opens actual selection dialog with exact maps and failure loop callback order',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      await f.action(t, 'Library z9', 'Download to device');
      await f.until(
        t,
        () => find.byType(FileSelectionDialog).evaluate().isNotEmpty,
      );
      final finder = find.byType(FileSelectionDialog);
      final dialog = t.widget<FileSelectionDialog>(finder);
      expect(dialog.torrentName, 'Library z9');
      expect(dialog.files, [
        {
          'name': 'Root/A.S02E01.mkv',
          '_fullPath': 'Root/A.S02E01.mkv',
          'size': '1000',
          '_adIndex': 0,
        },
        {
          'name': 'Root/C.S01E01.mkv',
          '_fullPath': 'Root/C.S01E01.mkv',
          'size': '1000',
          '_adIndex': 1,
        },
        {
          'name': 'Root/B.S01E02.mkv',
          '_fullPath': 'Root/B.S01E02.mkv',
          'size': '1000',
          '_adIndex': 2,
        },
        {
          'name': 'Root/Notes.txt',
          '_fullPath': 'Root/Notes.txt',
          'size': '1000',
          '_adIndex': 3,
        },
      ]);
      // The real dialog callback accepts synthetic maps for invalid-index cases;
      // no production action seam is used. Preserve dialog's pop-before-dispatch.
      Navigator.of(t.element(finder)).pop();
      final held = Completer<http.Response>();
      f.held['/v4/link/unlock|https://locked.test/file-m5'] = held;
      dialog.onDownload([
        {},
        {'_adIndex': -1},
        {'_adIndex': 99},
        {'_adIndex': 2},
        {'_adIndex': 0},
      ]);
      await f.until(t, () => f.requests.length == 3);
      expect(f.log, [
        adList(),
        adFiles('z9'),
        adUnlock('https://locked.test/file-m5'),
      ]);
      await t.pump();
      expect(f.requests.length, 3);
      held.complete(AllDebridFixture.success({'link': ''}));
      await f.until(
        t,
        () => find.text('Failed to queue any files').evaluate().isNotEmpty,
      );
      expect(f.log, [
        adList(),
        adFiles('z9'),
        adUnlock('https://locked.test/file-m5'),
        adUnlock('https://locked.test/file-z9'),
      ]);
    }),
  );
  testWidgets(
    'missing negative and out-of-range selection indices fail without any unlock request',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      await f.action(t, 'Library z9', 'Download to device');
      await f.until(
        t,
        () => find.byType(FileSelectionDialog).evaluate().isNotEmpty,
      );
      final finder = find.byType(FileSelectionDialog);
      final dialog = t.widget<FileSelectionDialog>(finder);
      Navigator.of(t.element(finder)).pop();
      dialog.onDownload([
        {},
        {'_adIndex': -2},
        {'_adIndex': 4},
      ]);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Failed to queue any files'), findsOneWidget);
      expect(f.log, [adList(), adFiles('z9')]);
    }),
  );
  testWidgets(
    'copy saved link writes unlocked URL to clipboard after exact unlock',
    (t) => allDebridCase(t, (f) async {
      f.defaultUnlockUrl = 'https://unlocked.test/copied.mkv';
      await f.mount(t);
      await f.web(t);
      await f.action(t, 'Saved w8.mkv', 'Copy link');
      await f.until(t, () => f.clipboard.isNotEmpty);
      expect(f.clipboard, ['https://unlocked.test/copied.mkv']);
      expect(find.text('Link copied'), findsOneWidget);
      expect(f.log, [adList(), adLinks(), adUnlock('https://locked.test/w8')]);
    }),
  );
  testWidgets(
    'duplicate loading requests share one non-dismissible modal and one flag',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      await f.open(t);
      final held = Completer<http.Response>();
      f.held['/v4/link/unlock'] = held;
      f.observer.pushed.clear();
      // Invoke the real row's interaction dispatch twice; the first invocation
      // installs the modal immediately, blocking a second physical gesture.
      final tap = t.widget<CloudFileRow>(f.row('A.S02E01.mkv')).onTap!;
      tap();
      tap();
      await t.pump();
      await f.until(t, () => f.requests.length == 4);
      expect(f.member('loadingDialogOpen'), isTrue);
      expect(find.text('Unlocking…'), findsOneWidget);
      final modals = f.observer.pushed
          .whereType<ModalRoute<dynamic>>()
          .toList();
      expect(modals, hasLength(1));
      expect(modals.single.barrierDismissible, isFalse);
      held.complete(AllDebridFixture.success({'link': ''}));
      await f.until(t, () => f.member('loadingDialogOpen') == false);
      expect(f.log, [
        adList(),
        adFiles('z9'),
        adUnlock('https://locked.test/file-z9'),
        adUnlock('https://locked.test/file-z9'),
      ]);
    }),
  );
  testWidgets(
    'system Back pops loading dialog while flag stays true then dismiss pops pushed screen',
    (t) => allDebridCase(t, (f) async {
      final held = Completer<http.Response>();
      f.held['/v4/link/unlock'] = held;
      await f.mount(t, pushed: true);
      await f.open(t);
      f.observer.popped.clear();
      await f.tap(t, find.text('A.S02E01.mkv'));
      await f.until(t, () => f.requests.length == 3);
      expect(f.member('loadingDialogOpen'), isTrue);
      expect(find.text('Unlocking…'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Unlocking…'), findsNothing);
      expect(f.member('loadingDialogOpen'), isTrue);
      expect(f.observer.popped, hasLength(1));
      expect(f.observer.popped.single, isA<PopupRoute<dynamic>>());
      expect(f.key.currentState, isNotNull);
      held.complete(AllDebridFixture.success({'link': ''}));
      await f.until(t, () => f.observer.popped.length == 2);
      await t.pump(const Duration(milliseconds: 600));
      expect(f.observer.popped.last, isA<MaterialPageRoute<void>>());
      expect(find.text('Caller'), findsOneWidget);
      expect(f.key.currentState, isNull);
      expect(f.log, [
        adList(),
        adFiles('z9'),
        adUnlock('https://locked.test/file-z9'),
      ]);
    }),
  );
}
