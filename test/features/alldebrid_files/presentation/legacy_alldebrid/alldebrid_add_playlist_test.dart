import 'dart:async';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/alldebrid_files_fixture.dart';

void main() {
  for (final mode in ['cancel', 'empty', 'success', 'failure']) {
    testWidgets(
      'add magnet real dialog exact trimmed upload snack before reload mode=$mode',
      (t) => allDebridCase(t, (f) async {
        await f.mount(t);
        await f.tap(t, find.byTooltip('Add magnet link'));
        await t.enterText(
          find.byType(TextField),
          mode == 'empty' ? '  ' : '  magnet:?xt=urn:btih:new&dn=Fixture  ',
        );
        if (mode == 'failure') {
          f.failures.add('/v4/magnet/upload');
        }
        final reload = Completer<http.Response>();
        if (mode == 'success') {
          f.held['/v4.1/magnet/status'] = reload;
        }
        await f.tap(t, find.text(mode == 'cancel' ? 'Cancel' : 'Add').last);
        if (mode == 'cancel' || mode == 'empty') {
          expect(f.log, [adList()]);
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.byType(SnackBar), findsNothing);
          return;
        }
        final upload = adRequest(
          '/v4/magnet/upload',
          body: Uri(
            queryParameters: {
              'magnets[]': 'magnet:?xt=urn:btih:new&dn=Fixture',
            },
          ).query,
        );
        await f.until(
          t,
          () =>
              f.requests.length == (mode == 'success' ? 3 : 2) &&
              f.member('loadingDialogOpen') == false,
        );
        expect(f.log, [adList(), upload, if (mode == 'success') adList()]);
        if (mode == 'success') {
          expect(find.text('Magnet added'), findsOneWidget);
          expect(f.member('loading'), isTrue);
          reload.complete(f.listResponse());
          await f.until(t, () => f.member('loading') == false);
        } else {
          expect(
            find.text('Failed to add magnet: Exception: fixture failure'),
            findsOneWidget,
          );
          expect(f.member('loading'), isFalse);
        }
      }),
    );
  }
  testWidgets(
    'add link clipboard auto-pastes trimmed http and https only',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      await f.web(t);
      for (final text in [
        '  http://input.test/a  ',
        '  https://input.test/b  ',
        'ftp://input.test/c',
        'not a url',
      ]) {
        f.clipboardText = text;
        await f.tap(t, find.byTooltip('Add link'));
        expect(
          t.widget<TextField>(find.byType(TextField)).controller!.text,
          text.trim().startsWith('http') ? text.trim() : '',
        );
        await f.tap(t, find.text('Cancel'));
      }
      expect(f.log, [adList(), adLinks()]);
    }),
  );
  for (final mode in [
    'cancel',
    'empty',
    'invalid',
    'success',
    'unlock_failure',
    'save_failure',
  ]) {
    testWidgets(
      'add link validates input and saves original URL with exact request order mode=$mode',
      (t) => allDebridCase(t, (f) async {
        await f.mount(t);
        await f.web(t);
        await f.tap(t, find.byTooltip('Add link'));
        const input = 'https://input.test/original.mkv';
        await t.enterText(
          find.byType(TextField),
          mode == 'empty'
              ? ' '
              : mode == 'invalid'
              ? 'ftp://input.test/wrong'
              : ' $input ',
        );
        f.defaultUnlockUrl = 'https://unlocked.test/different.mkv';
        if (mode == 'unlock_failure') {
          f.failures.add('/v4/link/unlock');
        }
        if (mode == 'save_failure') {
          f.failures.add('/v4/user/links/save');
        }
        final reload = Completer<http.Response>();
        if (mode == 'success') {
          f.held['/v4/user/links'] = reload;
        }
        await f.tap(t, find.text(mode == 'cancel' ? 'Cancel' : 'Add').last);
        if (['cancel', 'empty', 'invalid'].contains(mode)) {
          expect(f.log, [adList(), adLinks()]);
          if (mode == 'invalid') {
            expect(
              find.text(
                'Enter a valid URL (must start with http:// or https://)',
              ),
              findsOneWidget,
            );
          }
          expect(find.byType(AlertDialog), findsNothing);
          if (mode != 'invalid') expect(find.byType(SnackBar), findsNothing);
          return;
        }
        final expected = [
          adList(),
          adLinks(),
          adUnlock(input),
          if (mode != 'unlock_failure')
            adRequest(
              '/v4/user/links/save',
              body: Uri(queryParameters: {'links[]': input}).query,
            ),
          if (mode == 'success') adLinks(),
        ];
        await f.until(
          t,
          () =>
              f.requests.length == expected.length &&
              f.member('loadingDialogOpen') == false,
        );
        expect(f.log, expected);
        if (mode == 'success') {
          expect(find.text('Link added'), findsOneWidget);
          expect(f.member('loadingLinks'), isTrue);
          reload.complete(f.linksResponse());
          await f.until(t, () => f.member('loadingLinks') == false);
        } else {
          expect(
            find.text('Failed to add link: Exception: fixture failure'),
            findsOneWidget,
          );
          expect(f.member('loadingLinks'), isFalse);
        }
      }),
    );
  }
  for (final single in [false, true]) {
    testWidgets(
      'playlist real menu persists exact map and reports duplicate single=$single',
      (t) => allDebridCase(t, (f) async {
        f.magnets = [adMagnet('z9', name: 'Show.2026.1080p.WEB-DL')];
        if (single) {
          f.files = [adFile('single', size: 0)];
        }
        await f.mount(t);
        final before = DateTime.now().millisecondsSinceEpoch;
        await f.action(t, 'Show.2026.1080p.WEB-DL', 'Add to Playlist');
        List<Map<String, dynamic>> items = [];
        await f.until(
          t,
          () => find.text('Added to playlist').evaluate().isNotEmpty,
        );
        items = await t.runAsync(PlaylistStorage.getPlaylistItemsRaw) ?? [];
        expect(items, hasLength(1));
        final item = items.single;
        expect(
          item['addedAt'],
          inInclusiveRange(before, DateTime.now().millisecondsSinceEpoch),
        );
        expect({...item}..remove('addedAt'), {
          'provider': 'alldebrid',
          'title': FileUtils.cleanPlaylistTitle('Show.2026.1080p.WEB-DL'),
          'kind': single ? 'single' : 'collection',
          'torrent_hash': 'hash-z9',
          if (single) 'allDebridLink': 'https://locked.test/file-single',
          if (single) 'sizeBytes': 0,
          if (!single) 'count': 3,
        });
        await t.pump(const Duration(seconds: 4));
        await f.action(t, 'Show.2026.1080p.WEB-DL', 'Add to Playlist');
        await f.until(
          t,
          () => find.text('Already in playlist').evaluate().isNotEmpty,
        );
        expect(await t.runAsync(PlaylistStorage.getPlaylistItemsRaw), items);
        expect(f.log, [adList(), adFiles('z9'), adFiles('z9')]);
      }),
    );
  }
  testWidgets(
    'playlist empty-hash rejection makes no file request or persisted entry',
    (t) => allDebridCase(t, (f) async {
      f.magnets = [adMagnet('z9', hash: '')];
      await f.mount(t);
      await f.action(t, 'Library z9', 'Add to Playlist');
      expect(find.text('This magnet has no infohash to save.'), findsOneWidget);
      expect(await t.runAsync(PlaylistStorage.getPlaylistItemsRaw), isEmpty);
      expect(f.log, [adList()]);
    }),
  );
}
