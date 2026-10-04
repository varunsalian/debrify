import 'package:debrify/screens/settings/iptv_hidden_categories_page.dart';
import 'package:debrify/screens/settings/iptv_category_order_page.dart';
import 'package:debrify/screens/settings/iptv_channel_order_page.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/iptv_settings_fixture.dart';

void main() {
  testWidgets(
    'hidden badges recount after the real hidden categories route pops',
    (t) async {
      await iptvSettingsCase(t, (f) async {
        await f.mount(t, size: const Size(800, 1000));
        final target = f.playlists.single;
        final key = IptvCatalogKey.forPlaylist(target, 'live')!;
        await t.runAsync(() async {
          await IptvCatalogDb.ingestM3uLines(
            dbPath: IptvCatalogDb.path,
            catalogKey: key,
            lines: Stream.fromIterable(iptvFixtureM3u.split('\n')),
          );
          IptvCatalogDb.setGroupHidden(key, 'News', true);
        });
        await f.action(t, () => f.member('loadSettings')() as Future<void>);
        expect(f.member('hiddenCounts'), {target.id: 1});
        expect(find.text('1 category hidden'), findsOneWidget);
        f.member('enterPhoneSection')('hidden');
        await t.pump();
        expect(find.text('1 category hidden'), findsOneWidget);
        await f.tap(t, find.text(target.name));
        await f.until(
          t,
          () => find.byType(IptvHiddenCategoriesPage).evaluate().isNotEmpty,
        );
        await f.until(t, () => find.byType(Switch).evaluate().isNotEmpty);
        await f.frames(t);
        expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
        await f.tap(t, find.byType(Switch));
        await f.until(t, () => IptvCatalogDb.hiddenGroups(key).isEmpty);
        expect(f.member('hiddenCounts'), {target.id: 1});
        f.navigatorKey.currentState!.pop();
        await f.until(t, () => (f.member('hiddenCounts') as Map).isEmpty);
        await f.frames(t);
        expect(find.byType(IptvHiddenCategoriesPage), findsNothing);
        expect(find.text('Nothing hidden'), findsOneWidget);
        expect(find.text('1 category hidden'), findsNothing);
      }, sources: [iptvFixtureSource('z9')]);
    },
  );

  testWidgets(
    'category order stale scope refuses the actual route with its message',
    (t) async {
      await iptvSettingsCase(t, (f) async {
        await f.mount(t, size: const Size(800, 1000));
        f.member('enterPhoneSection')('categoryOrder');
        await t.pump();
        await t.runAsync(() async {
          await t.tap(find.text('Source z9'));
          final old = ProfileRuntime.capture();
          ProfileRuntime.publish(
            ProfileScope(
              profileId: f.incomingId,
              dataGeneration: 1,
              sessionEpoch: old.sessionEpoch + 1,
            ),
          );
        });
        await f.until(
          t,
          () => find
              .text(
                'The active profile changed. Category order was not opened.',
              )
              .evaluate()
              .isNotEmpty,
        );
        expect(find.byType(IptvCategoryOrderPage), findsNothing);
        expect(f.navigatorKey.currentState!.canPop(), isFalse);
        expect(await t.runAsync(() => f.stored(f.ownerId)), hasLength(1));
        expect(await t.runAsync(() => f.stored(f.incomingId)), isEmpty);
      }, sources: [iptvFixtureSource('z9')]);
    },
  );

  testWidgets('channel order hub entry pushes the real route and returns', (
    t,
  ) async {
    await iptvSettingsCase(t, (f) async {
      await f.mount(t, size: const Size(800, 1000));
      await f.tap(t, find.text('Channel order'));
      await f.until(
        t,
        () => find.byType(IptvChannelOrderPage).evaluate().isNotEmpty,
      );
      await f.frames(t);
      expect(find.text('Favorites'), findsOneWidget);
      expect(f.navigatorKey.currentState!.canPop(), isTrue);
      f.navigatorKey.currentState!.pop();
      await f.frames(t);
      expect(find.byType(IptvChannelOrderPage), findsNothing);
      expect(f.member('phoneSection'), 'hub');
    });
  });

  testWidgets(
    'ensureFocusNodes disposes surplus nodes and keeps existing row slots',
    (t) async {
      await iptvSettingsCase(t, (f) async {
        await f.mount(t);
        for (final name in [
          'playlistFocusNodes',
          'listFocusNodes',
          'hiddenFocusNodes',
        ]) {
          final nodes = f.member(name) as List;
          final retained = List<FocusNode>.from(nodes);
          final surplus = [FocusNode(), FocusNode()];
          nodes.addAll(surplus);
          f.member('ensureFocusNodes')();
          expect(nodes, orderedEquals(retained));
          for (final node in surplus) {
            expect(() => node.addListener(() {}), throwsFlutterError);
          }
          for (final node in retained) {
            void listener() {}
            node.addListener(listener);
            node.removeListener(listener);
          }
        }
      }, sources: [iptvFixtureSource('z9')]);
    },
  );

  testWidgets(
    'TV last playlist removal then emptying list repairs to row and active tab',
    (t) async {
      await iptvSettingsCase(t, (f) async {
        PlatformUtil.debugSetAndroidTvCached(true);
        await f.mount(t, size: const Size(800, 1000), add: true);
        final nodes = List<FocusNode>.from(
          f.member('playlistFocusNodes') as List,
        );
        nodes.last.requestFocus();
        await t.pump();
        await f.action(
          t,
          () => f.member('removePlaylist')(f.playlists.last) as Future<void>,
        );
        t.binding.scheduleFrame();
        await t.pump();
        expect(FocusManager.instance.primaryFocus, same(nodes.first));
        expect(() => nodes.last.addListener(() {}), throwsFlutterError);
        await f.action(
          t,
          () => f.member('removePlaylist')(f.playlists.single) as Future<void>,
        );
        t.binding.scheduleFrame();
        await t.pump();
        expect(f.member('playlistFocusNodes'), isEmpty);
        expect(
          FocusManager.instance.primaryFocus,
          same(f.member('urlTabFocusNode')),
        );
      }, sources: [iptvFixtureSource('z9'), iptvFixtureSource('a2')]);
    },
  );

  for (final action in ['Rename', 'Delete']) {
    testWidgets(
      'list sheet $action dispatches the actual dialog and persistence',
      (t) async {
        await iptvSettingsCase(t, (f) async {
          PlatformUtil.debugSetAndroidTvCached(true);
          await t.runAsync(() async {
            await IptvFavoritesStorage.createIptvList('A');
            if (action == 'Delete') {
              await IptvFavoritesStorage.createIptvList('B');
            }
          });
          await f.mount(t, size: const Size(800, 1000));
          f.member('enterPhoneSection')('lists');
          await t.pump();
          final oldNode =
              (f.member('listFocusNodes') as List).first as FocusNode;
          late Future<void> work;
          await t.runAsync(() async {
            work = f.member('showListActions')(f.lists.last) as Future<void>;
            f.outstanding.add(work);
          });
          await f.frames(t);
          await f.tap(t, find.text(action));
          await f.until(t, () => find.byType(Dialog).evaluate().isNotEmpty);
          await f.frames(t);
          if (action == 'Rename') {
            await t.enterText(
              find.descendant(
                of: find.byType(Dialog),
                matching: find.byType(TextField),
              ),
              'Renamed through sheet',
            );
            await f.tap(t, find.text('Save'));
            await f.until(
              t,
              () => f.lists.single.name == 'Renamed through sheet',
            );
            expect((f.member('listFocusNodes') as List).first, same(oldNode));
          } else {
            final trailing =
                (f.member('listFocusNodes') as List).last as FocusNode;
            await f.tap(t, find.text('Delete').last);
            await f.until(t, () => f.lists.length == 1);
            t.binding.scheduleFrame();
            await t.pump();
            expect(f.lists.single.name, 'A');
            expect(FocusManager.instance.primaryFocus, same(oldNode));
            expect(() => trailing.addListener(() {}), throwsFlutterError);
            await t.runAsync(() => work);
            late Future<void> emptyWork;
            await t.runAsync(() async {
              emptyWork =
                  f.member('deleteList')(f.lists.single) as Future<void>;
              f.outstanding.add(emptyWork);
            });
            await f.frames(t);
            await f.tap(t, find.text('Delete').last);
            await f.until(t, () => f.lists.isEmpty);
            await t.runAsync(() => emptyWork);
            t.binding.scheduleFrame();
            await t.pump();
            expect(f.member('listFocusNodes'), isEmpty);
            expect(() => oldNode.addListener(() {}), throwsFlutterError);
            expect(
              FocusManager.instance.primaryFocus,
              same(f.member('createListFocusNode')),
            );
          }
          await t.runAsync(() => work);
          await t.runAsync(() async {
            final saved = (await IptvFavoritesStorage.getIptvLists()).where(
              (l) => !l.isBuiltin,
            );
            expect(
              saved.map((l) => l.name),
              action == 'Rename' ? ['Renamed through sheet'] : isEmpty,
            );
          });
        });
      },
    );
  }
}
