import 'dart:async';
import 'dart:io';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../support/iptv_settings_fixture.dart';
import '../../../../support/iptv_settings_removal_probe.dart';
import '../../../../support/iptv_settings_held_boundaries.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

Future<void> seedCatalog(IptvSettingsFixture f, IptvPlaylist playlist) async {
  final key = IptvCatalogKey.forPlaylist(playlist, 'live')!;
  final result = await IptvCatalogDb.ingestM3uLines(
    dbPath: IptvCatalogDb.path,
    catalogKey: key,
    lines: Stream.fromIterable(iptvFixtureM3u.split('\n')),
    numberingSourceKey: playlist.id,
  );
  expect(result.hasError, isFalse);
  expect(IptvCatalogDb.snapshot(key), isNotNull);
  expect(IptvCatalogDb.setGroupHidden(key, 'News', true), isTrue);
}

void main() {
  for (final local in [false, true]) {
    testWidgets(
      'ordinary ${local ? 'local-file' : 'URL'} removal is immediate and cleans persisted catalog and media data',
      (tester) async {
        await iptvSettingsCase(tester, (f) async {
          await f.mount(tester);
          final target = f.playlists.first;
          late String listId;
          await tester.runAsync(() async {
            await IptvPlaylistStorage.setIptvDefaultPlaylist(target.id);
            listId = await IptvFavoritesStorage.createIptvList(
              'Surviving list',
            );
            await IptvFavoritesStorage.setIptvChannelInList(
              listId,
              'https://fixture.invalid/watch.ts',
              true,
              playlistId: target.id,
              channelName: 'News',
            );
            await IptvHistoryStorage.recordIptvWatch(
              'https://fixture.invalid/watch.ts',
              playlistId: target.id,
              channelName: 'News',
            );
            if (!local) {
              await seedCatalog(f, target);
            }
            if (local) {
              await IptvCatalogDb.setCategoryOrder(
                IptvCatalogKey.forLocalCategoryOrder(target.id),
                ['News', 'Sports'],
              );
            }
          });
          await f.action(
            tester,
            () => f.member('loadSettings')() as Future<void>,
          );
          await tester.runAsync(() => seedRemovalProbe(f));
          final numberingBefore = (await tester.runAsync(
            () => removalProbeState(target.id),
          ))!;
          final beforeLists = f.member('playlists');
          final twoPane =
              tester.widget(
                    find.byWidgetPredicate(
                      (w) => w.runtimeType.toString() == 'IptvSettingsTwoPane',
                    ),
                  )
                  as dynamic;
          await tester.runAsync(() async {
            twoPane.onDelete(target);
          });
          await f.until(tester, () => f.playlists.isEmpty);
          await f.frames(tester);
          expect(find.byType(Dialog), findsNothing);
          expect(find.byType(AlertDialog), findsNothing);
          expect(f.member('playlists'), isNot(same(beforeLists)));
          expect(f.member('defaultPlaylistId'), isNull);
          expect(find.text('Removed "${target.name}"'), findsOneWidget);
          await tester.runAsync(() async {
            expect(await IptvPlaylistStorage.getIptvPlaylists(), isEmpty);
            expect(await IptvPlaylistStorage.getIptvDefaultPlaylist(), isNull);
            expect(
              await IptvFavoritesStorage.getIptvListChannels(listId),
              isEmpty,
            );
            expect(
              (await IptvFavoritesStorage.getIptvLists()).any(
                (l) => l.id == listId,
              ),
              isTrue,
            );
            expect(await IptvHistoryStorage.getIptvWatchHistory(), isEmpty);
            final after = await removalProbeState(target.id);
            assertArchivedNumbering(numberingBefore, after);
            expect(after['categoryOrders'], 0);
            if (!local) {
              final key = IptvCatalogKey.forPlaylist(target, 'live')!;
              expect(IptvCatalogDb.snapshot(key), isNull);
              expect(IptvCatalogDb.hiddenGroups(key), isEmpty);
            }
            if (local) {
              expect(
                IptvCatalogDb.savedCategoryOrder(
                  IptvCatalogKey.forLocalCategoryOrder(target.id),
                ),
                isEmpty,
              );
            }
          });
        }, sources: [iptvFixtureSource('z9', local: local)]);
      },
    );
  }

  testWidgets(
    'mid-removal failure preserves the earlier whole-list write and reports catch-all',
    (tester) async {
      await iptvSettingsCase(tester, (f) async {
        await f.mount(tester);
        final target = f.playlists.first;
        await f.action(
          tester,
          () => f.member('setDefaultPlaylist')(target) as Future<void>,
        );
        final path = IptvCatalogDb.path;
        await tester.runAsync(() async {
          await IptvCatalogDb.closeScope();
          await File(path).rename('$path.saved');
          await Directory(path).create();
        });
        try {
          await f.action(
            tester,
            () => f.member('removePlaylist')(target) as Future<void>,
          );
          await tester.runAsync(() async {
            expect(await IptvPlaylistStorage.getIptvPlaylists(), isEmpty);
            expect(
              await IptvPlaylistStorage.getIptvDefaultPlaylist(),
              target.id,
            );
          });
          expect(f.playlists.single.id, target.id);
          expect(f.member('defaultPlaylistId'), target.id);
          await tester.pump(const Duration(seconds: 4));
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            find.text('Could not remove "${target.name}". Please try again.'),
            findsOneWidget,
          );
        } finally {
          await tester.runAsync(() async {
            await Directory(path).delete();
            await File('$path.saved').rename(path);
          });
        }
      }, sources: [iptvFixtureSource('z9')]);
    },
  );

  for (final boundary in [
    'default',
    'catalog',
    'local-category',
    'media-category',
    'favorites',
    'history',
  ]) {
    testWidgets(
      'removal failure at $boundary preserves exactly the preceding effects',
      (t) async {
        final local = boundary == 'local-category';
        await iptvSettingsCase(t, (f) async {
          await f.mount(t);
          final target = f.playlists.single;
          await f.action(
            t,
            () => f.member('setDefaultPlaylist')(target) as Future<void>,
          );
          await t.runAsync(() async {
            await seedRemovalProbe(f);
            if (!local) {
              IptvCatalogDb.setGroupHidden(
                IptvCatalogKey.forPlaylist(target, 'live')!,
                'News',
                true,
              );
            }
            final list = await IptvFavoritesStorage.createIptvList('Survivor');
            await IptvFavoritesStorage.setIptvChannelInList(
              list,
              'https://fixture.invalid/live.ts',
              true,
              playlistId: target.id,
              channelName: 'Café',
            );
            await IptvHistoryStorage.recordIptvWatch(
              'https://fixture.invalid/live.ts',
              playlistId: target.id,
              channelName: 'Café',
            );
            if (local) {
              await IptvCatalogDb.setCategoryOrder(
                IptvCatalogKey.forLocalCategoryOrder(target.id),
                ['News'],
              );
            }
          });
          final before = (await t.runAsync(
            () => removalProbeState(target.id),
          ))!;
          IptvHeldPreferences? failedAdapter;
          if (boundary == 'default') {
            final prefs = (await t.runAsync(SharedPreferences.getInstance))!;
            final adapter = IptvHeldPreferences({
              for (final key in prefs.getKeys())
                'flutter.$key': prefs.get(key)!,
            });
            failedAdapter = adapter;
            adapter.failRemoveKey =
                'flutter.p.${f.ownerId}.g.1.iptv_default_playlist';
            SharedPreferencesStorePlatform.instance = adapter;
          } else {
            await t.runAsync(() => installRemovalFailure(boundary));
          }
          await f.action(
            t,
            () => f.member('removePlaylist')(target) as Future<void>,
          );
          await t.runAsync(() async {
            expect(await IptvPlaylistStorage.getIptvPlaylists(), isEmpty);
            expect(await IptvPlaylistStorage.getIptvDefaultPlaylist(), isNull);
            if (failedAdapter != null) {
              expect(
                (await failedAdapter
                    .getAll())['flutter.p.${f.ownerId}.g.1.iptv_default_playlist'],
                target.id,
              );
            }
            final after = await removalProbeState(target.id);
            assertArchivedNumbering(before, after);
            expect(
              after['categoryOrders'],
              ['default', 'catalog', 'media-category'].contains(boundary)
                  ? before['categoryOrders']
                  : 0,
            );
            expect(
              after['memberships'],
              [
                    'default',
                    'catalog',
                    'media-category',
                    'favorites',
                  ].contains(boundary)
                  ? before['memberships']
                  : 0,
            );
            expect(after['history'], local ? 0 : before['history']);
            expect(
              (await IptvFavoritesStorage.getIptvLists()).any(
                (l) => l.name == 'Survivor',
              ),
              isTrue,
            );
            if (!local) {
              final key = IptvCatalogKey.forPlaylist(target, 'live')!;
              expect(
                IptvCatalogDb.snapshot(key),
                ['default', 'catalog'].contains(boundary) ? isNotNull : isNull,
              );
              expect(
                IptvCatalogDb.hiddenGroups(key),
                ['default', 'catalog'].contains(boundary)
                    ? isNotEmpty
                    : isEmpty,
              );
            } else {
              expect(
                IptvCatalogDb.savedCategoryOrder(
                  IptvCatalogKey.forLocalCategoryOrder(target.id),
                ),
                ['News'],
              );
            }
          });
          expect(f.playlists, local ? isEmpty : hasLength(1));
          expect(
            f.member('defaultPlaylistId'),
            boundary == 'default' ? target.id : isNull,
          );
          await t.pump(const Duration(seconds: 4));
          await t.pump(const Duration(milliseconds: 300));
          expect(
            find.text(
              local
                  ? 'Removed "${target.name}"'
                  : 'Could not remove "${target.name}". Please try again.',
            ),
            findsOneWidget,
          );
        }, sources: [iptvFixtureSource('z9', local: local)]);
      },
    );
  }

  for (final change in ['url', 'username', 'password']) {
    testWidgets(
      'edit $change preserves immutable fields and invalidates only unreachable hidden keys',
      (tester) async {
        final xc = change != 'url';
        await iptvSettingsCase(tester, (f) async {
          await f.mount(tester);
          final target = f.playlists.first;
          final keys = (f.member('catalogKeysFor')(target) as List)
              .cast<String>();
          await tester.runAsync(() async {
            for (final key in keys) {
              await IptvCatalogDb.ingestM3uLines(
                dbPath: IptvCatalogDb.path,
                catalogKey: key,
                lines: Stream.fromIterable(iptvFixtureM3u.split('\n')),
              );
              IptvCatalogDb.setGroupHidden(key, 'News', true);
            }
          });
          late Future<void> work;
          await tester.runAsync(() async {
            work = f.member('editPlaylist')(target) as Future<void>;
            f.outstanding.add(work);
          });
          await f.until(
            tester,
            () => find.byType(Dialog).evaluate().isNotEmpty,
          );
          await f.frames(tester);
          final label = change == 'url'
              ? 'Playlist URL'
              : change == 'username'
              ? 'Username'
              : 'Password';
          final value = change == 'url'
              ? 'https://fixture.invalid/changed.m3u'
              : change == 'username'
              ? 'new-user'
              : 'new-pass';
          await tester.enterText(
            find.widgetWithText(TvTextField, label),
            value,
          );
          await tester.enterText(
            find.widgetWithText(TvTextField, 'Playlist Name'),
            'Renamed',
          );
          await f.tap(tester, find.text('Save'));
          await f.until(tester, () => f.playlists.first.name == 'Renamed');
          await tester.runAsync(() => work);
          final updated = f.playlists.first;
          expect(updated.id, target.id);
          expect(updated.addedAt, target.addedAt);
          expect(updated.connectionResourceId, target.connectionResourceId);
          expect(updated.connectionReadOnly, target.connectionReadOnly);
          expect(updated.credentialsRedacted, isFalse);
          expect(updated.epgUrl, target.epgUrl);
          expect(updated.content, target.content);
          expect(
            change == 'url'
                ? updated.url
                : change == 'username'
                ? updated.username
                : updated.password,
            value,
          );
          for (final key in keys) {
            expect(IptvCatalogDb.snapshot(key), isNull);
            expect(
              IptvCatalogDb.hiddenGroups(key),
              change == 'password' ? {'News'} : isEmpty,
            );
          }
          await tester.runAsync(() async {
            expect(
              (await IptvPlaylistStorage.getIptvPlaylists()).single.toJson(),
              updated.toJson(),
            );
          });
          expect(find.text('Updated "Renamed"'), findsOneWidget);
        }, sources: [iptvFixtureSource('z9', xtream: xc)]);
      },
    );
  }

  for (final xtream in [false, true]) {
    for (final failed in [false, true]) {
      testWidgets(
        'manual ${xtream ? 'Xtream' : 'M3U'} refresh is sequential and retains busy-set identity failure=$failed',
        (tester) async {
          await iptvSettingsCase(tester, (f) async {
            await f.mount(tester);
            final target = f.playlists.first;
            final busy = f.member('refreshingIds');
            final pane =
                tester.widget(
                      find.byWidgetPredicate(
                        (w) =>
                            w.runtimeType.toString() == 'IptvSettingsTwoPane',
                      ),
                    )
                    as dynamic;
            expect(identical(busy, pane.refreshingIds), isTrue);
            f.holdAction = xtream ? 'get_live_streams' : 'm3u';
            f.heldHttp = Completer<http.Response>();
            f.failAction = failed && xtream
                ? 'get_vod_streams'
                : failed
                ? 'm3u'
                : null;
            late Future<void> work;
            await tester.runAsync(() async {
              work = f.member('refreshPlaylist')(target) as Future<void>;
              f.outstanding.add(work);
            });
            await f.until(
              tester,
              () => f.requests.any(
                (r) =>
                    (r.url.queryParameters['action'] ?? 'm3u') == f.holdAction,
              ),
            );
            expect(f.member('refreshingIds'), same(busy));
            expect((busy as Set).contains(target.id), isTrue);
            final active =
                tester.widget(
                      find.byWidgetPredicate(
                        (w) =>
                            w.runtimeType.toString() == 'IptvSettingsTwoPane',
                      ),
                    )
                    as dynamic;
            expect(active.refreshingIds, same(busy));
            expect(
              f.requests.where(
                (r) => r.url.queryParameters['action'] == 'get_vod_streams',
              ),
              isEmpty,
            );
            f.holdAction = null;
            f.heldHttp!.complete(
              http.Response(
                xtream
                    ? '[{"stream_id":9,"name":"Channel","category_id":"7"}]'
                    : failed
                    ? 'denied'
                    : iptvFixtureM3u,
                failed && !xtream ? 403 : 200,
              ),
            );
            var done = false;
            work.whenComplete(() => done = true);
            await f.until(tester, () => done);
            await tester.runAsync(() => work);
            await f.frames(tester);
            expect(f.member('refreshingIds'), same(busy));
            expect(busy, isEmpty);
            await tester.pump(const Duration(seconds: 4));
            await tester.pump(const Duration(milliseconds: 300));
            final actions = f.requests
                .map(
                  (r) =>
                      r.url.queryParameters['action'] ??
                      (r.url.path.endsWith('.m3u') ? 'm3u' : 'live-probe'),
                )
                .toList();
            if (xtream) {
              expect(actions, [
                'get_live_streams',
                'get_live_categories',
                'live-probe',
                'get_vod_streams',
                if (!failed) 'get_vod_categories',
                'get_series',
                'get_series_categories',
              ]);
              expect(
                actions.where((a) => !a.endsWith('_categories')).toList(),
                [
                  'get_live_streams',
                  'live-probe',
                  'get_vod_streams',
                  'get_series',
                ],
              );
              expect(
                f.requests
                    .singleWhere((r) => r.url.path.contains('/live/'))
                    .url
                    .toString(),
                'https://fixture.invalid/panel/live/user/pass/9.ts',
              );
              expect(
                actions.where((a) => a.endsWith('_categories')).toList(),
                failed
                    ? ['get_live_categories', 'get_series_categories']
                    : [
                        'get_live_categories',
                        'get_vod_categories',
                        'get_series_categories',
                      ],
              );
              expect(
                actions.indexOf('get_vod_streams'),
                greaterThan(actions.indexOf('get_live_streams')),
              );
              expect(
                actions.indexOf('get_series'),
                greaterThan(actions.indexOf('get_vod_streams')),
              );
              expect(
                find.textContaining(
                  failed ? 'Failed to refresh movies' : 'Updated',
                ),
                findsOneWidget,
              );
            } else {
              expect(actions, ['m3u']);
              expect(
                find.textContaining(failed ? 'Failed to refresh' : 'Updated'),
                findsOneWidget,
              );
            }
            expect(f.requests.every((r) => r.method == 'GET'), isTrue);
          }, sources: [iptvFixtureSource('z9', xtream: xtream)]);
        },
      );
    }
  }

  testWidgets(
    'manual Xtream refresh breaks after a held section when visible scope changes',
    (tester) async {
      await iptvSettingsCase(tester, (f) async {
        await f.mount(tester);
        final target = f.playlists.first;
        await tester.runAsync(() => seedCatalog(f, target));
        f.holdAction = 'get_live_streams';
        f.heldHttp = Completer<http.Response>();
        late Future<void> work;
        await tester.runAsync(() async {
          work = f.member('refreshPlaylist')(target) as Future<void>;
          f.outstanding.add(work);
        });
        await f.until(
          tester,
          () => f.requests.any(
            (r) => r.url.queryParameters['action'] == 'get_live_streams',
          ),
        );
        final old = ProfileRuntime.scope.value!;
        await tester.runAsync(
          () => f.switchProfile(f.incomingId, close: false),
        );
        f.holdAction = null;
        f.heldHttp!.complete(
          http.Response(
            '[{"stream_id":9,"name":"Channel","category_id":"7"}]',
            200,
          ),
        );
        var done = false;
        work.whenComplete(() => done = true);
        await f.until(tester, () => done);
        await tester.runAsync(() => work);
        expect(
          f.requests.where(
            (r) =>
                r.url.queryParameters['action'] == 'get_vod_streams' ||
                r.url.queryParameters['action'] == 'get_series',
          ),
          isEmpty,
        );
        expect(f.member('refreshingIds'), isEmpty);
        expect(find.textContaining('Updated "'), findsNothing);
        await tester.runAsync(() async {
          expect((await f.stored(old.profileId)).single.id, target.id);
          expect(await f.stored(f.incomingId), isEmpty);
          await f.switchProfile(f.incomingId);
          expect(await f.catalogKeysOnDisk(f.ownerId), [
            IptvCatalogKey.forPlaylist(target, 'live'),
          ]);
          expect(await f.catalogKeysOnDisk(f.incomingId), isEmpty);
        });
      }, sources: [iptvFixtureSource('z9', xtream: true)]);
    },
  );

  testWidgets(
    'TV playlist LEFT RIGHT chain and remove repair retain row-slot node',
    (tester) async {
      await iptvSettingsCase(tester, (f) async {
        PlatformUtil.debugSetAndroidTvCached(true);
        await f.mount(tester, size: const Size(800, 1000), add: true);
        final nodes = (f.member('playlistFocusNodes') as List)
            .cast<FocusNode>();
        nodes.first.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, same(nodes[1]));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, same(nodes[2]));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, same(nodes[3]));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, same(nodes[2]));
        await f.action(
          tester,
          () => f.member('removePlaylist')(f.playlists.first) as Future<void>,
        );
        tester.binding.scheduleFrame();
        await tester.pump();
        expect(f.playlists.length, 1);
        expect(
          FocusManager.instance.primaryFocus,
          same((f.member('playlistFocusNodes') as List).first),
        );
        expect((f.member('playlistFocusNodes') as List).length, 4);
      }, sources: [iptvFixtureSource('z9'), iptvFixtureSource('a2')]);
    },
  );
}
