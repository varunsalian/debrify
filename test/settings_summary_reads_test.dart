import 'dart:async';
import 'dart:io';

import 'package:debrify/screens/settings/settings_summary_reads.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/screens/settings_screen.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_lifecycle.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('diagnostic failure cannot reject a summary fallback', () async {
    final reads = SettingsSummaryReads(
      onFailure: (_, _) => throw StateError('diagnostics unavailable'),
    );
    expect(
      await reads.read<bool>(
        'IPTV',
        () => throw const ResourceAuthorizationException(
          'Resource is unavailable',
        ),
        false,
      ),
      isFalse,
    );
    expect(reads.unavailable, {'IPTV'});
  });
  test(
    'parallel summaries isolate authorization and synchronous failures',
    () async {
      final seen = <String>[];
      final reads = SettingsSummaryReads(
        onFailure: (label, _) => seen.add(label),
      );
      final slow = Completer<int>();
      final results = Future.wait<Object?>([
        reads.read('Healthy', () => slow.future, 0),
        reads.read<bool>('IPTV', () async {
          throw const ResourceAuthorizationException(
            'Connection authority changed',
          );
        }, false),
        reads.read<String>(
          'Version',
          () => throw StateError('read failed'),
          'Unavailable',
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(reads.failures, {'IPTV', 'Version'});
      expect(reads.unavailable, {'IPTV'});
      slow.complete(42);
      expect(await results, [42, false, 'Unavailable']);
      expect(seen, containsAll(['IPTV', 'Version']));
    },
  );

  for (final session in [
    'legacy',
    'member',
    'same-ID Settings join',
    'never-completing read',
  ]) {
    final memberSession = session == 'member';
    final committedSession =
        session == 'member' || session == 'same-ID Settings join';
    final neverCompletes = session == 'never-completing read';
    testWidgets('a denied summary renders after $session', (tester) async {
      SharedPreferences.setMockInitialValues({});
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      addTearDown(ProfileRuntime.debugReset);
      PackageInfo.setMockInitialValues(
        appName: 'Debrify',
        packageName: 'test.debrify',
        version: '1.0',
        buildNumber: '1',
        buildSignature: '',
      );
      Future<void> Function()? joinWhileMounted;
      Future<Object?> Function() deniedRead = () async =>
          throw const ResourceAuthorizationException('secret sentinel');
      if (committedSession) {
        await tester.runAsync(() async {
          sqfliteFfiInit();
          databaseFactory = databaseFactoryFfi;
          final directory = await Directory.systemTemp.createTemp(
            'settings-member-',
          );
          final registry = await ProfileRegistry.open(
            path: '${directory.path}/profiles.db',
          );
          final admin = await registry.createProfile(
            name: 'Admin',
            role: UserProfileRole.admin,
          );
          final member = await registry.createProfile(
            name: 'Member',
            role: UserProfileRole.member,
          );
          await registry.commitBootstrap(
            activeProfileId: admin.id,
            migratedLegacyInstall: false,
          );
          final cipher = MemoryDeviceSecretCipher(List<int>.filled(32, 9));
          await cipher.initialize();
          DeviceKeyProvider.debugInstallCipher(cipher);
          ProfileBootstrap.debugInstallRegistry(registry);
          ProfileRuntime.initializeCommitted(
            ProfileScope(
              profileId: admin.id,
              dataGeneration: 1,
              sessionEpoch: 1,
            ),
          );
          final resources = ConnectionResourceService(
            registry: registry,
            cipher: cipher,
          );
          final resource = await resources.create(
            context: await ProfileAuthorizationContext.capture(registry),
            type: ConnectionResourceType.iptvM3u,
            label: 'Owner playlist',
            publicConfig: const {},
            secretConfig: const {'url': 'https://example.invalid/list.m3u'},
          );
          if (memberSession) {
            // Shareable resources receive default use grants. Revoke the
            // member's grant so this exercises authorization denial, not a
            // successful resource descriptor cast to a playlist list.
            await resources.revokeGrant(
              actor: await ProfileAuthorizationContext.capture(registry),
              targetProfileId: member.id,
              resourceId: resource.id,
            );
          }
          final lifecycle = ProfileLifecycleCoordinator(registry: registry);
          addTearDown(lifecycle.dispose);
          Future<void> handoff() async {
            final before = ProfileRuntime.capture();
            await lifecycle.switchTo(
              memberSession ? member.id : admin.id,
              afterDeactivateBeforeCommit: () async {},
            );
            expect(
              ProfileRuntime.capture().sessionEpoch,
              greaterThan(before.sessionEpoch),
            );
            await (await ProfileAuthorizationContext.capture(
              registry,
            )).validate(registry);
          }

          if (memberSession) {
            await handoff();
          } else {
            joinWhileMounted = handoff;
          }
          if (memberSession) {
            deniedRead = () async => resources.authorize(
              context: await ProfileAuthorizationContext.capture(registry),
              resourceId: resource.id,
              permission: ResourcePermission.use,
              feature: ProfileFeature.iptv,
            );
          }
          addTearDown(() async {
            ProfileBootstrap.debugInstallRegistry(null);
            DeviceKeyProvider.debugReset();
            await registry.close();
            await directory.delete(recursive: true);
          });
        });
      }
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final theme = AppThemes.byId('spotlight');
      await tester.pumpWidget(
        MaterialApp(
          home: AppThemeScope(
            theme: theme,
            child: Scaffold(
              // Exercise the same epoch remount contract as ProfileGate while
              // keeping unrelated startup/network work outside this UI test.
              body: ValueListenableBuilder<ProfileScope?>(
                valueListenable: ProfileRuntime.scope,
                builder: (context, scope, _) => SettingsScreen(
                  key: ValueKey(scope?.sessionEpoch),
                  summaryReadOverrides: {
                    'IPTV': neverCompletes
                        ? () => Completer<Object?>().future
                        : deniedRead,
                    'Pending credentials': () async => <ConnectionResourceType>{
                      ConnectionResourceType.torbox,
                    },
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(SettingsSkeleton), findsOneWidget);
      if (joinWhileMounted != null) {
        final retiredState = tester.state(find.byType(SettingsScreen));
        await tester.runAsync(joinWhileMounted!);
        await tester.pump();
        expect(
          tester.state(find.byType(SettingsScreen)),
          isNot(same(retiredState)),
        );
      }
      // Avoid pumpAndSettle: the skeleton deliberately animates forever if the
      // regression returns. A bounded pump makes this a useful failure signal.
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SettingsSkeleton), findsNothing);
      final notice = tester.widget<Text>(
        find.byKey(const ValueKey('settings-summary-attention')),
      );
      expect(
        notice.data,
        "Some items couldn't load — open them to retry or sign in.",
      );
      expect(find.text('Real Debrid'), findsWidgets);
      // This layout renders ConnectionCards straight from the loaded
      // ConnectionInfo rather than placing the ConnectionsSummary widget, so
      // assert the per-item outcome on the cards that are actually in the
      // tree (offstage included: the detail pane may be off-screen here).
      final infos = tester
          .widgetList<ConnectionCard>(
            find.byType(ConnectionCard, skipOffstage: false),
          )
          .map((card) => card.info)
          .toList();
      final torbox = infos.singleWhere((info) => info.title == 'Torbox');
      expect(torbox.connected, isTrue);
      expect(torbox.caption, 'credentials pending owner sign-in');
      final iptv = infos.singleWhere((info) => info.title == 'IPTV');
      expect(iptv.connected, isFalse);
      final realDebrid = infos.singleWhere(
        (info) => info.title == 'Real Debrid',
      );
      expect(iptv.status, 'Attention');
      expect(
        iptv.caption,
        neverCompletes
            ? 'Unable to load; open the item to retry'
            : 'Unavailable; retry or sign in',
      );
      expect(realDebrid.status, isNot('Attention'));
      expect(notice.data, isNot(contains('secret sentinel')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
