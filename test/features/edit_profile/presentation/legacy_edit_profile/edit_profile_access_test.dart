import 'dart:async';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/edit_profile_fixture.dart';

void main() {
  testWidgets(
    'O target grants engines identity and lock leave admin unchanged',
    (t) async {
      await editProfileCase(t, (f) async {
        final target = (await t.runAsync(
          () => f.profile(
            'Target',
            policy: ProfilePolicy(
              enabled: {ProfileFeature.downloads, ProfileFeature.cloud},
            ),
          ),
        ))!;
        final resources = (await t.runAsync(() async {
          await f.engine(f.admin, 'alpha', 'Alpha engine');
          await f.engine(f.admin, 'beta', 'Beta engine');
          return [await f.resource('Cloud A'), await f.resource('Cloud B')];
        }))!;
        f.television = true;
        await f.mount(t, target: target);
        await f.name(t, 'Target saved');
        await f.section(t, 'lock');
        t.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged!(true);
        await t.pump();
        await f.tap(t, find.text('Never'));
        await f.tap(t, find.text('After 5 minutes'));
        await f.section(t, 'access');
        await f.check(t, 'Cloud A', true);
        await f.check(t, 'Cloud B', true);
        await f.check(t, 'Alpha engine', true);
        await f.save(t);
        await f.until(t, () => f.popped);
        final row = (await t.runAsync(() => f.registry.getProfile(target.id)))!;
        expect(row.name, 'Target saved');
        expect(row.lockOnResume, isTrue);
        expect(row.inactivityTimeoutMinutes, 5);
        expect(await t.runAsync(() => f.engines(target.id)), {
          'alpha': 'name: Alpha engine\nsource: original_alpha\n',
        });
        expect(await t.runAsync(() => f.engines(f.admin.id)), hasLength(2));
        for (final resource in resources) {
          final storedGrant = await t.runAsync(
            () => f.registry.getGrant(target.id, resource.id),
          );
          expect(storedGrant, isNotNull, reason: 'grant persisted on target');
          final grant = storedGrant!;
          expect(grant.allows(ResourcePermission.use), isTrue);
          expect(grant.allows(ResourcePermission.download), isTrue);
          expect(grant.allows(ResourcePermission.writeRemote), isFalse);
        }
        expect(
          (await t.runAsync(() => f.registry.getProfile(f.admin.id)))!.name,
          'Managing Admin',
        );
        expect(f.reloads, 0);
      });
    },
  );
  testWidgets(
    'O newly selected mask derives use download and writeRemote from target policy',
    (t) async {
      await editProfileCase(t, (f) async {
        final target = (await t.runAsync(
          () => f.profile(
            'Target',
            policy: ProfilePolicy(
              enabled: {
                ProfileFeature.downloads,
                ProfileFeature.remoteTransfer,
                ProfileFeature.remoteControl,
              },
            ),
          ),
        ))!;
        final resource = (await t.runAsync(() => f.resource('Cloud A')))!;
        f.television = true;
        await f.mount(t, target: target);
        await f.section(t, 'access');
        await f.check(t, 'Cloud A', true);
        await f.save(t);
        await f.until(t, () => f.popped);
        final grant = (await t.runAsync(
          () => f.registry.getGrant(target.id, resource.id),
        ))!;
        for (final permission in [
          ResourcePermission.use,
          ResourcePermission.download,
          ResourcePermission.writeRemote,
        ]) {
          expect(
            grant.allows(permission),
            isTrue,
            reason: 'derived $permission',
          );
        }
      });
    },
  );
  testWidgets('O grant refresh supports active Admin singleton rebinding', (
    t,
  ) async {
    await editProfileCase(t, (f) async {
      final owner = (await t.runAsync(
        () => f.profile('Source owner', role: UserProfileRole.admin),
      ))!;
      final resources = (await t.runAsync(() async {
        await f.activate(owner);
        await f.refreshActor();
        final a = await f.resource(
          'TorBox A',
          type: ConnectionResourceType.torbox,
        );
        final b = await f.resource(
          'TorBox B',
          type: ConnectionResourceType.torbox,
        );
        await f.grant(f.admin, a, {
          ResourcePermission.use,
          ResourcePermission.share,
        });
        await f.grant(f.admin, b, {
          ResourcePermission.use,
          ResourcePermission.share,
        });
        await f.activate(f.admin);
        await f.refreshActor();
        return [a, b];
      }))!;
      f.television = true;
      await f.mount(t, target: f.admin);
      await f.save(t);
      await f.until(t, () => f.popped);
      expect(
        f.result,
        isTrue,
        reason: 'refresh after each active-profile grant',
      );
      for (final resource in resources) {
        expect(
          await t.runAsync(() => f.registry.getGrant(f.admin.id, resource.id)),
          isNotNull,
        );
      }
      expect(
        await t.runAsync(
          () => f.registry.getBoundResourceId(
            f.admin.id,
            ConnectionResourceType.torbox.singletonCredentialBindingSlot!,
          ),
        ),
        resources.last.id,
      );
    });
  });
  testWidgets(
    'O session switch after PIN keeps earlier writes and rejects grants engines',
    (t) async {
      await editProfileCase(t, (f) async {
        final target = (await t.runAsync(() => f.profile('Target')))!;
        final incoming = (await t.runAsync(
          () => f.profile('Incoming', role: UserProfileRole.admin),
        ))!;
        final resource = (await t.runAsync(() async {
          await f.engine(f.admin, 'alpha', 'Alpha engine');
          return f.resource('Cloud A');
        }))!;
        await t.runAsync(
          () => f.grant(incoming, resource, {
            ResourcePermission.use,
            ResourcePermission.share,
          }),
        );
        f.television = true;
        await f.mount(t, target: target);
        await f.name(t, 'Before switch');
        await f.section(t, 'access');
        await f.check(t, 'Cloud A', true);
        await f.check(t, 'Alpha engine', true);
        await f.pin(t, '1234');
        f.pins.release = Completer<void>();
        await f.save(t);
        await f.until(t, () => f.pins.written);
        await t.runAsync(() => f.activate(incoming));
        f.pins.release!.complete();
        await f.until(
          t,
          () => find.text('Could not save this profile').evaluate().isNotEmpty,
        );
        final row = (await t.runAsync(() => f.registry.getProfile(target.id)))!;
        expect(row.name, 'Before switch');
        expect(row.hasPin, isTrue);
        expect(
          await t.runAsync(() => f.registry.getGrant(target.id, resource.id)),
          isNull,
        );
        expect(await t.runAsync(() => f.engines(target.id)), isEmpty);
        expect(await t.runAsync(() => f.engines(incoming.id)), isEmpty);
        expect(await t.runAsync(() => f.engines(f.admin.id)), hasLength(1));
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
          isFalse,
        );
      });
    },
  );
  testWidgets(
    'O captured selection snapshot survives callback after PIN await',
    (t) async {
      await editProfileCase(t, (f) async {
        final target = (await t.runAsync(() => f.profile('Target')))!;
        final resource = (await t.runAsync(() => f.resource('Cloud A')))!;
        f.television = true;
        await f.mount(t, target: target);
        await f.section(t, 'access');
        final toggle = f.checkbox(t, 'Cloud A').onChanged!;
        toggle(true);
        await t.pump();
        await f.pin(t, '1234');
        f.pins.release = Completer<void>();
        await f.save(t);
        await f.until(t, () => f.pins.written);
        toggle(false);
        await t.pump();
        f.pins.release!.complete();
        await f.until(t, () => find.text('I saved it').evaluate().isNotEmpty);
        expect(
          await t.runAsync(() => f.registry.getGrant(target.id, resource.id)),
          isNotNull,
          reason: 'snapshot selection after await',
        );
        await f.tap(t, find.text('I saved it'));
        await f.until(t, () => f.popped);
      });
    },
  );
  testWidgets('O existing mask no churn and reselect keeps stored permission', (
    t,
  ) async {
    await editProfileCase(t, (f) async {
      final target = (await t.runAsync(
        () => f.profile('Target', policy: ProfilePolicy(enabled: {})),
      ))!;
      final resource = (await t.runAsync(() => f.resource('Cloud A')))!;
      await t.runAsync(
        () => f.grant(target, resource, {
          ResourcePermission.use,
          ResourcePermission.writeRemote,
        }),
      );
      final before = (await t.runAsync(
        () => f.registry.getGrant(target.id, resource.id),
      ))!;
      var writes = 0;
      f.registry.authorityWillChangeCallback = () async {
        writes++;
      };
      f.television = true;
      await f.mount(t, target: target);
      await f.section(t, 'access');
      await f.check(t, 'Cloud A', false);
      await f.check(t, 'Cloud A', true);
      await f.save(t);
      await f.until(t, () => f.popped);
      final after = (await t.runAsync(
        () => f.registry.getGrant(target.id, resource.id),
      ))!;
      expect(
        after.permissions,
        before.permissions,
        reason: 'putIfAbsent preserves explicit mask',
      );
      expect(writes, 1, reason: 'identity update only; no grant churn');
    });
  });
  testWidgets('O deselect revokes borrower grant', (t) async {
    await editProfileCase(t, (f) async {
      final target = (await t.runAsync(() => f.profile('Target')))!;
      final resource = (await t.runAsync(() => f.resource('Cloud A')))!;
      await t.runAsync(
        () => f.grant(target, resource, {ResourcePermission.use}),
      );
      f.television = true;
      await f.mount(t, target: target);
      await f.section(t, 'access');
      await f.check(t, 'Cloud A', false);
      await f.save(t);
      await f.until(t, () => f.popped);
      expect(
        await t.runAsync(() => f.registry.getGrant(target.id, resource.id)),
        isNull,
      );
    });
  });
  testWidgets(
    'O owned connection cannot toggle or revoke and read-only TV row focuses',
    (t) async {
      await editProfileCase(t, (f) async {
        final resource = (await t.runAsync(() => f.resource('Owned Cloud')))!;
        f.television = true;
        await f.mount(t, target: f.admin);
        await f.section(t, 'access');
        expect(f.checkbox(t, 'Owned Cloud').onChanged, isNull);
        final focus = find
            .descendant(
              of: find.byKey(ValueKey('tv-profile-connection-${resource.id}')),
              matching: find.byType(Focus),
            )
            .first;
        final node = Focus.of(
          t.element(
            find
                .descendant(of: focus, matching: find.byType(AnimatedContainer))
                .first,
          ),
        );
        node.requestFocus();
        await t.pump();
        expect(node.hasFocus, isTrue);
        await f.save(t);
        await f.until(t, () => f.popped);
        expect(
          await t.runAsync(() => f.registry.getGrant(f.admin.id, resource.id)),
          isNotNull,
        );
      });
    },
  );
  testWidgets(
    'O formerly editable callback cannot revoke newly owned connection',
    (t) async {
      await editProfileCase(t, (f) async {
        final target = (await t.runAsync(
          () => f.profile('Target', role: UserProfileRole.admin),
        ))!;
        final resource = (await t.runAsync(() => f.resource('Cloud A')))!;
        f.television = true;
        await f.mount(t, target: target);
        await f.section(t, 'access');
        final toggle = f.checkbox(t, 'Cloud A').onChanged!;
        toggle(true);
        await t.pump();
        await f.tap(t, find.byTooltip('Transfer ownership to this profile'));
        await f.tap(t, find.text('Transfer'));
        await f.until(
          t,
          () => find
              .text('Connection ownership transferred')
              .evaluate()
              .isNotEmpty,
        );
        toggle(false);
        await t.pump();
        await f.save(t);
        await f.until(t, () => f.popped);
        expect(
          (await t.runAsync(
            () => f.registry.getResource(resource.id),
          ))!.ownerProfileId,
          target.id,
        );
        expect(
          await t.runAsync(() => f.registry.getGrant(target.id, resource.id)),
          isNotNull,
        );
      });
    },
  );
  testWidgets('R singleton rivals deselect through group All and None', (
    t,
  ) async {
    await editProfileCase(t, (f) async {
      final target = (await t.runAsync(() => f.profile('Target')))!;
      await t.runAsync(() async {
        await f.resource('TorBox A', type: ConnectionResourceType.torbox);
        await f.resource('TorBox B', type: ConnectionResourceType.torbox);
      });
      f.television = true;
      await f.mount(t, target: target);
      await f.section(t, 'access');
      await f.tap(t, find.text('All').last);
      expect(f.checkbox(t, 'TorBox A').value, isFalse);
      expect(f.checkbox(t, 'TorBox B').value, isTrue);
      await f.tap(t, find.text('None').last);
      expect(f.checkbox(t, 'TorBox B').value, isFalse);
    });
  });
  testWidgets('O engine All then None persists empty independent generation', (
    t,
  ) async {
    await editProfileCase(t, (f) async {
      final target = (await t.runAsync(() => f.profile('Target')))!;
      await t.runAsync(() async {
        await f.engine(f.admin, 'alpha', 'Alpha engine');
        await f.engine(target, 'beta', 'Beta engine');
      });
      f.television = true;
      await f.mount(t, target: target);
      await f.section(t, 'access');
      await f.tap(t, find.text('All').first);
      expect(f.checkbox(t, 'Alpha engine').value, isTrue);
      expect(f.checkbox(t, 'Beta engine').value, isTrue);
      await f.tap(t, find.text('None').first);
      await f.save(t);
      await f.until(t, () => f.popped);
      expect(await t.runAsync(() => f.engines(target.id)), isEmpty);
      expect(await t.runAsync(() => f.engines(f.admin.id)), hasLength(1));
    });
  });
  testWidgets('R own editor engine controls are read-only', (t) async {
    await editProfileCase(t, (f) async {
      await t.runAsync(() => f.engine(f.admin, 'alpha', 'Alpha engine'));
      f.television = true;
      await f.mount(t, target: f.admin);
      await f.section(t, 'access');
      expect(f.checkbox(t, 'Alpha engine').onChanged, isNull);
      expect(find.text('All'), findsNothing);
      expect(find.text('None'), findsNothing);
    });
  });
  for (final choice in ['confirm', 'cancel', 'session']) {
    testWidgets('O transfer $choice preserves owner and result', (t) async {
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
        late Future<void> transferDone;
        await t.runAsync(() async {
          final dynamic start = t
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) =>
                      w is IconButton &&
                      w.tooltip == 'Transfer ownership to this profile',
                ),
              )
              .onPressed;
          transferDone = start() as Future<void>;
        });
        await f.settle(t);
        expect(find.text('Transfer connection ownership?'), findsOneWidget);
        if (choice == 'session') {
          final incoming = (await t.runAsync(
            () => f.profile('Incoming', role: UserProfileRole.admin),
          ))!;
          await t.runAsync(() => f.activate(incoming));
        }
        await f.tap(t, find.text(choice == 'cancel' ? 'Cancel' : 'Transfer'));
        await t.runAsync(() => transferDone);
        await t.pump();
        if (choice != 'cancel') {
          await f.until(
            t,
            () => find
                .text(
                  choice == 'confirm'
                      ? 'Connection ownership transferred'
                      : 'Connection could not be transferred',
                )
                .evaluate()
                .isNotEmpty,
          );
        }
        expect(
          (await t.runAsync(
            () => f.registry.getResource(resource.id),
          ))!.ownerProfileId,
          choice == 'confirm' ? target.id : f.admin.id,
        );
      });
    });
  }
  for (final fails in [false, true]) {
    testWidgets(
      'O admin PIN reset ${fails ? "fails" : "succeeds"} with correct snackbar',
      (t) async {
        await editProfileCase(t, (f) async {
          final target = (await t.runAsync(() => f.profile('Target')))!;
          await t.runAsync(() async {
            await f.pins.setPinAsAdmin(
              actor: f.authorization,
              targetProfileId: target.id,
              pin: '1234',
            );
            await f.refreshActor();
          });
          final fresh = (await t.runAsync(
            () => f.registry.getProfile(target.id),
          ))!;
          f.pins.failRemove = fails;
          f.television = true;
          await f.mount(t, target: fresh);
          await f.section(t, 'lock');
          await f.tap(t, find.text('Admin reset: remove PIN'));
          await f.until(
            t,
            () => find
                .text(
                  fails
                      ? 'PIN protection was not changed'
                      : 'PIN protection removed',
                )
                .evaluate()
                .isNotEmpty,
          );
          expect(
            (await t.runAsync(() => f.registry.getProfile(target.id)))!.hasPin,
            fails,
          );
        });
      },
    );
  }
  testWidgets('R PIN reset absent without PIN or reset requirement', (t) async {
    await editProfileCase(t, (f) async {
      f.television = true;
      await f.mount(t);
      await f.section(t, 'lock');
      expect(find.text('Admin reset: remove PIN'), findsNothing);
    });
  });
}
