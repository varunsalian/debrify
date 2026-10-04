import 'dart:async';
import 'dart:convert';

import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/services/iptv_catalog_refresh_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/services/storage/startup_iptv_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../../../support/iptv_settings_fixture.dart';
import '../../../../support/iptv_settings_held_boundaries.dart';

void main() {
  testWidgets(
    'create rename cancel delete and reorder keep actual list persistence',
    (t) async {
      await iptvSettingsCase(t, (f) async {
        await f.mount(t);
        late Future<void> work;
        Future<void> start(String action, [dynamic arg]) async {
          await t.runAsync(() async {
            work = arg == null
                ? f.member(action)() as Future<void>
                : f.member(action)(arg) as Future<void>;
            f.outstanding.add(work);
          });
          await f.frames(t);
        }

        await start('createList');
        expect(find.text('New list'), findsOneWidget);
        await t.enterText(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(TextField),
          ),
          'Cinema',
        );
        await f.tap(t, find.text('Create'));
        await f.until(t, () => f.lists.any((l) => l.name == 'Cinema'));
        await t.runAsync(() => work);
        final before = f.member('lists');
        final id = f.lists.single.id;
        await start('renameList', f.lists.single);
        expect(
          t
              .widget<TextField>(
                find.descendant(
                  of: find.byType(Dialog),
                  matching: find.byType(TextField),
                ),
              )
              .controller!
              .text,
          'Cinema',
        );
        await t.enterText(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(TextField),
          ),
          'Renamed',
        );
        await f.tap(t, find.text('Save'));
        await f.until(t, () => f.lists.single.name == 'Renamed');
        await t.runAsync(() => work);
        expect(f.member('lists'), isNot(same(before)));
        expect(f.lists.single.id, id);
        await start('deleteList', f.lists.single);
        expect(
          find.text('The list is empty, so nothing else changes.'),
          findsOneWidget,
        );
        await f.tap(t, find.text('Cancel'));
        await f.frames(t);
        await t.runAsync(() => work);
        expect(f.lists.single.id, id);
        await t.runAsync(() async {
          await IptvFavoritesStorage.createIptvList('Second');
        });
        await f.action(t, () => f.member('loadSettings')() as Future<void>);
        final first = f.lists.first;
        await f.action(
          t,
          () => f.member('moveList')(first, -1) as Future<void>,
        );
        expect(f.lists.map((l) => l.name), ['Renamed', 'Second']);
        await f.action(t, () => f.member('moveList')(first, 1) as Future<void>);
        expect(f.lists.map((l) => l.name), ['Second', 'Renamed']);
        await start('deleteList', f.lists.last);
        await f.tap(t, find.text('Delete'));
        await f.until(t, () => f.lists.length == 1);
        await t.runAsync(() => work);
        expect(f.lists.single.name, 'Second');
        await t.runAsync(() async {
          expect(
            (await IptvFavoritesStorage.getIptvLists())
                .where((l) => !l.isBuiltin)
                .map((l) => l.name),
            ['Second'],
          );
        });
        expect(f.member('customLists'), isNot(same(f.member('customLists'))));
      });
    },
  );
  for (final index in [0, 1, 2]) {
    testWidgets(
      'list sheet omits end moves and autofocuses Rename at index $index',
      (t) async {
        await iptvSettingsCase(t, (f) async {
          PlatformUtil.debugSetAndroidTvCached(true);
          await t.runAsync(() async {
            for (final name in ['A', 'B', 'C']) {
              await IptvFavoritesStorage.createIptvList(name);
            }
          });
          await f.mount(t);
          late Future<void> work;
          await t.runAsync(() async {
            work = f.member('showListActions')(f.lists[index]) as Future<void>;
            f.outstanding.add(work);
          });
          await f.frames(t);
          expect(find.text('Rename'), findsOneWidget);
          expect(
            find.text('Move up'),
            index > 0 ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('Move down'),
            index < 2 ? findsOneWidget : findsNothing,
          );
          expect(find.text('Delete'), findsOneWidget);
          expect(
            t
                .widget<ListTile>(find.widgetWithText(ListTile, 'Rename'))
                .autofocus,
            isTrue,
          );
          if (index == 0) {
            await f.tap(t, find.text('Move down'));
            await f.until(t, () => f.lists.first.name == 'B');
          } else if (index == 2) {
            await f.tap(t, find.text('Move up'));
            await f.until(t, () => f.lists[1].name == 'C');
          } else {
            f.navigatorKey.currentState!.pop();
            await f.frames(t);
          }
          await t.runAsync(() => work);
          await t.runAsync(() async {
            expect(
              (await IptvFavoritesStorage.getIptvLists())
                  .where((l) => !l.isBuiltin)
                  .map((l) => l.id),
              f.lists.map((l) => l.id),
            );
          });
        });
      },
    );
  }

  final settings =
      <
        ({
          String method,
          dynamic value,
          String key,
          dynamic persisted,
          String field,
        })
      >[
        (
          method: 'setStartupEnabled',
          value: true,
          key: 'startup_auto_launch_enabled',
          persisted: true,
          field: 'startupEnabled',
        ),
        (
          method: 'setStartupMode',
          value: 'last',
          key: 'startup_iptv_mode',
          persisted: 'last',
          field: 'startupMode',
        ),
        (
          method: 'setTrackContinueWatching',
          value: false,
          key: 'iptv_track_continue_watching',
          persisted: false,
          field: 'trackContinueWatching',
        ),
        (
          method: 'setChannelPreviewEnabled',
          value: false,
          key: 'iptv_channel_preview_enabled',
          persisted: false,
          field: 'channelPreviewEnabled',
        ),
        (
          method: 'setIptvStyle',
          value: 'console',
          key: 'iptv_style',
          persisted: 'console',
          field: 'iptvStyle',
        ),
        (
          method: 'setPlayerGuideStyle',
          value: 'glass',
          key: 'iptv_player_guide_style',
          persisted: 'glass',
          field: 'playerGuideStyle',
        ),
      ];
  for (final setting in settings) {
    for (final held in [false, true]) {
      testWidgets(
        '${setting.method} persists its original key${held ? ' under captured scope across a switch' : ''}',
        (t) async {
          await iptvSettingsCase(t, (f) async {
            await t.runAsync(f.grantSource);
            await f.mount(t);
            final source = f.playlists.single;
            final origin = 'flutter.p.${f.ownerId}.g.1.${setting.key}';
            late IptvHeldPreferences store;
            await t.runAsync(() async {
              store = IptvHeldPreferences(
                await SharedPreferencesStorePlatform.instance.getAll(),
              );
              SharedPreferencesStorePlatform.instance = store;
            });
            if (held) {
              store.holdKey = origin;
              store.entered = Completer<void>();
              store.release = Completer<void>();
            }
            late Future<void> work;
            var done = false;
            await t.runAsync(() async {
              work = (f.member(setting.method)(setting.value) as Future<void>)
                  .whenComplete(() => done = true);
              f.outstanding.add(work);
            });
            if (held) {
              await f.until(t, () => store.entered!.isCompleted);
              await t.runAsync(() => f.switchProfile(f.incomingId));
              store.release!.complete();
            }
            await f.until(t, () => done);
            await t.runAsync(() => work);
            expect(f.member(setting.field), setting.value);
            await t.runAsync(() async {
              final actual = await store.getAll();
              expect(actual[origin], setting.persisted);
              expect(
                actual['flutter.p.${f.incomingId}.g.1.${setting.key}'],
                isNull,
              );
              expect(
                (await f.stored(f.ownerId)).single.connectionResourceId,
                source.connectionResourceId,
              );
              expect(
                (await f.stored(f.incomingId)).single.connectionResourceId,
                source.connectionResourceId,
              );
              expect(
                await f.registry.getGrant(
                  f.ownerId,
                  source.connectionResourceId!,
                ),
                isNotNull,
              );
              expect(
                await f.registry.getGrant(
                  f.incomingId,
                  source.connectionResourceId!,
                ),
                isNotNull,
              );
              if (setting.method == 'setStartupEnabled') {
                expect(
                  actual['flutter.p.${f.ownerId}.g.1.startup_mode'],
                  'iptv',
                );
              }
            });
          }, sources: [iptvFixtureSource('z9')]);
        },
      );
    }
  }
  testWidgets('startup disable removes mode and null mode remains a no-op', (
    t,
  ) async {
    await iptvSettingsCase(t, (f) async {
      await f.mount(t);
      await f.action(
        t,
        () => f.member('setStartupEnabled')(true) as Future<void>,
      );
      await f.action(
        t,
        () => f.member('setStartupEnabled')(false) as Future<void>,
      );
      await f.action(t, () => f.member('setStartupMode')(null) as Future<void>);
      await t.runAsync(() async {
        final p = await ProfilePreferences.instance();
        expect(p.getBool('startup_auto_launch_enabled'), isFalse);
        expect(p.getString('startup_mode'), isNull);
        expect(p.getString('startup_iptv_mode'), isNull);
      });
      expect(
        await t.runAsync(StartupIptvStorage.getStartupIptvEnabled),
        isFalse,
      );
    });
  });

  testWidgets(
    'desktop scheduled counts are profile owned and max concurrent is device wide',
    (t) async {
      await iptvSettingsCase(t, (f) async {
        await t.runAsync(() async {
          final p = await SharedPreferences.getInstance();
          await p.setString(
            'desktop_recording_schedules_v1',
            jsonEncode([
              for (final id in [f.ownerId, f.ownerId, f.incomingId])
                {
                  'id': 'job-$id-${DateTime.now().microsecondsSinceEpoch}',
                  'url': 'https://fixture.invalid/live.ts',
                  'ownerProfileId': id,
                  'profileAuthorizationRevision': 1,
                  'startMs': 1893456000000,
                  'endMs': 1893456060000,
                },
            ]),
          );
        });
        await f.mount(t, size: const Size(800, 1000));
        f.member('enterPhoneSection')('recording');
        await t.pump();
        expect(f.member('scheduledCount'), 2);
        expect(find.text('Recordings (2 scheduled)'), findsOneWidget);
        expect(find.text('Background recording engine'), findsNothing);
        expect(find.textContaining('Battery optimization'), findsNothing);
        late Future<void> work;
        await t.runAsync(() async {
          work = f.member('pickMaxConcurrent')() as Future<void>;
          f.outstanding.add(work);
        });
        await f.until(t, () => find.byType(SimpleDialog).evaluate().isNotEmpty);
        await f.frames(t);
        await f.tap(t, find.text('3'));
        await f.until(t, () => f.member('maxConcurrent') == 3);
        await t.runAsync(() => work);
        await t.runAsync(() async {
          final p = await SharedPreferences.getInstance();
          expect(p.getInt('recording_max_concurrent'), 3);
          expect(
            p.getInt('p.${f.ownerId}.g.1.recording_max_concurrent'),
            isNull,
          );
          await f.switchProfile(f.incomingId);
          expect(await LiveRecordingService.maxConcurrent(), 3);
        });
        await f.action(t, () => f.member('loadSettings')() as Future<void>);
        await t.pump();
        expect(f.member('scheduledCount'), 1);
        expect(find.text('Recordings (1 scheduled)'), findsOneWidget);
      });
    },
  );
  for (final hours in [0, 6]) {
    testWidgets(
      'auto refresh $hours stores profile interval and discovery follows original eligibility',
      (t) async {
        await iptvSettingsCase(t, (f) async {
          await f.mount(t);
          final callsBefore =
              IptvCatalogRefreshService.debugRefreshDueInvocations;
          late Future<void> work;
          await t.runAsync(() async {
            work = f.member('pickAutoRefresh')() as Future<void>;
            f.outstanding.add(work);
          });
          await f.until(
            t,
            () => find.byType(SimpleDialog).evaluate().isNotEmpty,
          );
          await f.frames(t);
          final dialog = find.byType(SimpleDialog);
          await f.tap(
            t,
            find.descendant(
              of: dialog,
              matching: find.text(hours == 0 ? 'Off' : 'Every 6 hours'),
            ),
          );
          await f.until(t, () => f.member('autoRefreshHours') == hours);
          await t.runAsync(() => work);
          await t.runAsync(IptvCatalogRefreshService.instance.debugSettle);
          await f.frames(t);
          await t.runAsync(() async {
            expect(
              (await ProfilePreferences.instance()).getInt(
                'iptv_catalog_refresh_hours_v1',
              ),
              hours,
            );
          });
          expect(
            IptvCatalogRefreshService.debugRefreshDueInvocations - callsBefore,
            hours == 0 ? 1 : 2,
          );
          expect(
            f.requests.map((r) => r.url.toString()).toList(),
            hours == 0 ? <String>[] : ['https://fixture.invalid/z9.m3u'],
          );
        }, sources: [iptvFixtureSource('z9')]);
      },
    );
  }
  testWidgets(
    'scope change while auto refresh dialog is open preserves both profile intervals',
    (t) async {
      await iptvSettingsCase(t, (f) async {
        await f.mount(t);
        late Future<void> work;
        await t.runAsync(() async {
          work = f.member('pickAutoRefresh')() as Future<void>;
          f.outstanding.add(work);
        });
        await f.until(t, () => find.byType(SimpleDialog).evaluate().isNotEmpty);
        await f.frames(t);
        await t.runAsync(() => f.switchProfile(f.incomingId));
        await f.tap(
          t,
          find.descendant(
            of: find.byType(SimpleDialog),
            matching: find.text('Every 6 hours'),
          ),
        );
        await f.frames(t);
        await t.runAsync(() => work);
        expect(f.member('autoRefreshHours'), 0);
        expect(f.requests, isEmpty);
        await t.runAsync(() async {
          final p = await SharedPreferences.getInstance();
          for (final id in [f.ownerId, f.incomingId]) {
            expect(p.getInt('p.$id.g.1.iptv_catalog_refresh_hours_v1'), 0);
          }
        });
      });
    },
  );
}
