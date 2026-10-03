import 'dart:async';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/pikpak_files_fixture.dart';

void main() {
  for (final folder in [false, true]) {
    testWidgets(
      'real picker row binding folder=$folder awaits callback before screen pop',
      (t) => pikpakCase(t, (f) async {
        final selected = <SeriesSource>[];
        final done = Completer<void>();
        final before = DateTime.now().millisecondsSinceEpoch;
        await f.mount(
          t,
          pushed: true,
          picker: true,
          selected: (s) async {
            selected.add(s);
            await done.future;
          },
        );
        await t.tap(find.text(folder ? 'Folder z9' : 'Video a2.mkv'));
        await f.until(t, () => selected.isNotEmpty);
        await t.pump(const Duration(milliseconds: 600));
        expect(selected.length, 1);
        final s = selected.single;
        expect(s.torrentHash, '');
        expect(s.torrentName, folder ? 'Folder z9' : 'Video a2.mkv');
        expect(s.debridService, 'pikpak');
        expect(s.debridTorrentId, folder ? 'z9' : 'a2');
        expect(
          s.cloudSourceKind,
          folder ? SeriesSource.cloudKindFolder : SeriesSource.cloudKindFile,
        );
        expect(
          s.boundAt,
          inInclusiveRange(before, DateTime.now().millisecondsSinceEpoch),
        );
        expect(f.observer.popped.length, 1);
        expect(f.observer.popped.single, isA<DialogRoute<void>>());
        expect(f.key.currentState, isNotNull);
        expect(find.text('Checking PikPak source...'), findsNothing);
        done.complete();
        await f.until(t, () => f.observer.popped.length == 2);
        await t.pump(const Duration(milliseconds: 600));
        expect(find.text('Caller'), findsOneWidget);
        expect(f.observer.popped.last, isA<MaterialPageRoute<void>>());
        expect(selected.length, 1);
        expect(
          f.requests.map((r) => (r.method, r.url.path)),
          folder
              ? [
                  ('GET', '/drive/v1/files'),
                  ('GET', '/drive/v1/files/z9'),
                  ('GET', '/drive/v1/files'),
                  ('GET', '/drive/v1/files/n6'),
                ]
              : [('GET', '/drive/v1/files'), ('GET', '/drive/v1/files/a2')],
        );
      }),
    );
  }
  testWidgets(
    'readiness probes await full recursive pages then sequential children and stop after success',
    (t) => pikpakCase(t, (f) async {
      f.pages['z9|'] = f.page([
        pikpakFile('i8', complete: false),
        pikpakFile('t4'),
        pikpakFile('q2', folder: true),
      ], next: 'token-v3');
      f.pages['q2|'] = f.page([pikpakFile('u7', url: false)]);
      final pageHeld = Completer<http.Response>();
      f.heldPages['z9|token-v3'] = pageHeld;
      final childHeld = Completer<http.Response>();
      f.heldDetails['t4'] = childHeld;
      f.details['u7'] = pikpakFile('u7', url: false);
      final selected = <SeriesSource>[];
      final callback = Completer<void>();
      await f.mount(
        t,
        pushed: true,
        picker: true,
        selected: (s) async {
          selected.add(s);
          await callback.future;
        },
      );
      await t.tap(find.text('Folder z9'));
      await f.until(t, () => f.requests.length == 5);
      expect(selected, isEmpty);
      expect(f.requests.map((r) => r.url.path), [
        '/drive/v1/files',
        '/drive/v1/files/z9',
        '/drive/v1/files',
        '/drive/v1/files',
        '/drive/v1/files',
      ]);
      expect(f.requests.last.url.queryParameters['page_token'], 'token-v3');
      pageHeld.complete(f.json(f.page([pikpakFile('a2'), pikpakFile('n6')])));
      await f.until(t, () => f.requests.length == 6);
      expect(f.requests.last.url.path, '/drive/v1/files/t4');
      expect(selected, isEmpty);
      await t.pump();
      expect(f.requests.length, 6);
      childHeld.complete(
        f.json({'error_description': 'fixture details failure'}, 500),
      );
      await f.until(t, () => selected.length == 1);
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
          ('GET', '/drive/v1/files/z9', null, null),
          ('GET', '/drive/v1/files', 'z9', null),
          ('GET', '/drive/v1/files', 'q2', null),
          ('GET', '/drive/v1/files', 'z9', 'token-v3'),
          ('GET', '/drive/v1/files/t4', null, null),
          ('GET', '/drive/v1/files/u7', null, null),
          ('GET', '/drive/v1/files/a2', null, null),
        ],
      );
      expect(selected.single.debridTorrentId, 'z9');
      callback.complete();
      await t.pump(const Duration(milliseconds: 600));
    }),
  );
  for (final reason in [
    'folder_not_complete',
    'no_videos',
    'no_ready',
    'file_not_ready',
    'file_no_url',
    'error',
  ]) {
    testWidgets(
      'picker validation rejection $reason through real row',
      (t) => pikpakCase(t, (f) async {
        final folder = reason.startsWith('folder') || reason.startsWith('no_');
        var count = 0;
        if (reason == 'folder_not_complete') {
          f.details['z9'] = pikpakFile('z9', folder: true, complete: false);
        }
        if (reason == 'no_videos') {
          f.pages['z9|'] = f.page([pikpakFile('b3', video: false)]);
        }
        if (reason == 'no_ready') {
          f.pages['z9|'] = f.page([pikpakFile('b3', url: false)]);
          f.details['b3'] = pikpakFile('b3', url: false);
        }
        if (reason == 'file_not_ready') {
          f.details['a2'] = pikpakFile('a2', complete: false);
        }
        if (reason == 'file_no_url') {
          f.details['a2'] = pikpakFile('a2', url: false);
        }
        if (reason == 'error') f.failingDetails.add('a2');
        await f.mount(
          t,
          pushed: true,
          picker: true,
          selected: (s) async {
            count++;
          },
        );
        await t.tap(find.text(folder ? 'Folder z9' : 'Video a2.mkv'));
        await f.until(t, () => f.observer.popped.isNotEmpty);
        await t.pump(const Duration(milliseconds: 600));
        expect(count, 0);
        expect(f.key.currentState, isNotNull);
        expect(f.observer.popped.length, 1);
        expect(f.observer.popped.single, isA<DialogRoute<void>>());
        final message = reason == 'folder_not_complete'
            ? 'This PikPak folder is not ready to stream'
            : reason == 'no_videos'
            ? 'This folder has no playable videos'
            : reason == 'no_ready'
            ? 'This PikPak folder has no ready video streams'
            : reason == 'error'
            ? 'Could not bind this PikPak source:'
            : 'This PikPak file is not ready to stream';
        expect(find.textContaining(message), findsOneWidget);
      }),
    );
  }
  testWidgets(
    'disabled incomplete and non-video picker rows have no callback through UI',
    (t) => pikpakCase(t, (f) async {
      f.rows = [
        pikpakFile('a2', complete: false),
        pikpakFile('m5', video: false),
      ];
      var count = 0;
      await f.mount(
        t,
        pushed: true,
        picker: true,
        selected: (s) async {
          count++;
        },
      );
      expect(find.byTooltip('Select items'), findsNothing);
      expect(find.byTooltip('Add Link'), findsNothing);
      expect(find.text('Select PikPak Source'), findsOneWidget);
      for (final row in t.widgetList<CloudFileRow>(find.byType(CloudFileRow))) {
        expect(row.onTap, isNull);
      }
      await t.tap(find.text('Video a2.mkv'));
      await t.pump();
      await t.tap(find.text('Archive m5.zip'));
      await t.pump();
      expect(count, 0);
      expect(f.requests.length, 1);
      expect(find.text('Still downloading'), findsOneWidget);
    }, preferences: {'pikpak_show_videos_only': false}),
  );
  for (final file in [
    <String, dynamic>{'id': '', 'name': 'Empty.mkv', 'mime_type': 'video/mkv'},
    <String, dynamic>{'id': 'z9', 'name': 'Archive.zip', 'kind': 'drive#file'},
  ]) {
    testWidgets(
      'accessor invalid unselectable input ${file['name']} rejects before dialog',
      (t) => pikpakCase(t, (f) async {
        await f.mount(t, pushed: true, picker: true);
        await f.member('selectBoundSource')(file);
        await t.pump();
        expect(f.requests.length, 1);
        expect(f.observer.popped, isEmpty);
        expect(find.text('Choose a video file or folder'), findsOneWidget);
      }),
    );
  }
  testWidgets(
    'search row binds incomplete loaded file without completeness entry check',
    (t) => pikpakCase(t, (f) async {
      f.rows = [pikpakFile('a2', complete: false)];
      final selected = <SeriesSource>[];
      final callback = Completer<void>();
      await f.mount(
        t,
        pushed: true,
        picker: true,
        selected: (s) async {
          selected.add(s);
          await callback.future;
        },
      );
      f.pages['z9|'] = f.page(f.rows);
      f.member('navigateIntoFolder')('z9', 'Folder z9');
      await f.until(t, () => f.member('isLoading') == false);
      f.member('toggleSearch')();
      await t.pump();
      await t.enterText(find.byType(TextField), 'Video');
      await t.pump();
      await t.tap(find.text('Video a2.mkv'));
      await f.until(t, () => selected.isNotEmpty);
      expect(selected.single.debridTorrentId, 'a2');
      expect(f.requests.length, 3);
      callback.complete();
      await t.pump(const Duration(milliseconds: 600));
    }),
  );
  testWidgets(
    'checking-dialog system Back hazard later root pop removes underlying screen',
    (t) => pikpakCase(t, (f) async {
      final held = Completer<http.Response>();
      f.heldDetails['a2'] = held;
      final callback = Completer<void>();
      var count = 0;
      await f.mount(
        t,
        pushed: true,
        picker: true,
        selected: (s) async {
          count++;
          await callback.future;
        },
      );
      await t.tap(find.text('Video a2.mkv'));
      await f.until(t, () => f.requests.length == 2);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Checking PikPak source...'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 600));
      expect(f.observer.popped.length, 1);
      expect(f.observer.popped.single, isA<DialogRoute<void>>());
      expect(f.key.currentState, isNotNull);
      held.complete(f.json(pikpakFile('a2')));
      await f.until(t, () => f.observer.popped.length == 2);
      await t.pump(const Duration(milliseconds: 600));
      expect(f.observer.popped.last, isA<MaterialPageRoute<void>>());
      expect(find.text('Caller'), findsOneWidget);
      expect(count, 1);
      callback.complete();
      await t.pump();
      expect(f.observer.popped.length, 2);
    }),
  );
}
