import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/widgets/file_selection_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/premiumize_files_fixture.dart';

void main() {
  for (final text in [
    ' http://example.test/a ',
    'https://example.test/a',
    'magnet:?xt=fixture',
    'ignored',
    'ftp://example.test/a',
    '',
  ]) {
    testWidgets(
      'clipboard autopaste accepted prefixes $text',
      (t) => premiumizeCase(t, (f) async {
        await f.mount(t);
        f.clipboardText = text;
        await f.member('autoPasteLink')();
        expect(
          (f.member('linkController') as TextEditingController).text,
          ['ignored', 'ftp://example.test/a', ''].contains(text)
              ? ''
              : text.trim(),
        );
        expect(f.log, [f.getRequest('folder/list')]);
      }),
    );
  }
  for (final nested in [false, true]) {
    testWidgets(
      'Add Link Cancel uses lexical navigator nested=$nested',
      (t) => premiumizeCase(t, (f) async {
        await f.mount(t, useNested: nested);
        if (nested) await f.transitions(t);
        f.clipboardText = 'magnet:?xt=fixture';
        await t.tap(find.byTooltip('Add to Premiumize'));
        await f.transitions(t);
        expect(find.text('Add to Premiumize'), findsOneWidget);
        expect(
          (f.member('linkController') as TextEditingController).text,
          'magnet:?xt=fixture',
        );
        await t.tap(find.text('Cancel'));
        await f.transitions(t);
        expect((f.member('linkController') as TextEditingController).text, '');
        expect(f.key.currentState, isNotNull);
        expect(f.nestedObserver.popped, isEmpty);
        expect(f.observer.popped.whereType<PopupRoute>().length, 1);
        expect(f.log, [f.getRequest('folder/list')]);
      }),
    );
  }
  for (final link in ['', 'invalid']) {
    testWidgets(
      'Add Link validates $link',
      (t) => premiumizeCase(t, (f) async {
        await f.mount(t);
        await t.tap(find.byTooltip('Add to Premiumize'));
        await f.transitions(t);
        await t.enterText(find.byType(TextField), link);
        await t.tap(find.text('Add'));
        await t.pump();
        expect(
          find.text(
            link.isEmpty
                ? 'Please enter a link'
                : 'Please enter a valid URL or magnet link',
          ),
          findsOneWidget,
        );
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(f.log, [f.getRequest('folder/list')]);
        await t.tap(find.text('Cancel'));
        await f.transitions(t);
      }),
    );
  }
  for (final folder in [false, true]) {
    for (final failure in [false, true]) {
      testWidgets(
        'Add Link exact POST refresh and failure folder=$folder failure=$failure',
        (t) => premiumizeCase(t, (f) async {
          await f.mount(t);
          if (folder) {
            f.member('navigateIntoFolder')(premiumizeItem('z9', folder: true));
            await f.until(t, () => f.member('isLoading') == false);
          }
          if (failure) f.failures.add('transfer/create|');
          await t.tap(find.byTooltip('Add to Premiumize'));
          await f.transitions(t);
          await t.enterText(find.byType(TextField), '  magnet:?xt=fixture  ');
          await t.tap(find.text('Add'));
          await f.until(
            t,
            () =>
                f.requests.any((r) => r.url.path == '/api/transfer/create') &&
                f.member('isAddingLink') == false,
          );
          await f.transitions(t);
          expect(f.log, [
            f.getRequest('folder/list'),
            if (folder) f.getRequest('folder/list', {'id': 'z9'}),
            f.postRequest(
              'transfer/create',
              {'src': 'magnet:?xt=fixture', if (folder) 'folder_id': 'z9'},
              {'apikey': 'fixture-key'},
            ),
            if (!failure)
              f.getRequest('folder/list', folder ? {'id': 'z9'} : {}),
          ]);
          expect(find.byType(AlertDialog), findsNothing);
          expect(
            f.observer.popped.whereType<PopupRoute>().length,
            2,
            reason: 'input and loading dialogs pop separately',
          );
          expect(
            find.textContaining(
              failure ? 'Failed to add:' : 'Added to Premiumize',
            ),
            findsOneWidget,
          );
          expect(
            (f.member('linkController') as TextEditingController).text,
            failure ? '  magnet:?xt=fixture  ' : '',
          );
        }),
      );
    }
  }
  testWidgets(
    'nested Add uses State pop root dismiss leaves lexical Add dialog',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t, useNested: true);
      await f.transitions(t);
      await t.tap(find.byTooltip('Add to Premiumize'));
      await f.transitions(t);
      await t.enterText(find.byType(TextField), 'magnet:?xt=fixture');
      await t.tap(find.text('Add'));
      await f.until(t, () => f.requests.length >= 2);
      await t.pump();
      expect(
        f.nestedObserver.popped.whereType<PageRoute>().length,
        1,
        reason: 'Add pops State nested navigator',
      );
      expect(
        f.observer.popped.whereType<PopupRoute>().length,
        1,
        reason: 'dismiss pops root loading dialog',
      );
      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: 'root input dialog survives State pop',
      );
      await f.transitions(t);
      expect(find.text('Nested caller'), findsOneWidget);
      f.navigatorKey.currentState!.pop();
      await f.transitions(t);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.postRequest(
          'transfer/create',
          {'src': 'magnet:?xt=fixture'},
          {'apikey': 'fixture-key'},
        ),
        f.getRequest('folder/list'),
      ]);
    }),
  );
  for (final kind in [
    'file',
    'non-video',
    'single-folder',
    'collection-folder',
  ]) {
    testWidgets(
      'playlist persisted original map $kind',
      (t) => premiumizeCase(t, (f) async {
        f.pages['z9'] = kind == 'single-folder'
            ? [premiumizeFile('a2')]
            : [
                premiumizeFile('m5'),
                premiumizeFile('a2'),
                premiumizeFile('archive', video: false),
              ];
        await f.mount(t);
        await f.member('addToPlaylist')(
          premiumizeItem(
            kind.endsWith('folder') ? 'z9' : 'a2',
            folder: kind.endsWith('folder'),
            video: kind != 'non-video',
          ),
        );
        await f.transitions(t);
        final entries = await PlaylistStorage.getPlaylistItemsRaw();
        if (kind == 'non-video') {
          expect(entries, isEmpty);
          expect(
            find.text('Only video files can be added to playlist'),
            findsOneWidget,
          );
        } else {
          expect(entries.length, 1);
          final r = entries.single;
          expect(r['provider'], 'premiumize');
          expect(
            r['kind'],
            kind == 'collection-folder' ? 'collection' : 'single',
          );
          expect(
            r['premiumizeItemId'],
            kind == 'collection-folder' ? 'z9' : 'a2',
          );
          if (kind == 'collection-folder') {
            expect(r['premiumizeItemIds'], ['m5', 'a2']);
            expect(r['premiumizeFiles'], [
              {'id': 'm5', 'name': 'Video m5.mkv', 'size': 209715200},
              {'id': 'a2', 'name': 'Video a2.mkv', 'size': 209715200},
            ]);
            expect(r['count'], 2);
          } else {
            expect(r['premiumizeFile'], {
              'id': 'a2',
              'name': 'Video a2.mkv',
              'size': 209715200,
            });
            expect(r['sizeBytes'], 209715200);
          }
          await f.member('addToPlaylist')(
            premiumizeItem(
              kind.endsWith('folder') ? 'z9' : 'a2',
              folder: kind.endsWith('folder'),
            ),
          );
          await f.waitForText(t, 'Already in playlist');
          expect((await PlaylistStorage.getPlaylistItemsRaw()).length, 1);
          expect(find.text('Already in playlist'), findsOneWidget);
        }
        expect(f.log, [
          f.getRequest('folder/list'),
          if (kind.endsWith('folder'))
            ...List.generate(
              2,
              (_) => f.getRequest('folder/list', {'id': 'z9'}),
            ),
        ]);
      }),
    );
  }
  testWidgets(
    'folder download dialog preserves exact maps and unawaited dispatch',
    (t) => premiumizeCase(t, (f) async {
      f.pages['z9'] = [
        premiumizeFile('m5'),
        premiumizeFile('sub', name: 'Sub', folder: true),
      ];
      f.pages['sub'] = [premiumizeFile('a2', url: false)];
      await f.mount(t);
      final action =
          f.member('downloadFolder')(premiumizeItem('z9', folder: true))
              as Future<void>;
      await f.until(
        t,
        () => find.byType(FileSelectionDialog).evaluate().isNotEmpty,
      );
      await f.transitions(t);
      final dialog = t.widget<FileSelectionDialog>(
        find.byType(FileSelectionDialog),
      );
      expect(dialog.torrentName, 'Folder z9');
      expect(dialog.files, [
        {
          'name': 'Video m5.mkv',
          '_fullPath': 'Video m5.mkv',
          'size': '209715200',
          '_premiumizeIndex': 0,
        },
        {
          'name': 'Sub/Video a2.mkv',
          '_fullPath': 'Sub/Video a2.mkv',
          'size': '209715200',
          '_premiumizeIndex': 1,
        },
      ]);
      await f.member('downloadSelectedFiles')(
        [
          {'_premiumizeIndex': -1},
          {'_premiumizeIndex': 9},
          {'_premiumizeIndex': 1},
        ],
        [premiumizeItem('m5'), premiumizeItem('a2', url: false)],
        'Folder z9',
      );
      await t.pump();
      expect(find.text('Failed to queue any files'), findsOneWidget);
      f.navigatorKey.currentState!.pop();
      await action;
      await f.transitions(t);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/list', {'id': 'z9'}),
        f.getRequest('folder/list', {'id': 'sub'}),
      ]);
    }),
  );
  testWidgets(
    'missing playable and download URLs reject without notification',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      var notifications = 0;
      void listener() {
        notifications++;
      }

      MainPageBridge.addPlayerLaunchListener(listener);
      try {
        f.failures.add('item/details|a2');
        await f.member('playFile')(premiumizeItem('a2', url: false));
        await t.pump();
        expect(notifications, 0);
        expect(find.text('No playable URL for this file'), findsOneWidget);
        await f.member('playPremiumizeVideos')([
          premiumizeItem('m5', url: false),
        ], 'Collection');
        await f.member('downloadFile')(premiumizeItem('m5', url: false));
        await f.waitForText(t, 'No download URL for this file');
        expect(notifications, 0);
        expect(find.text('No download URL for this file'), findsOneWidget);
        expect(f.log, [
          f.getRequest('folder/list'),
          f.getRequest('item/details', {'id': 'a2'}),
        ]);
      } finally {
        MainPageBridge.removePlayerLaunchListener(listener);
      }
    }),
  );
}
