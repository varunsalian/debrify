import 'dart:async';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_creation_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/edit_profile_fixture.dart';

Future<void> finished(WidgetTester t, EditProfileFixture f) => f.until(
  t,
  () =>
      f.popped ||
      find.text('Could not save this profile').evaluate().isNotEmpty,
);

Future<void> role(WidgetTester t, EditProfileFixture f, String value) async {
  final dynamic tile = t.widget(find.byKey(ValueKey('tv-profile-role-$value')));
  (tile.onPressed as VoidCallback)();
  await t.pump();
}

Future<void> autoLock(
  WidgetTester t,
  EditProfileFixture f,
  String label,
) async {
  await f.section(t, 'lock');
  await f.tap(t, find.byKey(const ValueKey('tv-profile-auto-lock')));
  await f.tap(
    t,
    find.descendant(of: find.byType(SimpleDialog), matching: find.text(label)),
  );
}

Future<void> Function() transfer(WidgetTester t) {
  final dynamic callback = t
      .widget<IconButton>(
        find.byWidgetPredicate(
          (w) =>
              w is IconButton &&
              w.tooltip == 'Transfer ownership to this profile',
        ),
      )
      .onPressed;
  return () => callback() as Future<void>;
}

void main() {
  for (final create in [true, false]) {
    for (final demote in [false, true]) {
      testWidgets(
        '0b Save ${create ? "create" : "edit"} rejects ${demote ? "demoted" : "stale"} actor after loaded options',
        (t) async {
          await editProfileCase(t, (f) async {
            final target = (await t.runAsync(() => f.profile('Target')))!;
            await t.runAsync(
              () => f.profile('Other Admin', role: UserProfileRole.admin),
            );
            await f.mount(t, target: create ? null : target);
            await f.name(t, 'Forbidden write');
            expect(find.byType(LinearProgressIndicator), findsNothing);
            await t.runAsync(
              () => f.registry.updateProfile(
                id: f.admin.id,
                name: 'Changed authority',
                role: demote ? UserProfileRole.member : UserProfileRole.admin,
                actingProfileId: f.authorization.profileId,
                actingAuthorizationRevision:
                    f.authorization.authorizationRevision,
                actingSessionEpoch: f.authorization.sessionEpoch,
              ),
            );
            var writeAttempts = 0;
            f.registry.authorityWillChangeCallback = () async {
              writeAttempts++;
            };
            await f.save(t);
            await finished(t, f);
            expect(f.popped, isFalse);
            expect(
              writeAttempts,
              0,
              reason: 'editor rejects before registry write boundary',
            );
            expect(
              await t.runAsync(
                () => f.registry.listProfiles(includeStaging: true),
              ),
              hasLength(3),
            );
            expect(
              (await t.runAsync(() => f.registry.getProfile(target.id)))!.name,
              'Target',
            );
            if (create) {
              await t.runAsync(() async {
                try {
                  await ProfileCreationService(f.registry).createStaged(
                    actor: f.authorization,
                    name: 'Core must refuse staging',
                    role: UserProfileRole.member,
                    policy: ProfilePolicy.defaultsFor(UserProfileRole.member),
                    copyDefaultsFromActive: false,
                  );
                  fail('stale original actor must be rejected by core');
                } catch (error, stack) {
                  expect(
                    error.toString(),
                    contains('Profile authorization has changed'),
                  );
                  expect(
                    stack.toString(),
                    contains('ProfileAuthorizationContext.validate'),
                  );
                  expect(
                    stack.toString(),
                    contains('ProfileCreationService.createStaged'),
                  );
                  debugPrint(
                    'S demonstration: createStaged calls actor.validate before registry.createProfile; $error; $stack',
                  );
                }
              });
            }
          });
        },
      );
    }
  }

  testWidgets(
    '0b create refresh after staged update keeps changed Admin authority',
    (t) async {
      await editProfileCase(t, (f) async {
        await t.runAsync(() => f.engine(f.admin, 'alpha', 'Alpha engine'));
        var ordinal = 0;
        f.registry.authorityChangedCallback = () async {
          if (++ordinal != 2) return;
          f.registry.authorityChangedCallback = null;
          await f.registry.updateProfile(
            id: f.admin.id,
            name: 'Admin authority advanced',
            actingProfileId: f.authorization.profileId,
            actingAuthorizationRevision: f.authorization.authorizationRevision,
            actingSessionEpoch: f.authorization.sessionEpoch,
          );
        };
        await f.mount(t);
        await f.name(t, 'Created');
        await f.save(t);
        await finished(t, f);
        expect(
          f.result,
          isTrue,
          reason: 'refresh after staged update precedes engine apply',
        );
        final created = (await t.runAsync(
          () => f.registry.listProfiles(),
        ))!.singleWhere((p) => p.id != f.admin.id);
        expect(
          await t.runAsync(() => f.engines(created.id)),
          contains('alpha'),
        );
      });
    },
  );

  testWidgets('0b own Admin publish refresh precedes later engine validation', (
    t,
  ) async {
    await editProfileCase(t, (f) async {
      await f.mount(t, target: f.admin);
      await f.name(t, 'Admin published');
      await f.save(t);
      await finished(t, f);
      expect(f.result, isTrue);
      expect(f.reloads, 1);
      expect(
        (await t.runAsync(() => f.registry.getProfile(f.admin.id)))!.name,
        'Admin published',
      );
    });
  });

  testWidgets('0b own Admin PIN refresh and edit recovery dialog precede pop', (
    t,
  ) async {
    await editProfileCase(t, (f) async {
      var writes = 0;
      f.registry.authorityChangedCallback = () async {
        if (++writes != 2) return; // publish, then real PIN write
        f.registry.authorityChangedCallback = null;
        await f.refreshActor();
        await f.registry.updateProfile(
          id: f.admin.id,
          name: 'Authority changed after PIN',
          actingProfileId: f.authorization.profileId,
          actingAuthorizationRevision: f.authorization.authorizationRevision,
          actingSessionEpoch: f.authorization.sessionEpoch,
        );
      };
      await f.mount(t, target: f.admin);
      await f.pin(t, '4321');
      await f.save(t);
      await f.until(
        t,
        () =>
            f.popped ||
            find.text('I saved it').evaluate().isNotEmpty ||
            find.text('Could not save this profile').evaluate().isNotEmpty,
      );
      expect(find.text('Save this recovery code'), findsOneWidget);
      expect(f.popped, isFalse);
      expect(
        (await t.runAsync(() => f.registry.getProfile(f.admin.id)))!.hasPin,
        isTrue,
      );
      expect(f.pins.targets, [f.admin.id]);
      expect(find.byType(SelectableText), findsOneWidget);
      await f.tap(t, find.text('I saved it'));
      await f.until(t, () => f.popped);
      expect(f.result, isTrue);
    });
  });

  for (final create in [true, false]) {
    testWidgets(
      '0b ${create ? "create" : "edit"} engine seeds and selected assignments reach target only',
      (t) async {
        await editProfileCase(t, (f) async {
          final target = (await t.runAsync(() => f.profile('Target')))!;
          await t.runAsync(() async {
            await f.engine(f.admin, 'alpha', 'Alpha engine');
            await f.engine(f.admin, 'beta', 'Beta engine');
            if (!create) await f.engine(target, 'beta', 'Beta engine');
          });
          f.television = true;
          await f.mount(t, target: create ? null : target);
          await f.name(t, 'Engine target');
          await f.section(t, 'access');
          expect(f.checkbox(t, 'Alpha engine').value, create);
          expect(f.checkbox(t, 'Beta engine').value, isTrue);
          if (!create) await f.check(t, 'Alpha engine', true);
          await f.check(t, 'Beta engine', false);
          await f.save(t);
          await finished(t, f);
          expect(f.result, isTrue);
          final id = create
              ? (await t.runAsync(() => f.registry.listProfiles()))!
                    .singleWhere((p) => p.id != target.id && p.id != f.admin.id)
                    .id
              : target.id;
          final installed = (await t.runAsync(() => f.engines(id)))!;
          expect(installed.keys, ['alpha']);
          expect(
            installed['alpha'],
            'name: Alpha engine\nsource: original_alpha\n',
          );
          expect(
            (await t.runAsync(() => f.engines(f.admin.id)))!.keys.toSet(),
            {'alpha', 'beta'},
          );
        });
      },
    );
  }

  testWidgets('0b transfer refuses stale actor before showing dialog', (
    t,
  ) async {
    await editProfileCase(t, (f) async {
      final target = (await t.runAsync(
        () => f.profile(
          'Target',
          policy: ProfilePolicy.defaultsFor(UserProfileRole.admin),
        ),
      ))!;
      final resource = (await t.runAsync(() => f.resource('Cloud A')))!;
      f.television = true;
      await f.mount(t, target: target);
      await f.section(t, 'access');
      final start = transfer(t);
      await t.runAsync(() => f.activate(f.admin));
      Object? rejection;
      Future<void>? pending;
      await t.runAsync(() async {
        pending = start().catchError((Object e) {
          rejection = e;
        });
      });
      await f.until(
        t,
        () =>
            rejection != null ||
            find.text('Transfer connection ownership?').evaluate().isNotEmpty,
      );
      try {
        expect(find.text('Transfer connection ownership?'), findsNothing);
        expect(
          rejection.toString(),
          contains('Profile authorization session has ended'),
        );
        expect(
          (await t.runAsync(
            () => f.registry.getResource(resource.id),
          ))!.ownerProfileId,
          f.admin.id,
        );
      } finally {
        if (find.text('Cancel').evaluate().isNotEmpty) {
          await f.tap(t, find.text('Cancel'));
        }
        await t.runAsync(() => pending!);
      }
    });
  });

  testWidgets(
    '0b transfer revalidates after dialog and core masks omitted prewrite guard',
    (t) async {
      await editProfileCase(t, (f) async {
        final target = (await t.runAsync(
          () => f.profile(
            'Target',
            policy: ProfilePolicy.defaultsFor(UserProfileRole.admin),
          ),
        ))!;
        final resource = (await t.runAsync(() => f.resource('Cloud A')))!;
        f.television = true;
        await f.mount(t, target: target);
        await f.section(t, 'access');
        late Future<void> pending;
        await t.runAsync(() async {
          pending = transfer(t)();
        });
        await f.settle(t);
        expect(find.text('Transfer connection ownership?'), findsOneWidget);
        await t.runAsync(() => f.activate(f.admin));
        await f.tap(t, find.text('Transfer'));
        await t.runAsync(() => pending);
        await t.pump();
        expect(
          find.text('Connection could not be transferred'),
          findsOneWidget,
        );
        expect(
          (await t.runAsync(
            () => f.registry.getResource(resource.id),
          ))!.ownerProfileId,
          f.admin.id,
        );
        await t.runAsync(() async {
          try {
            await ConnectionResourceService(
              registry: f.registry,
              cipher: DeviceKeyProvider.cipher,
            ).transferOwnership(
              actor: f.authorization,
              resourceId: resource.id,
              newOwnerProfileId: target.id,
            );
            fail('core must reject same stale actor');
          } catch (error, stack) {
            expect(
              error.toString(),
              contains('Profile authorization session has ended'),
            );
            expect(
              stack.toString(),
              contains('ConnectionResourceService.transferOwnership'),
            );
            expect(
              stack.toString(),
              contains('ProfileAuthorizationContext.validate'),
            );
            debugPrint(
              'S demonstration: ConnectionResourceService.transferOwnership first await actor.validate rejects before reseal/write; $error',
            );
          }
        });
      });
    },
  );

  testWidgets('0b transfer refresh supports a later Save in same editor', (
    t,
  ) async {
    await editProfileCase(t, (f) async {
      final target = (await t.runAsync(
        () => f.profile(
          'Target',
          policy: ProfilePolicy.defaultsFor(UserProfileRole.admin),
        ),
      ))!;
      final resource = (await t.runAsync(() => f.resource('Cloud A')))!;
      f.television = true;
      await f.mount(t, target: target);
      await f.section(t, 'access');
      late Future<void> pending;
      await t.runAsync(() async {
        pending = transfer(t)();
      });
      await f.until(
        t,
        () => find.text('Transfer connection ownership?').evaluate().isNotEmpty,
      );
      await f.tap(t, find.text('Transfer'));
      await t.runAsync(() => pending);
      await t.pump();
      expect(
        (await t.runAsync(
          () => f.registry.getResource(resource.id),
        ))!.ownerProfileId,
        target.id,
      );
      if (find.text('Cloud A').evaluate().isNotEmpty) {
        final row = f.checkbox(t, 'Cloud A');
        final grant = (await t.runAsync(
          () => f.registry.getGrant(target.id, resource.id),
        ))!;
        debugPrint(
          'Found-not-fixed transfer selection: selected=${row.value}, interactive=${row.onChanged != null}, ownerGrantUse=${grant.allows(ResourcePermission.use)}',
        );
      }
      await f.section(t, 'profile');
      await f.name(t, 'After transfer');
      final dynamic save = f.saveCallback(t);
      await t.runAsync(() async {
        await (save() as Future<void>);
      });
      await f.settle(t);
      expect(
        f.result,
        isTrue,
        reason: 'later Save uses refreshed managing Admin revision',
      );
      expect(
        (await t.runAsync(() => f.registry.getProfile(target.id)))!.name,
        'After transfer',
      );
    });
  });

  testWidgets('0b own Admin reset refresh supports later Save in same editor', (
    t,
  ) async {
    await editProfileCase(t, (f) async {
      await t.runAsync(() async {
        await f.pins.setPinAsAdmin(
          actor: f.authorization,
          targetProfileId: f.admin.id,
          pin: '1234',
        );
        await f.refreshActor();
      });
      final target = (await t.runAsync(
        () => f.registry.getProfile(f.admin.id),
      ))!;
      f.registry.authorityChangedCallback = () async {
        f.registry.authorityChangedCallback = null;
        await f.registry.updateProfile(
          id: f.admin.id,
          name: 'Authority changed after reset',
          actingProfileId: f.authorization.profileId,
          actingAuthorizationRevision: f.authorization.authorizationRevision,
          actingSessionEpoch: f.authorization.sessionEpoch,
        );
      };
      f.television = true;
      await f.mount(t, target: target);
      await f.section(t, 'lock');
      await f.tap(t, find.text('Admin reset: remove PIN'));
      await f.until(
        t,
        () => find.text('PIN protection removed').evaluate().isNotEmpty,
      );
      expect(
        (await t.runAsync(() => f.registry.getProfile(target.id)))!.hasPin,
        isFalse,
      );
      await f.section(t, 'profile');
      await f.name(t, 'After reset');
      await f.save(t);
      await finished(t, f);
      expect(f.result, isTrue);
      expect(
        (await t.runAsync(() => f.registry.getProfile(target.id)))!.name,
        'After reset',
      );
    });
  });

  testWidgets(
    '0b loaded download-only grant gains required use permission on Save',
    (t) async {
      await editProfileCase(t, (f) async {
        final target = (await t.runAsync(() => f.profile('Target')))!;
        final resource = (await t.runAsync(() => f.resource('Cloud A')))!;
        await t.runAsync(
          () => f.grant(target, resource, {ResourcePermission.download}),
        );
        expect(
          (await t.runAsync(
            () => f.registry.getGrant(target.id, resource.id),
          ))!.allows(ResourcePermission.use),
          isFalse,
        );
        await f.mount(t, target: target);
        await f.save(t);
        await finished(t, f);
        expect(f.result, isTrue);
        final grant = (await t.runAsync(
          () => f.registry.getGrant(target.id, resource.id),
        ))!;
        expect(
          grant.permissions,
          ResourcePermission.use.bit | ResourcePermission.download.bit,
        );
      });
    },
  );

  testWidgets(
    '0b create copy defaults switched off leaves actual appearance uncopied',
    (t) async {
      await editProfileCase(t, (f) async {
        await t.runAsync(() async {
          final prefs = await ProfilePreferences.instance();
          await prefs.setString('app_theme', 'light');
        });
        await f.mount(t);
        await f.name(t, 'No copied defaults');
        await f.tap(t, find.text('Copy appearance and playback defaults'));
        expect(
          t.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
          isFalse,
        );
        await f.save(t);
        await finished(t, f);
        expect(f.result, isTrue);
        final row = (await t.runAsync(
          () => f.registry.listProfiles(),
        ))!.singleWhere((p) => p.id != f.admin.id);
        final prefs = (await t.runAsync(
          () => ProfilePreferences.forCapturedScope(
            f.scope(row),
            CapturedProfilePreferenceAccess.diagnosticsReadOnly,
          ),
        ))!;
        expect(prefs.getString('app_theme'), isNull);
        expect(
          prefs.getBool('sources_presentation_defaults_copied_v1'),
          isNull,
        );
      });
    },
  );

  for (final create in [true, false]) {
    for (final minutes in [5, 0]) {
      testWidgets(
        '0b ${create ? "create" : "edit"} writes timeout $minutes and resume lock',
        (t) async {
          await editProfileCase(t, (f) async {
            final target = (await t.runAsync(
              () => f.profile('Target', timeout: 15),
            ))!;
            if (create && minutes == 0) {
              // Exercise clearing independently from nullable timeout seeding:
              // the existing registry authority callback models a staged-row
              // update before the editor's final metadata write.
              f.registry.authorityChangedCallback = () async {
                final staged =
                    (await f.registry.listProfiles(includeStaging: true))
                        .where(
                          (p) => p.lifecycle == UserProfileLifecycle.staging,
                        )
                        .firstOrNull;
                if (staged == null) return;
                f.registry.authorityChangedCallback = null;
                await f.registry.updateProfile(
                  id: staged.id,
                  inactivityTimeoutMinutes: 15,
                  actingProfileId: f.authorization.profileId,
                  actingAuthorizationRevision:
                      f.authorization.authorizationRevision,
                  actingSessionEpoch: f.authorization.sessionEpoch,
                );
              };
            }
            f.television = true;
            await f.mount(t, target: create ? null : target);
            await f.name(t, 'Timeout target');
            await autoLock(t, f, minutes == 0 ? 'Never' : 'After 5 minutes');
            await f.tap(t, find.text('Lock when the app resumes'));
            await f.save(t);
            await finished(t, f);
            expect(f.result, isTrue);
            final row = create
                ? (await t.runAsync(
                    () => f.registry.listProfiles(),
                  ))!.singleWhere(
                    (p) => p.id != target.id && p.id != f.admin.id,
                  )
                : (await t.runAsync(() => f.registry.getProfile(target.id)))!;
            expect(row.inactivityTimeoutMinutes, minutes == 0 ? null : minutes);
            expect(row.lockOnResume, isTrue);
          });
        },
      );
    }
  }

  testWidgets(
    '0b returning to stored role restores displayed and persisted split policy',
    (t) async {
      await editProfileCase(t, (f) async {
        final stored = ProfilePolicy(enabled: {ProfileFeature.cloud});
        final target = (await t.runAsync(
          () => f.profile('Target', policy: stored),
        ))!;
        f.television = true;
        await f.mount(t, target: target);
        await role(t, f, 'child');
        await role(t, f, 'member');
        await f.section(t, 'pages');
        final dynamic downloads = t.widget(
          find.byKey(const ValueKey('tv-pages-downloads')),
        );
        expect(downloads.selected, isFalse);
        // Touch Downloads twice to make the currently displayed policy authoritative.
        final dynamic cloud = t.widget(
          find.byKey(const ValueKey('tv-pages-downloads')),
        );
        (cloud.onPressed as VoidCallback)();
        await t.pump();
        final dynamic cloudAgain = t.widget(
          find.byKey(const ValueKey('tv-pages-downloads')),
        );
        (cloudAgain.onPressed as VoidCallback)();
        await t.pump();
        await f.save(t);
        await finished(t, f);
        expect(f.result, isTrue);
        expect(
          (await t.runAsync(
            () => f.registry.getProfile(target.id),
          ))!.policy.encode(),
          stored.encode(),
        );
      });
    },
  );

  testWidgets(
    '0b edit role change resets download and remote pair follow seeds',
    (t) async {
      await editProfileCase(t, (f) async {
        final target = (await t.runAsync(
          () => f.profile('Target', policy: ProfilePolicy(enabled: {})),
        ))!;
        f.television = true;
        await f.mount(t, target: target);
        await role(t, f, 'admin');
        await f.section(t, 'pages');
        // Move Downloads and Remote away from their new-role defaults. Stale
        // old-role seeds would leave both paired capabilities enabled.
        for (final feature in ['downloads', 'remoteControl']) {
          final dynamic tile = t.widget(
            find.byKey(ValueKey('tv-pages-$feature')),
          );
          (tile.onPressed as VoidCallback)();
          await t.pump();
        }
        await f.save(t);
        await finished(t, f);
        expect(f.result, isTrue);
        final enabled = (await t.runAsync(
          () => f.registry.getProfile(target.id),
        ))!.policy.enabled;
        expect(enabled, isNot(contains(ProfileFeature.downloads)));
        expect(enabled, isNot(contains(ProfileFeature.recordings)));
        expect(enabled, isNot(contains(ProfileFeature.remoteTransfer)));
      });
    },
  );

  testWidgets(
    '0b phone role art tile and connection persist after picked image',
    (t) async {
      await editProfileCase(t, (f) async {
        final target = (await t.runAsync(() => f.profile('Phone target')))!;
        final resource = (await t.runAsync(() => f.resource('Phone Cloud')))!;
        expect(
          await t.runAsync(() => f.registry.getGrant(target.id, resource.id)),
          isNull,
        );
        f.picker.response = () async => FilePickerResult([
          PlatformFile(name: 'avatar.png', size: 0, bytes: editProfilePng()),
        ]);
        await f.mount(t, target: target, size: const Size(600, 1000));
        await f.name(t, 'Phone Kid');
        await f.tap(t, find.text('Choose image or GIF (this device only)'));
        await f.until(
          t,
          () => find.text('Discard picked image').evaluate().isNotEmpty,
        );
        await f.tap(t, find.byTooltip('child'));
        expect(find.text('Discard picked image'), findsNothing);
        await f.tap(t, find.text('Kid'));
        await t.scrollUntilVisible(
          find.text('Phone Cloud'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await f.tap(t, find.text('Phone Cloud'));
        expect(f.checkbox(t, 'Phone Cloud').value, isTrue);
        await f.save(t);
        await finished(t, f);
        expect(f.result, isTrue);
        final created = (await t.runAsync(
          () => f.registry.getProfile(target.id),
        ))!;
        expect(created.role, UserProfileRole.child);
        expect(created.avatarKey, 'child');
        expect(
          (await t.runAsync(
            () => f.registry.getGrant(created.id, resource.id),
          ))!.allows(ResourcePermission.use),
          isTrue,
        );
      });
    },
  );

  testWidgets('0b phone AppBar Save disables during real held PIN write', (
    t,
  ) async {
    await editProfileCase(t, (f) async {
      final target = (await t.runAsync(() => f.profile('Target')))!;
      await f.mount(t, target: target);
      await f.pin(t, '1234');
      f.pins.release = Completer<void>();
      await f.save(t);
      await f.until(t, () => f.pins.written);
      final button = t.widget<TextButton>(
        find.ancestor(of: find.text('Save'), matching: find.byType(TextButton)),
      );
      try {
        expect(
          button.onPressed,
          isNull,
          reason: 'AppBar is outside AbsorbPointer; Save must disable',
        );
        expect(t.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
        expect(f.popped, isFalse);
      } finally {
        f.pins.release!.complete();
      }
      await f.until(t, () => find.text('I saved it').evaluate().isNotEmpty);
      await f.tap(t, find.text('I saved it'));
      await f.until(t, () => f.popped);
      expect(f.result, isTrue);
    });
  });
}
