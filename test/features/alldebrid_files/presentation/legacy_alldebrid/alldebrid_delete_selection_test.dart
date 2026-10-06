import 'package:flutter_test/flutter_test.dart';
import '../../../../support/alldebrid_files_fixture.dart';

AdRequest deleteMagnet(String id) =>
    adRequest('/v4/magnet/delete', body: 'id=$id');
AdRequest deleteLink(String id) => adRequest(
  '/v4/user/links/delete',
  body: Uri(queryParameters: {'links[]': 'https://locked.test/$id'}).query,
);
void main() {
  testWidgets(
    'single magnet confirmation Cancel makes no deletion request',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      await f.action(t, 'Library z9', 'Delete');
      expect(find.text('Delete magnet?'), findsOneWidget);
      expect(
        find.text('Remove "Library z9" from your AllDebrid account?'),
        findsOneWidget,
      );
      await f.tap(t, find.text('Cancel'));
      expect(f.ids, ['z9', 'a2', 'm5']);
      expect(f.log, [adList()]);
    }),
  );
  for (final mode in ['single', 'selected', 'all', 'swallowed_failure']) {
    testWidgets(
      'magnet deletion reload and success snack use list order mode=$mode',
      (t) => allDebridCase(t, (f) async {
        await f.mount(t);
        if (mode == 'swallowed_failure') {
          f.failures.add('/v4/magnet/delete');
        }
        if (mode == 'selected') {
          await f.tap(t, find.byTooltip('Select items'));
          await f.tap(t, find.text('Library m5'));
          await f.tap(t, find.text('Library a2'));
          expect(f.member('selectedIds'), {'m5', 'a2'});
          await f.tap(t, find.text('Delete'));
          expect(find.text('Delete 2 magnets?'), findsOneWidget);
        } else if (mode == 'all') {
          await f.tap(t, find.byTooltip('Delete all magnets'));
          expect(find.text('Delete all magnets?'), findsOneWidget);
        } else {
          await f.action(t, 'Library z9', 'Delete');
        }
        await f.tap(t, find.text('Delete').last);
        final ids = mode == 'selected'
            ? ['a2', 'm5']
            : mode == 'all'
            ? ['z9', 'a2', 'm5']
            : ['z9'];
        await f.until(
          t,
          () =>
              f.requests.length == ids.length + 2 &&
              f.member('loading') == false,
        );
        expect(f.log, [
          adList(),
          for (final id in ids) deleteMagnet(id),
          adList(),
        ]);
        expect(f.member('selectionMode'), isFalse);
        expect(f.member('selectedIds'), isEmpty);
        expect(
          f.ids,
          mode == 'swallowed_failure'
              ? ['z9', 'a2', 'm5']
              : mode == 'selected'
              ? ['z9']
              : mode == 'all'
              ? <String>[]
              : ['a2', 'm5'],
        );
        expect(
          find.text(
            ids.length == 1
                ? 'Magnet deleted'
                : '${ids.length} magnets deleted',
          ),
          findsOneWidget,
        );
      }),
    );
  }
  for (final mode in ['cancel', 'single', 'all', 'partial']) {
    testWidgets(
      'saved link deletion counts failures then reloads in list order mode=$mode',
      (t) => allDebridCase(t, (f) async {
        await f.mount(t);
        await f.web(t);
        if (mode == 'partial') {
          f.failures.add('/v4/user/links/delete|https://locked.test/b3');
        }
        if (mode == 'all' || mode == 'partial') {
          await f.tap(t, find.byTooltip('Delete all links'));
          expect(find.text('Delete all links?'), findsOneWidget);
        } else {
          await f.action(t, 'Saved w8.mkv', 'Delete');
          expect(find.text('Delete link?'), findsOneWidget);
        }
        await f.tap(t, find.text(mode == 'cancel' ? 'Cancel' : 'Delete').last);
        if (mode == 'cancel') {
          expect(f.log, [adList(), adLinks()]);
          expect(f.member('links') as List, hasLength(3));
          return;
        }
        final ids = mode == 'single' ? ['w8'] : ['w8', 'b3', 'n6'];
        await f.until(
          t,
          () =>
              f.requests.length == ids.length + 3 &&
              f.member('loadingLinks') == false,
        );
        expect(f.log, [
          adList(),
          adLinks(),
          for (final id in ids) deleteLink(id),
          adLinks(),
        ]);
        expect(
          (f.member('links') as List).map((dynamic l) => l.link),
          mode == 'single'
              ? ['https://locked.test/b3', 'https://locked.test/n6']
              : mode == 'partial'
              ? ['https://locked.test/b3']
              : <String>[],
        );
        expect(
          find.text(
            mode == 'partial'
                ? 'Failed to delete 1 link'
                : mode == 'single'
                ? 'Link deleted'
                : '3 links deleted',
          ),
          findsOneWidget,
        );
      }),
    );
  }
  testWidgets(
    'filtered Select All and Deselect All preserve hidden selections and visible all flag',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      await f.tap(t, find.byTooltip('Select items'));
      await f.tap(t, find.text('Library z9'));
      await f.search(t, 'a2');
      expect(f.member('isAllSelected'), isFalse);
      await f.tap(t, find.text('Select All'));
      expect(f.member('selectedIds'), {'z9', 'a2'});
      expect(f.member('isAllSelected'), isTrue);
      expect(find.text('Deselect All'), findsOneWidget);
      await f.tap(t, find.text('Deselect All'));
      expect(f.member('selectedIds'), {'z9'});
      expect(f.member('isAllSelected'), isFalse);
      await f.search(t, 'none');
      expect(f.member('isAllSelected'), isFalse);
      await f.tap(t, find.text('Select All'));
      expect(f.member('selectedIds'), {'z9'});
      expect(f.log, [adList()]);
    }),
  );
  testWidgets(
    'reload prunes stale selected ids but retains surviving selection and mode',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t);
      await f.tap(t, find.byTooltip('Select items'));
      await f.tap(t, find.text('Library m5'));
      await f.tap(t, find.text('Library z9'));
      f.magnets.removeWhere((m) => m['id'] == 'm5');
      await f.tap(t, find.byTooltip('Refresh'));
      await f.until(t, () => f.member('loading') == false);
      expect(f.ids, ['z9', 'a2']);
      expect(f.member('selectedIds'), {'z9'});
      expect(f.member('selectionMode'), isTrue);
      expect(find.text('1 selected'), findsOneWidget);
      expect(f.log, [adList(), adList()]);
    }),
  );
}
