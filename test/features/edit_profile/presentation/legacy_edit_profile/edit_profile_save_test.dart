import 'dart:async';
import 'dart:io';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/services/profiles/profile_engine_assignment_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/widgets/profiles/profile_avatar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/edit_profile_fixture.dart';

void main() {
  testWidgets('R create seeds member defaults and person avatar', (t) async {
    await editProfileCase(t, (f) async {
      f.television = true;
      await f.mount(t);
      final preview = t.widget<ProfileAvatarView>(
        find.byType(ProfileAvatarView).first,
      );
      expect(preview.avatarKey, 'person', reason: 'original create avatar');
      expect(find.text('Member'), findsWidgets);
      await f.section(t, 'pages');
      expect(find.byKey(const ValueKey('tv-pages-downloads')), findsOneWidget);
    });
  });
  testWidgets('R edit seeds stored lock timeout avatar and child fallback', (
    t,
  ) async {
    await editProfileCase(t, (f) async {
      final target = (await t.runAsync(
        () => f.profile(
          'Kid',
          role: UserProfileRole.child,
          avatar: 'child',
          lock: true,
          timeout: 15,
        ),
      ))!;
      f.television = true;
      await f.mount(t, target: target);
      expect(
        t
            .widget<ProfileAvatarView>(find.byType(ProfileAvatarView).first)
            .avatarKey,
        'child',
      );
      await f.section(t, 'lock');
      expect(
        t.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(find.text('After 15 minutes'), findsOneWidget);
    });
  });
  testWidgets('R nullable legacy Kid avatar uses child fallback', (t) async {
    await editProfileCase(t, (f) async {
      final stored = (await t.runAsync(
        () => f.profile('Kid', role: UserProfileRole.child),
      ))!;
      final target = UserProfile(
        id: stored.id,
        name: stored.name,
        role: stored.role,
        policy: stored.policy,
        authorizationRevision: stored.authorizationRevision,
        lifecycle: stored.lifecycle,
        visibleDataGeneration: stored.visibleDataGeneration,
        setupComplete: stored.setupComplete,
        pinResetRequired: stored.pinResetRequired,
        hasPin: stored.hasPin,
        lockOnResume: stored.lockOnResume,
        createdAt: stored.createdAt,
        updatedAt: stored.updatedAt,
      );
      f.television = true;
      await f.mount(t, target: target);
      expect(
        t
            .widget<ProfileAvatarView>(find.byType(ProfileAvatarView).first)
            .avatarKey,
        'child',
        reason: 'nullable child fallback',
      );
    });
  });
  testWidgets('R disposed held setup publishes nothing', (t) async {
    await editProfileCase(t, (f) async {
      final hold =
          Completer<
            (List<ConnectionResource>, List<ProfileEngineAssignment>)
          >();
      var started = false;
      f.television = true;
      await f.mount(
        t,
        loader: () {
          started = true;
          return hold.future;
        },
        wait: false,
      );
      await f.until(t, () => started);
      await t.pumpWidget(const SizedBox());
      hold.complete((<ConnectionResource>[], <ProfileEngineAssignment>[]));
      await f.settle(t);
      expect(t.takeException(), isNull, reason: 'original mounted load guard');
      expect(find.text('Profile access'), findsNothing);
    });
  });
  for (final stale in [true, false]) {
    testWidgets(
      'R ${stale ? "stale authorization" : "non-admin actor"} load error refuses save',
      (t) async {
        await editProfileCase(t, (f) async {
          final target = (await t.runAsync(
            () => f.profile(
              'Incoming',
              role: stale ? UserProfileRole.admin : UserProfileRole.member,
            ),
          ))!;
          await t.runAsync(() => f.activate(target));
          if (!stale) await t.runAsync(f.refreshActor);
          f.television = true;
          await f.mount(
            t,
            loader: () async =>
                (<ConnectionResource>[], <ProfileEngineAssignment>[]),
          );
          await f.name(t, 'Rejected');
          await f.section(t, 'access');
          expect(
            find.text('Profile options could not be loaded'),
            findsOneWidget,
          );
          await f.save(t);
          await f.settle(t);
          expect(
            find.text('Profile options could not be loaded'),
            findsNWidgets(2),
          );
          expect(
            await t.runAsync(() => f.registry.listProfiles()),
            hasLength(2),
          );
        });
      },
    );
  }
  testWidgets('R empty name is a no-op', (t) async {
    await editProfileCase(t, (f) async {
      await f.mount(t);
      await f.save(t);
      await f.settle(t);
      expect(f.popped, isFalse);
      expect(find.byType(SnackBar), findsNothing);
      expect(await t.runAsync(() => f.registry.listProfiles()), hasLength(1));
    });
  });
  testWidgets('R held options reports loading before writes', (t) async {
    await editProfileCase(t, (f) async {
      final hold =
          Completer<
            (List<ConnectionResource>, List<ProfileEngineAssignment>)
          >();
      await f.mount(t, loader: () => hold.future, wait: false);
      await f.name(t, 'Loading');
      await f.save(t);
      expect(find.text('Profile options are still loading'), findsOneWidget);
      expect(await t.runAsync(() => f.registry.listProfiles()), hasLength(1));
      hold.complete((<ConnectionResource>[], <ProfileEngineAssignment>[]));
      await f.settle(t);
    });
  });
  testWidgets('R short PIN refuses save', (t) async {
    await editProfileCase(t, (f) async {
      await f.mount(t);
      await f.name(t, 'Short PIN');
      await f.pin(t, '123');
      await f.save(t);
      expect(find.text('PIN must contain 4–8 digits'), findsOneWidget);
      expect(f.pins.targets, isEmpty);
    });
  });
  testWidgets('O create publishes fields and pops true', (t) async {
    await editProfileCase(t, (f) async {
      await f.mount(t);
      await f.name(t, ' New profile ');
      await f.save(t);
      await f.until(t, () => f.popped);
      final rows = (await t.runAsync(
        () => f.registry.listProfiles(includeStaging: true),
      ))!;
      final created = rows.singleWhere((p) => p.id != f.admin.id);
      expect(created.name, 'New profile');
      expect(created.role, UserProfileRole.member);
      expect(
        created.policy.enabled,
        ProfilePolicy.defaultsFor(UserProfileRole.member).enabled,
      );
      expect(created.avatarKey, 'person');
      expect(created.setupComplete, isTrue);
      expect(created.lifecycle, UserProfileLifecycle.active);
      expect(f.result, isTrue);
    });
  });
  testWidgets('O create PIN recovery precedes pop', (t) async {
    await editProfileCase(t, (f) async {
      await f.mount(t);
      await f.name(t, 'Protected');
      await f.pin(t, '1234');
      await f.save(t);
      await f.until(t, () => find.text('I saved it').evaluate().isNotEmpty);
      expect(f.popped, isFalse);
      expect(find.byType(SelectableText), findsOneWidget);
      final dialog = t.widget<ModalBarrier>(find.byType(ModalBarrier).last);
      expect(dialog.dismissible, isFalse);
      final row = (await t.runAsync(
        () => f.registry.getProfile(f.pins.targets.single),
      ))!;
      expect(row.hasPin, isTrue);
      await f.tap(t, find.text('I saved it'));
      await f.until(t, () => f.popped);
      expect(f.result, isTrue);
    });
  });
  for (final beforeCompletion in [false, true]) {
    testWidgets(
      'O create ${beforeCompletion ? "completion" : "PIN"} failure rolls back rows and avatar bytes',
      (t) async {
        await editProfileCase(t, (f) async {
          var ordinal = 0;
          String? staged;
          f.registry.authorityWillChangeCallback = () async {
            ordinal++;
            final rows = await f.registry.listProfiles(includeStaging: true);
            staged =
                rows.where((p) => p.id != f.admin.id).firstOrNull?.id ?? staged;
            if (beforeCompletion && ordinal == 4) {
              throw StateError('fixture before completion');
            }
          };
          f.pins.failSet = !beforeCompletion;
          f.picker.response = () async => FilePickerResult([
            PlatformFile(name: 'avatar.png', size: 0, bytes: editProfilePng()),
          ]);
          await f.mount(t);
          await f.tap(t, find.text('Choose image or GIF (this device only)'));
          await f.until(
            t,
            () => find.text('Discard picked image').evaluate().isNotEmpty,
          );
          await f.name(t, 'Rollback');
          await f.pin(t, '1234');
          await f.save(t);
          await f.until(
            t,
            () =>
                find.text('Could not save this profile').evaluate().isNotEmpty,
          );
          staged ??= f.pins.targets.firstOrNull;
          expect(
            staged,
            isNotNull,
            reason: 'staged row reached failure boundary',
          );
          expect(
            await t.runAsync(() => f.registry.getProfile(staged!)),
            isNull,
            reason: 'rollback removes staged row',
          );
          expect(
            await t.runAsync(
              () => f.registry.listProfiles(includeStaging: true),
            ),
            hasLength(1),
          );
          expect(
            await t.runAsync(
              () => Directory('${f.root.path}/profiles/$staged').exists(),
            ),
            isFalse,
          );
          expect(f.popped, isFalse);
        });
      },
    );
  }
  for (final failures in [1, 2, 0]) {
    testWidgets(
      'O published checkpoint failures $failures retain or finalize intent',
      (t) async {
        await editProfileCase(t, (f) async {
          var attempts = 0;
          String? saved;
          f.registry.authorityChangedCallback = () async {
            final rows = await f.registry.listProfiles(includeStaging: true);
            final created = rows.where((p) => p.id != f.admin.id).firstOrNull;
            if (created?.lifecycle != UserProfileLifecycle.active) return;
            saved = created!.id;
            attempts++;
            if (failures == 0) {
              for (final slot in ['', '.next']) {
                await Directory(
                  '${f.root.path}/profile-avatar-mutations-v1.json$slot.write.tmp',
                ).create();
              }
            } else if (attempts <= failures) {
              throw StateError('fixture checkpoint $attempts');
            }
          };
          await f.mount(t);
          await f.name(t, 'Published');
          await f.save(t);
          await f.until(
            t,
            () =>
                f.popped ||
                find.text('Could not save this profile').evaluate().isNotEmpty,
          );
          expect(saved, isNotNull);
          final persisted = await t.runAsync(
            () => f.registry.getProfile(saved!),
          );
          expect(
            persisted,
            isNotNull,
            reason: 'published row survives checkpoint failure',
          );
          final row = persisted!;
          expect(row.lifecycle, UserProfileLifecycle.active);
          expect(row.setupComplete, isTrue);
          if (failures == 2) {
            expect(attempts, 2);
            expect(f.popped, isFalse);
            expect(await t.runAsync(f.avatarIntents), contains(saved!));
          } else {
            expect(f.result, isTrue);
            expect(attempts, failures == 1 ? 2 : 1);
            if (failures == 0) {
              expect(await t.runAsync(f.avatarIntents), contains(saved!));
            }
          }
        });
      },
    );
  }
  testWidgets('O identity edit preserves stored split policy on target', (
    t,
  ) async {
    await editProfileCase(t, (f) async {
      final policy = ProfilePolicy(
        enabled: {ProfileFeature.downloads, ProfileFeature.cloud},
      );
      final target = (await t.runAsync(
        () => f.profile('Target', policy: policy),
      ))!;
      await f.mount(t, target: target);
      await f.name(t, 'Renamed');
      await f.save(t);
      await f.until(t, () => f.popped);
      final row = (await t.runAsync(() => f.registry.getProfile(target.id)))!;
      expect(row.name, 'Renamed');
      expect(row.policy.encode(), policy.encode());
      expect(
        (await t.runAsync(() => f.registry.getProfile(f.admin.id)))!.name,
        'Managing Admin',
      );
      expect(f.reloads, 0);
    });
  });
  testWidgets('O role change saves defaults and clamped Kid policy', (t) async {
    await editProfileCase(t, (f) async {
      final target = (await t.runAsync(() => f.profile('Target')))!;
      f.television = true;
      await f.mount(t, target: target);
      final dynamic role = t.widget(
        find.byKey(const ValueKey('tv-profile-role-child')),
      );
      (role.onPressed as VoidCallback)();
      await t.pump();
      await f.save(t);
      await f.until(t, () => f.popped);
      final row = (await t.runAsync(() => f.registry.getProfile(target.id)))!;
      expect(row.role, UserProfileRole.child);
      expect(
        row.policy.enabled,
        ProfilePolicy.defaultsFor(UserProfileRole.child).enabled,
      );
      expect(
        row.policy.enabled,
        isNot(contains(ProfileFeature.remoteTransfer)),
      );
    });
  });
  testWidgets('O touched Pages downloads pair follows moved toggle', (t) async {
    await editProfileCase(t, (f) async {
      final target = (await t.runAsync(
        () => f.profile('Target', policy: ProfilePolicy(enabled: {})),
      ))!;
      f.television = true;
      await f.mount(t, target: target);
      await f.section(t, 'pages');
      final dynamic tile = t.widget(
        find.byKey(const ValueKey('tv-pages-downloads')),
      );
      (tile.onPressed as VoidCallback)();
      await t.pump();
      await f.save(t);
      await f.until(t, () => f.popped);
      final row = (await t.runAsync(() => f.registry.getProfile(target.id)))!;
      expect(row.policy.enabled, {
        ProfileFeature.downloads,
        ProfileFeature.recordings,
      });
    });
  });
  testWidgets(
    'O touched Kid Remote clamps paired transfer before persisted comparison',
    (t) async {
      await editProfileCase(t, (f) async {
        final target = (await t.runAsync(
          () => f.profile(
            'Kid',
            role: UserProfileRole.child,
            policy: ProfilePolicy(enabled: {}),
          ),
        ))!;
        f.television = true;
        await f.mount(t, target: target);
        await f.section(t, 'pages');
        final dynamic tile = t.widget(
          find.byKey(const ValueKey('tv-pages-remoteControl')),
        );
        (tile.onPressed as VoidCallback)();
        await t.pump();
        await f.save(t);
        await f.until(t, () => f.popped);
        final row = (await t.runAsync(() => f.registry.getProfile(target.id)))!;
        expect(row.policy.enabled, {ProfileFeature.remoteControl});
        expect(f.result, isTrue);
      });
    },
  );
  testWidgets(
    'O own-profile reload exactly once and double Save accepted once',
    (t) async {
      await editProfileCase(t, (f) async {
        await f.mount(t, target: f.admin);
        await f.name(t, 'Admin renamed');
        final hold = Completer<void>();
        var writes = 0;
        f.registry.authorityWillChangeCallback = () async {
          writes++;
          await hold.future;
        };
        final save = f.saveCallback(t);
        await t.runAsync(() async {
          save();
          save();
        });
        await f.until(t, () => writes > 0);
        try {
          expect(writes, 1, reason: 'one accepted save before registry write');
        } finally {
          hold.complete();
        }
        await f.until(t, () => f.popped);
        expect(writes, 1);
        expect(f.reloads, 1);
        expect(
          (await t.runAsync(() => f.registry.getProfile(f.admin.id)))!.name,
          'Admin renamed',
        );
      });
    },
  );
  testWidgets(
    'R held TV save locks focus pointer and pop then failure restores Save',
    (t) async {
      await editProfileCase(t, (f) async {
        final target = (await t.runAsync(() => f.profile('Target')))!;
        f.television = true;
        await f.mount(t, target: target);
        await f.pin(t, '1234');
        f.pins.release = Completer<void>();
        await f.save(t);
        await f.until(t, () => f.pins.written);
        expect(find.text('SAVING…'), findsOneWidget);
        final scope = t.widget<PopScope>(find.byType(PopScope));
        expect(scope.canPop, isFalse);
        expect(
          t
              .widget<AbsorbPointer>(
                find
                    .ancestor(
                      of: find.byKey(const ValueKey('tv-profile-save')),
                      matching: find.byType(AbsorbPointer),
                    )
                    .first,
              )
              .absorbing,
          isTrue,
        );
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Focus &&
                !w.descendantsAreFocusable &&
                !w.descendantsAreTraversable,
          ),
          findsOneWidget,
        );
        expect(await f.navigator.currentState!.maybePop(), isTrue);
        expect(f.popped, isFalse);
        final incoming = (await t.runAsync(
          () => f.profile('Incoming', role: UserProfileRole.admin),
        ))!;
        await t.runAsync(() => f.activate(incoming));
        f.pins.release!.complete();
        await f.until(
          t,
          () => find.text('Could not save this profile').evaluate().isNotEmpty,
        );
        await t.pump();
        expect(find.text('SAVE'), findsOneWidget);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Edit profile save',
          reason: 'failure restores rail Save',
        );
        expect(
          (await t.runAsync(() => f.registry.getProfile(target.id)))!.hasPin,
          isTrue,
        );
      });
    },
  );
}
