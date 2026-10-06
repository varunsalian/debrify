import 'package:debrify/widgets/file_selection_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/alldebrid_files_fixture.dart';

void main() {
  testWidgets(
    'root load re-reads credential while lazy links and link refresh retain cached key',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      await f.changeCredential(t, 'changed-key');
      await f.web(t);
      await f.tap(t, find.byTooltip('Refresh'));
      await f.until(
        t,
        () => f.requests.length == 3 && f.member('loadingLinks') == false,
      );
      expect(f.log, [adList(), adLinks(), adLinks()]);
      await f.torrents(t);
      await f.tap(t, find.byTooltip('Refresh'));
      await f.until(
        t,
        () => f.requests.length == 4 && f.member('loading') == false,
      );
      await f.web(t);
      await f.tap(t, find.byTooltip('Refresh'));
      await f.until(
        t,
        () => f.requests.length == 5 && f.member('loadingLinks') == false,
      );
      expect(f.log, [
        adList(),
        adLinks(),
        adLinks(),
        adList(key: 'changed-key'),
        adLinks(key: 'changed-key'),
      ]);
    }),
  );
  testWidgets(
    'remount reads replaced credential and constructs independent resources',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      final scroll = f.scroll, focus = f.focus('firstItemFocusNode');
      await f.changeCredential(t, 'changed-key');
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 1));
      await f.mount(t);
      expect(f.scroll, isNot(same(scroll)));
      expect(f.focus('firstItemFocusNode'), isNot(same(focus)));
      expect(f.member('apiKey'), 'changed-key');
      expect(f.log, [adList(), adList(key: 'changed-key')]);
    }),
  );
  for (final action in [
    'play_file',
    'play_magnet',
    'download_file',
    'download_magnet',
    'play_link',
    'download_link',
    'copy_link',
    'add_magnet',
    'add_link',
    'delete_magnet',
    'delete_link',
    'playlist',
  ]) {
    testWidgets(
      'cached credential remains on every action request after storage change action=$action',
      (t) => allDebridCase(t, (f) async {
        await f.mount(t);
        final web = [
          'play_link',
          'download_link',
          'copy_link',
          'add_link',
          'delete_link',
        ].contains(action);
        if (web) await f.web(t);
        if (['play_file', 'download_file'].contains(action)) await f.open(t);
        await f.changeCredential(t, 'changed-key');
        final expected = <AdRequest>[
          adList(),
          if (web) adLinks(),
          if (['play_file', 'download_file'].contains(action)) adFiles('z9'),
        ];
        switch (action) {
          case 'play_file':
            await f.tap(t, find.text('A.S02E01.mkv'));
            expected.add(adUnlock('https://locked.test/file-z9'));
          case 'download_file':
            await f.action(t, 'A.S02E01.mkv', 'Download');
            expected.add(adUnlock('https://locked.test/file-z9'));
          case 'play_magnet':
            await f.action(t, 'Library z9', 'Play');
            expected.addAll([
              adFiles('z9'),
              adUnlock('https://locked.test/file-a2'),
              adUnlock('https://locked.test/file-m5'),
              adUnlock('https://locked.test/file-z9'),
            ]);
          case 'download_magnet':
            await f.action(t, 'Library z9', 'Download to device');
            await f.until(
              t,
              () => find.byType(FileSelectionDialog).evaluate().isNotEmpty,
            );
            final callback = t
                .widget<FileSelectionDialog>(find.byType(FileSelectionDialog))
                .onDownload;
            f.navigatorKey.currentState!.pop();
            await t.pump();
            callback([
              {'_adIndex': 2},
            ]);
            await t.pump();
            expected.addAll([
              adFiles('z9'),
              adUnlock('https://locked.test/file-m5'),
            ]);
          case 'play_link':
            await f.tap(t, find.text('Saved w8.mkv'));
            expected.add(adUnlock('https://locked.test/w8'));
          case 'download_link':
            await f.action(t, 'Saved w8.mkv', 'Download to device');
            expected.add(adUnlock('https://locked.test/w8'));
          case 'copy_link':
            await f.action(t, 'Saved w8.mkv', 'Copy link');
            expected.add(adUnlock('https://locked.test/w8'));
          case 'add_magnet':
            f.failures.add('/v4/magnet/upload');
            await f.tap(t, find.byTooltip('Add magnet link'));
            await t.enterText(find.byType(TextField), ' magnet:?xt=fixture ');
            await f.tap(t, find.text('Add').last);
            expected.add(
              adRequest(
                '/v4/magnet/upload',
                body: Uri(
                  queryParameters: {'magnets[]': 'magnet:?xt=fixture'},
                ).query,
              ),
            );
          case 'add_link':
            f.failures.add('/v4/link/unlock');
            await f.tap(t, find.byTooltip('Add link'));
            await t.enterText(
              find.byType(TextField),
              ' https://input.test/original ',
            );
            await f.tap(t, find.text('Add').last);
            expected.add(adUnlock('https://input.test/original'));
          case 'delete_magnet':
            await f.action(t, 'Library z9', 'Delete');
            await f.tap(t, find.text('Delete').last);
            expected.addAll([
              adRequest('/v4/magnet/delete', body: 'id=z9'),
              adList(key: 'changed-key'),
            ]);
          case 'delete_link':
            await f.action(t, 'Saved w8.mkv', 'Delete');
            await f.tap(t, find.text('Delete').last);
            expected.addAll([
              adRequest(
                '/v4/user/links/delete',
                body: Uri(
                  queryParameters: {'links[]': 'https://locked.test/w8'},
                ).query,
              ),
              adLinks(),
            ]);
          case 'playlist':
            await f.action(t, 'Library z9', 'Add to Playlist');
            expected.add(adFiles('z9'));
        }
        await f.until(
          t,
          () =>
              f.requests.length == expected.length &&
              f.member('loadingDialogOpen') == false &&
              f.member('loading') == false &&
              f.member('loadingLinks') == false,
        );
        expect(f.log, expected);
      }),
    );
  }
}
