import 'dart:async';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/premiumize_files_fixture.dart';

void main() {
  for (final kind in ['folder-url', 'folder-resolve', 'file']) {
    testWidgets(
      'binding awaits callback before pushed pop $kind',
      (t) => premiumizeCase(t, (f) async {
        final callback = Completer<void>();
        final sources = <SeriesSource>[];
        f.pages['z9'] = [premiumizeFile('first', url: kind == 'folder-url')];
        await f.mount(
          t,
          pushed: true,
          picker: true,
          selected: (s) async {
            sources.add(s);
            await callback.future;
          },
        );
        await f.transitions(t);
        final start = DateTime.now().millisecondsSinceEpoch;
        final action =
            f.member('selectBoundSource')(
                  premiumizeItem(
                    kind == 'file' ? 'a2' : 'z9',
                    folder: kind != 'file',
                  ),
                )
                as Future<void>;
        await f.until(t, () => sources.isNotEmpty);
        await f.transitions(t);
        final s = sources.single;
        expect(s.torrentHash, '');
        expect(s.torrentName, kind == 'file' ? 'Video a2.mkv' : 'Folder z9');
        expect(s.debridService, 'premiumize');
        expect(s.debridTorrentId, kind == 'file' ? 'a2' : 'z9');
        expect(
          s.cloudSourceKind,
          kind == 'file'
              ? SeriesSource.cloudKindFile
              : SeriesSource.cloudKindFolder,
        );
        expect(s.boundAt, greaterThanOrEqualTo(start));
        expect(
          f.observer.popped.whereType<PopupRoute>().length,
          1,
          reason: 'checking dialog closes once',
        );
        expect(
          f.observer.popped.whereType<PageRoute>(),
          isEmpty,
          reason: 'screen waits for callback completion',
        );
        callback.complete();
        await action;
        await f.transitions(t);
        expect(f.observer.popped.whereType<PageRoute>().length, 1);
        expect(f.log, [
          f.getRequest('folder/list'),
          if (kind != 'file') f.getRequest('folder/list', {'id': 'z9'}),
          if (kind != 'folder-url')
            f.getRequest('item/details', {
              'id': kind == 'file' ? 'a2' : 'first',
            }),
        ]);
      }),
    );
  }
  for (final rejection in [
    'no-videos',
    'first-unready',
    'non-video',
    'file-unready',
    'throw',
  ]) {
    testWidgets(
      'bind rejection exact readiness and message $rejection',
      (t) => premiumizeCase(t, (f) async {
        var called = 0;
        f.pages['z9'] = rejection == 'no-videos'
            ? [premiumizeFile('archive', video: false)]
            : [premiumizeFile('first', url: false), premiumizeFile('second')];
        if (rejection == 'first-unready') f.failures.add('item/details|first');
        if (rejection == 'file-unready') f.failures.add('item/details|a2');
        if (rejection == 'throw') f.failures.add('folder/list|z9');
        await f.mount(
          t,
          pushed: true,
          picker: true,
          selected: (_) async {
            called++;
          },
        );
        await f.transitions(t);
        final folder = [
          'no-videos',
          'first-unready',
          'throw',
        ].contains(rejection);
        await f.member('selectBoundSource')(
          premiumizeItem(
            folder ? 'z9' : 'a2',
            folder: folder,
            video: rejection != 'non-video',
          ),
        );
        await f.transitions(t);
        expect(called, 0);
        expect(f.observer.popped.whereType<PageRoute>(), isEmpty);
        expect(f.observer.popped.whereType<PopupRoute>().length, 1);
        final message = switch (rejection) {
          'no-videos' => 'This folder has no playable videos',
          'first-unready' => 'This folder has no ready video streams',
          'non-video' => 'Only video files can be bound',
          'file-unready' => 'This file is not ready to stream',
          _ => 'Could not bind this Premiumize source:',
        };
        expect(find.textContaining(message), findsOneWidget);
        expect(f.log, [
          f.getRequest('folder/list'),
          if (folder) f.getRequest('folder/list', {'id': 'z9'}),
          if (rejection == 'first-unready')
            f.getRequest('item/details', {'id': 'first'}),
          if (rejection == 'file-unready')
            f.getRequest('item/details', {'id': 'a2'}),
        ]);
      }),
    );
  }
  for (final folder in [false, true]) {
    testWidgets(
      'held binding disposal asymmetric callback folder=$folder',
      (t) => premiumizeCase(t, (f) async {
        var called = 0;
        final h = Completer<http.Response>();
        f.held[folder ? 'folder/list|z9' : 'item/details|a2'] = h;
        await f.mount(
          t,
          pushed: true,
          picker: true,
          selected: (_) async {
            called++;
          },
        );
        await f.transitions(t);
        final action =
            f.member('selectBoundSource')(
                  premiumizeItem(folder ? 'z9' : 'a2', folder: folder),
                )
                as Future<void>;
        await f.until(t, () => f.requests.length == 2);
        await f.close(t);
        h.complete(
          f.json(
            folder
                ? f.page([premiumizeFile('first')])
                : {'status': 'success', ...premiumizeFile('a2')},
          ),
        );
        await action;
        expect(
          called,
          folder ? 0 : 1,
          reason: 'file binding calls callback after disposal',
        );
        expect(f.observer.popped, isEmpty);
        expect(t.takeException(), isNull);
        expect(f.log, [
          f.getRequest('folder/list'),
          f.getRequest(folder ? 'folder/list' : 'item/details', {
            'id': folder ? 'z9' : 'a2',
          }),
        ]);
      }),
    );
  }
  testWidgets(
    'binding reads live replaced widget callback',
    (t) => premiumizeCase(t, (f) async {
      var oldCalls = 0, newCalls = 0;
      final h = Completer<http.Response>();
      f.held['item/details|a2'] = h;
      await f.mount(
        t,
        picker: true,
        selected: (_) async {
          oldCalls++;
        },
      );
      final action =
          f.member('selectBoundSource')(premiumizeItem('a2')) as Future<void>;
      await f.until(t, () => f.requests.length == 2);
      final originalState = f.key.currentState;
      // Rebuild the same keyed State while preserving the Navigator and dialog.
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: f.navigatorKey,
          navigatorObservers: [f.observer],
          theme: ThemeData.dark(),
          home: f.screen(
            picker: true,
            selected: (_) async {
              newCalls++;
            },
          ),
        ),
      );
      expect(f.key.currentState, same(originalState));
      h.complete(f.json({'status': 'success', ...premiumizeFile('a2')}));
      await action;
      await f.transitions(t);
      expect(oldCalls, 0);
      expect(newCalls, 1);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('item/details', {'id': 'a2'}),
      ]);
    }),
  );
  testWidgets(
    'checking Back hazard pops screen on later root dismissal',
    (t) => premiumizeCase(t, (f) async {
      final h = Completer<http.Response>();
      f.held['item/details|a2'] = h;
      var called = 0;
      final callback = Completer<void>();
      await f.mount(
        t,
        pushed: true,
        picker: true,
        selected: (_) async {
          called++;
          await callback.future;
        },
      );
      await f.transitions(t);
      final action =
          f.member('selectBoundSource')(premiumizeItem('a2')) as Future<void>;
      await f.until(t, () => f.requests.length == 2);
      await f.transitions(t);
      await f.navigatorKey.currentState!.maybePop();
      await f.transitions(t);
      expect(f.observer.popped.whereType<PopupRoute>().length, 1);
      expect(f.key.currentState, isNotNull);
      h.complete(f.json({'status': 'success', ...premiumizeFile('a2')}));
      await f.until(t, () => called == 1);
      await f.transitions(t);
      await t.pumpAndSettle();
      expect(f.key.currentState, isNull);
      callback.complete();
      await action;
      expect(called, 1);
      expect(f.observer.popped.whereType<PageRoute>().length, 1);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('item/details', {'id': 'a2'}),
      ]);
    }),
  );
  testWidgets(
    'picker real rows disabled archive and Browse folder',
    (t) => premiumizeCase(t, (f) async {
      f.rows = [
        premiumizeFile('z9', folder: true),
        premiumizeFile('a2'),
        premiumizeFile('archive', video: false),
      ];
      await f.mount(t, picker: true);
      expect(find.text('Select Premiumize Source'), findsOneWidget);
      expect(find.byTooltip('Select items'), findsNothing);
      expect(find.byTooltip('Add to Premiumize'), findsNothing);
      expect(find.text('Transfers'), findsNothing);
      final archive = t.widget<CloudFileRow>(
        find.widgetWithText(CloudFileRow, 'Archive archive.zip'),
      );
      expect(archive.onTap, isNull);
      final folder = t.widget<CloudFileRow>(
        find.widgetWithText(CloudFileRow, 'Folder z9'),
      );
      expect(folder.actions.single.label, 'Browse folder');
      folder.actions.single.onSelected();
      await f.until(t, () => f.member('isLoading') == false);
      expect(f.member('currentFolderId'), 'z9');
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/list', {'id': 'z9'}),
      ]);
    }),
  );
  testWidgets(
    'search result row binds through same original card',
    (t) => premiumizeCase(t, (f) async {
      var called = 0;
      f.searches['Alpha'] = [premiumizeFile('hit', name: 'Alpha.mkv')];
      await f.mount(
        t,
        pushed: true,
        picker: true,
        selected: (_) async {
          called++;
        },
      );
      await f.transitions(t);
      await t.tap(find.byTooltip('Search files'));
      await t.pump();
      await t.enterText(find.byType(TextField), 'Alpha');
      await t.pump(const Duration(milliseconds: 350));
      await f.until(t, () => f.member('isSearching') == false);
      final row = t.widget<CloudFileRow>(
        find.widgetWithText(CloudFileRow, 'Alpha.mkv'),
      );
      expect(row.focusNode, isNull);
      row.onTap!();
      await f.until(t, () => called == 1);
      await f.transitions(t);
      expect(f.observer.popped.whereType<PageRoute>().length, 1);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/search', {'q': 'Alpha'}),
        f.getRequest('item/details', {'id': 'hit'}),
      ]);
    }),
  );
  testWidgets(
    'folder disposal before readiness avoids item details request',
    (t) => premiumizeCase(t, (f) async {
      var called = 0;
      final h = Completer<http.Response>();
      f.held['folder/list|z9'] = h;
      await f.mount(
        t,
        pushed: true,
        picker: true,
        selected: (_) async {
          called++;
        },
      );
      await f.transitions(t);
      final action =
          f.member('selectBoundSource')(premiumizeItem('z9', folder: true))
              as Future<void>;
      await f.until(t, () => f.requests.length == 2);
      await f.close(t);
      h.complete(f.json(f.page([premiumizeFile('unready', url: false)])));
      await action;
      expect(called, 0);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/list', {'id': 'z9'}),
      ], reason: 'disposed folder must not begin readiness resolution');
      expect(f.observer.popped, isEmpty);
      expect(t.takeException(), isNull);
    }),
  );
}
