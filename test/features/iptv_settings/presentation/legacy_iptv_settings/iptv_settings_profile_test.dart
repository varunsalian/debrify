import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/profiles/profile_gate.dart';
import 'package:debrify/screens/profiles/profile_wall_screen.dart';
import 'package:debrify/screens/settings/iptv_settings_page.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../../../../support/iptv_settings_held_boundaries.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/iptv_settings_fixture.dart';

Future<void> unchangedBoth(IptvSettingsFixture f, String resourceId) async {
  expect((await f.stored(f.ownerId)).single.connectionResourceId, resourceId);
  expect(
    (await f.stored(f.incomingId)).single.connectionResourceId,
    resourceId,
  );
  expect((await f.registry.getResource(resourceId))!.ownerProfileId, f.ownerId);
  expect(
    (await f.registry.getGrant(
      f.ownerId,
      resourceId,
    ))!.allows(ResourcePermission.use),
    isTrue,
  );
  expect(
    (await f.registry.getGrant(
      f.incomingId,
      resourceId,
    ))!.allows(ResourcePermission.use),
    isTrue,
  );
}

void main() {
  testWidgets(
    'non Admin owner of a shared source is refused without removing either grant',
    (t) async {
      await iptvSettingsCase(t, (f) async {
        await t.runAsync(() async {
          await f.grantSource();
          final actor = (await f.registry.getProfile(f.ownerId))!;
          await f.registry.updateProfile(
            id: f.ownerId,
            role: UserProfileRole.member,
            policy: ProfilePolicy.defaultsFor(UserProfileRole.member),
            actingProfileId: f.ownerId,
            actingAuthorizationRevision: actor.authorizationRevision,
            actingSessionEpoch: ProfileRuntime.capture().sessionEpoch,
          );
        });
        await f.mount(t);
        expect(
          (await t.runAsync(
            () => f.registry.getResource(f.connectionId!),
          ))!.ownerProfileId,
          f.ownerId,
        );
        await f.action(
          t,
          () => f.member('removePlaylist')(f.playlists.single) as Future<void>,
        );
        expect(find.byType(IptvSharedSourceDeleteDialog), findsNothing);
        expect(
          find.text(
            'Only an Admin can remove a source shared with other profiles.',
          ),
          findsOneWidget,
        );
        await t.runAsync(() => unchangedBoth(f, f.connectionId!));
      }, sources: [iptvFixtureSource('z9')]);
    },
  );
  for (final confirm in [false, true]) {
    testWidgets(
      'Admin shared source ${confirm ? 'confirm revokes both grants' : 'cancel preserves both grants'}',
      (t) async {
        await iptvSettingsCase(t, (f) async {
          await t.runAsync(f.grantSource);
          await f.mount(t);
          late Future<void> work;
          await t.runAsync(() async {
            work =
                f.member('removePlaylist')(f.playlists.single) as Future<void>;
            f.outstanding.add(work);
          });
          await f.until(
            t,
            () =>
                find.byType(IptvSharedSourceDeleteDialog).evaluate().isNotEmpty,
          );
          await f.frames(t);
          expect(
            find.textContaining('shared with 1 other profile'),
            findsOneWidget,
          );
          await t.runAsync(() => unchangedBoth(f, f.connectionId!));
          await f.tap(t, find.text(confirm ? 'OK' : 'Cancel'));
          var done = false;
          work.whenComplete(() => done = true);
          await f.until(t, () => done);
          await t.runAsync(() => work);
          await f.frames(t);
          await t.runAsync(() async {
            if (confirm) {
              expect(await f.stored(f.ownerId), isEmpty);
              expect(await f.stored(f.incomingId), isEmpty);
              expect(await f.registry.getResource(f.connectionId!), isNull);
              expect(
                await f.registry.getGrant(f.ownerId, f.connectionId!),
                isNull,
              );
              expect(
                await f.registry.getGrant(f.incomingId, f.connectionId!),
                isNull,
              );
            } else {
              await unchangedBoth(f, f.connectionId!);
            }
          });
          expect(
            find.textContaining('Removed "'),
            confirm ? findsOneWidget : findsNothing,
          );
        }, sources: [iptvFixtureSource('z9')]);
      },
    );
  }

  testWidgets(
    'mounted State scope replacement during shared confirmation writes nothing and explains it',
    (t) async {
      await iptvSettingsCase(t, (f) async {
        await t.runAsync(f.grantSource);
        await f.mount(t);
        final old = f.state;
        late Future<void> work;
        await t.runAsync(() async {
          work = f.member('removePlaylist')(f.playlists.single) as Future<void>;
          f.outstanding.add(work);
        });
        await f.until(
          t,
          () => find.byType(IptvSharedSourceDeleteDialog).evaluate().isNotEmpty,
        );
        await f.frames(t);
        await t.runAsync(() => f.switchProfile(f.incomingId));
        expect(f.state, same(old));
        expect(old.mounted, isTrue);
        await f.tap(t, find.text('OK'));
        var done = false;
        work.whenComplete(() => done = true);
        await f.until(t, () => done);
        await t.runAsync(() => work);
        await f.frames(t);
        expect(
          find.text('The active profile changed. Nothing was removed.'),
          findsOneWidget,
        );
        await t.runAsync(() => unchangedBoth(f, f.connectionId!));
        expect(f.catalogPaths[f.ownerId], isNot(f.catalogPaths[f.incomingId]));
      }, sources: [iptvFixtureSource('z9')]);
    },
  );

  testWidgets(
    'stale pre body authorization rejects actual writes and preserves both profile grants',
    (t) async {
      await iptvSettingsCase(t, (f) async {
        await t.runAsync(f.grantSource);
        await f.mount(t);
        final prefs = (await t.runAsync(SharedPreferences.getInstance))!;
        final before = {
          for (final key in prefs.getKeys()) key: prefs.get(key)!,
        };
        final adapter = IptvHeldPreferences({
          for (final entry in before.entries)
            'flutter.${entry.key}': entry.value,
        });
        SharedPreferencesStorePlatform.instance = adapter;
        Object? error;
        var done = false;
        await t.runAsync(() async {
          final work = f.member('setIptvStyle')('classic') as Future<void>;
          f.outstanding.add(
            work.then(
              (_) {
                done = true;
              },
              onError: (Object e) {
                error = e;
                done = true;
              },
            ),
          );
          final s = ProfileRuntime.capture();
          ProfileRuntime.publish(
            ProfileScope(
              profileId: f.incomingId,
              dataGeneration: 1,
              sessionEpoch: s.sessionEpoch + 1,
            ),
          );
        });
        await f.until(t, () => done);
        expect(error, isA<StateError>());
        expect(adapter.writes, isEmpty);
        expect({
          for (final key in prefs.getKeys()) key: prefs.get(key)!,
        }, before);
        expect(f.member('iptvStyle'), isNot('classic'));
        await t.runAsync(() => unchangedBoth(f, f.connectionId!));
      }, sources: [iptvFixtureSource('z9')]);
    },
  );

  testWidgets(
    'real ProfileGate epoch remount replaces owners and an in flight shared removal returns silently',
    (t) async {
      await iptvSettingsCase(
        t,
        (f) async {
          await t.runAsync(() async {
            await ProfileGateAlwaysAsk.set(false);
            await ProfileGateStyle.set(ProfileGateStyle.classic);
          });
          t.view.physicalSize = const Size(1200, 800);
          t.view.devicePixelRatio = 1;
          await t.pumpWidget(
            MaterialApp(
              navigatorKey: f.navigatorKey,
              home: const ProfileGate(child: IptvSettingsPage()),
            ),
          );
          State state() => t.state<State>(find.byType(IptvSettingsPage));
          Map<String, dynamic> access() => iptvSettingsTestAccess(state());
          await f.until(
            t,
            () =>
                find.byType(IptvSettingsPage).evaluate().isNotEmpty &&
                access()['loading'] == false,
          );
          await f.frames(t);
          final old = state();
          final before = access();
          await t.runAsync(() async {
            final actor = (await f.registry.getProfile(f.ownerId))!;
            f.incomingId = (await f.registry.createProfile(
              name: 'Incoming',
              role: UserProfileRole.admin,
              actingProfileId: f.ownerId,
              actingAuthorizationRevision: actor.authorizationRevision,
              actingSessionEpoch: ProfileRuntime.capture().sessionEpoch,
            )).id;
            await f.grantSource();
          });
          late Future<void> work;
          await t.runAsync(() async {
            work =
                before['removePlaylist']((before['playlists'] as List).single)
                    as Future<void>;
            f.outstanding.add(work);
          });
          await f.until(
            t,
            () =>
                find.byType(IptvSharedSourceDeleteDialog).evaluate().isNotEmpty,
          );
          await f.frames(t);
          await t.runAsync(() async {
            await f.registry.setActiveProfile(f.incomingId);
            await f.switchProfile(f.incomingId);
          });
          await f.until(
            t,
            () => state() != old && access()['loading'] == false,
          );
          await f.frames(t);
          expect(old.mounted, isFalse);
          for (final name in [
            'twoPaneKey',
            'tabController',
            'nameController',
            'urlController',
            'epgUrlController',
            'xcNameController',
            'xcServerController',
            'xcUsernameController',
            'xcPasswordController',
            'playlistFocusNodes',
            'listFocusNodes',
            'hiddenFocusNodes',
            'refreshingIds',
            'hubSourcesFocusNode',
            'backButtonFocusNode',
          ]) {
            expect(access()[name], isNot(same(before[name])), reason: name);
          }
          await f.tap(t, find.text('OK'));
          var done = false;
          work.whenComplete(() => done = true);
          await f.until(t, () => done);
          await t.runAsync(() => work);
          await f.frames(t);
          expect(find.textContaining('Nothing was removed'), findsNothing);
          expect(find.textContaining('Removed "'), findsNothing);
          await t.runAsync(() => unchangedBoth(f, f.connectionId!));
          expect(
            f.catalogPaths[f.ownerId],
            isNot(f.catalogPaths[f.incomingId]),
          );
        },
        sources: [iptvFixtureSource('z9')],
        singleProfile: true,
      );
    },
  );

  testWidgets(
    'held shared removal persists revocation in origin before its stale save catch all',
    (t) async {
      await iptvSettingsCase(t, (f) async {
        await t.runAsync(f.grantSource);
        await f.mount(t);
        final oldSource = f.playlists.single;
        late Future<void> work;
        await t.runAsync(() async {
          work = f.member('removePlaylist')(oldSource) as Future<void>;
          f.outstanding.add(work);
        });
        await f.until(
          t,
          () => find.byType(IptvSharedSourceDeleteDialog).evaluate().isNotEmpty,
        );
        await f.frames(t);
        final entered = Completer<void>();
        final release = Completer<void>();
        f.registry.authorityWillChangeCallback = () async {
          if (!entered.isCompleted) {
            entered.complete();
            await release.future;
          }
        };
        try {
          await f.tap(t, find.text('OK'));
          await f.until(t, () => entered.isCompleted);
          await t.runAsync(() => f.switchProfile(f.incomingId));
          release.complete();
          var done = false;
          work.whenComplete(() => done = true);
          await f.until(t, () => done);
          await t.runAsync(() => work);
          await f.frames(t);
          expect(f.playlists.single.id, oldSource.id);
          expect(
            find.text(
              'Could not remove "${oldSource.name}". Please try again.',
            ),
            findsOneWidget,
          );
          await t.runAsync(() async {
            expect(await f.stored(f.ownerId), isEmpty);
            expect(await f.stored(f.incomingId), isEmpty);
            expect(await f.registry.getResource(f.connectionId!), isNull);
            expect(
              await f.registry.getGrant(f.ownerId, f.connectionId!),
              isNull,
            );
            expect(
              await f.registry.getGrant(f.incomingId, f.connectionId!),
              isNull,
            );
          });
        } finally {
          if (!release.isCompleted) release.complete();
          f.registry.authorityWillChangeCallback = null;
        }
      }, sources: [iptvFixtureSource('z9')]);
    },
  );

  for (final caller in [
    'addPlaylist',
    'addXtreamCodes',
    'importFromFile',
    'editPlaylist',
  ]) {
    testWidgets(
      '$caller held resource save persists in origin then retains its own stale save handling',
      (t) async {
        await iptvSettingsCase(t, (f) async {
          await t.runAsync(f.grantSource);
          await f.mount(t, add: true);
          final source = f.playlists.single;
          if (caller == 'addPlaylist') {
            (f.member('nameController') as TextEditingController).text =
                'New URL';
            (f.member('urlController') as TextEditingController).text =
                'https://fixture.invalid/new.m3u';
          } else if (caller == 'addXtreamCodes') {
            (f.member('xcServerController') as TextEditingController).text =
                'https://fixture.invalid/newpanel';
            (f.member('xcUsernameController') as TextEditingController).text =
                'new-user';
            (f.member('xcPasswordController') as TextEditingController).text =
                'pass';
          } else if (caller == 'importFromFile') {
            f.picker.file(
              'New File.m3u',
              Uint8List.fromList(utf8.encode(iptvFixtureM3u)),
            );
          }
          f.cipher.holdSeal = true;
          f.cipher.entered = Completer<void>();
          f.cipher.release = Completer<void>();
          Object? error;
          var done = false;
          await t.runAsync(() async {
            final work = caller == 'editPlaylist'
                ? f.member(caller)(source) as Future<void>
                : f.member(caller)() as Future<void>;
            f.outstanding.add(
              work.then(
                (_) {
                  done = true;
                },
                onError: (Object e) {
                  error = e;
                  done = true;
                },
              ),
            );
          });
          if (caller == 'importFromFile' || caller == 'editPlaylist') {
            await f.until(t, () => find.byType(Dialog).evaluate().isNotEmpty);
            await f.frames(t);
            if (caller == 'editPlaylist') {
              await t.enterText(
                find.descendant(
                  of: find.byType(Dialog),
                  matching: find.widgetWithText(TvTextField, 'Playlist Name'),
                ),
                'Edited',
              );
            }
            await f.tap(
              t,
              find.text(caller == 'editPlaylist' ? 'Save' : 'Import').last,
            );
          }
          await f.until(t, () => f.cipher.entered!.isCompleted);
          await t.runAsync(() => f.switchProfile(f.incomingId));
          f.cipher.release!.complete();
          await f.until(t, () => done);
          await f.frames(t);
          if (caller == 'importFromFile') {
            expect(error, isNull);
            expect(
              find.text(
                'Failed to import file: Bad state: Profile changed while saving IPTV playlists',
              ),
              findsOneWidget,
            );
          } else {
            expect(error, isA<StateError>());
            expect(
              error.toString(),
              'Bad state: Profile changed while saving IPTV playlists',
            );
          }
          expect(f.playlists.single.name, source.name);
          expect(f.member('isAdding'), caller == 'addPlaylist');
          expect(f.member('isXcAdding'), caller == 'addXtreamCodes');
          await t.runAsync(() async {
            final origin = await f.stored(f.ownerId);
            final incoming = await f.stored(f.incomingId);
            expect(origin.length, caller == 'editPlaylist' ? 1 : 2);
            expect(
              origin.any(
                (p) =>
                    p.name ==
                    (caller == 'editPlaylist'
                        ? 'Edited'
                        : caller == 'addPlaylist'
                        ? 'New URL'
                        : caller == 'importFromFile'
                        ? 'New File'
                        : 'new-user@fixture.invalid'),
              ),
              isTrue,
            );
            expect(incoming.length, 1);
            expect(
              incoming.single.connectionResourceId,
              source.connectionResourceId,
            );
            expect(
              (await f.registry.getGrant(
                f.ownerId,
                f.connectionId!,
              ))!.allows(ResourcePermission.use),
              isTrue,
            );
            expect(
              (await f.registry.getGrant(
                f.incomingId,
                f.connectionId!,
              ))!.allows(ResourcePermission.use),
              isTrue,
            );
            for (final p in origin.where(
              (p) => p.connectionResourceId != f.connectionId,
            )) {
              expect(
                await f.registry.getGrant(
                  f.incomingId,
                  p.connectionResourceId!,
                ),
                isNull,
              );
            }
          });
        }, sources: [iptvFixtureSource('z9')]);
      },
    );
  }
}
