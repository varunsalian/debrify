import 'dart:async';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/addons/addon_hub_screen.dart';
import 'package:debrify/screens/profiles/profile_gate.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_active_profile_refresh.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../support/addon_hub_fixture.dart';
import '../../../../support/addon_hub_profiles.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  testWidgets(
    'real gate picker and same-profile switch dispose original hub resources',
    (t) async {
      await hubCase(t, (f) async {
        final p = AddonHubProfiles(f);
        await t.runAsync(p.open);
        await f.mount(
          t,
          home: const ProfileGate(child: Scaffold(body: Text('Gate child'))),
        );
        await f.until(t, () => find.text('A').evaluate().isNotEmpty);
        await f.tap(t, 'A');
        await f.until(t, () => find.text('Gate child').evaluate().isNotEmpty);
        f.navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => AddonHubScreen(key: f.key)),
        );
        await t.pump();
        await f.loaded(t);
        final old = f.key.currentState!;
        final node = f.member('kindFocus') as FocusNode;
        final client = f.clients.last;
        final beforeSame = ProfileRuntime.capture();
        await t.runAsync(() async {
          MainPageBridge.switchProfile!(p.a.profileId);
        });
        await f.until(t, () => !old.mounted);
        expect(ProfileRuntime.capture(), beforeSame);
        expect(ProfileRuntime.capture().profileId, p.a.profileId);
        expect(client.closed, isTrue);
        expect(node.hasFocus, isFalse);
        expect(f.key.currentState, isNull);
        f.navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => AddonHubScreen(key: f.key)),
        );
        await t.pump();
        await f.loaded(t);
        final replacement = f.key.currentState!;
        await t.runAsync(() async {
          MainPageBridge.switchProfile!(p.b.profileId);
        });
        await f.until(t, () => !replacement.mounted);
        await f.until(
          t,
          () => ProfileRuntime.capture().profileId == p.b.profileId,
        );
        expect(f.key.currentState, isNull);
        expect(await t.runAsync(() => p.engineIds(p.a)), isEmpty);
        expect(await t.runAsync(() => p.engineIds(p.b)), isEmpty);
      }, committed: true);
    },
  );
  for (final abort in [false, true]) {
    testWidgets(
      'held engine download across switch abort=$abort preserves save capture and suppresses snackbar',
      (t) async {
        await hubCase(t, (f) async {
          final p = AddonHubProfiles(f);
          await t.runAsync(p.open);
          f.abortOnClose = abort;
          await f.mount(t);
          await f.engines(t);
          final url = addonHubMetadataUrl.replaceFirst(
            'metadata.yaml',
            'z9.yaml',
          );
          final response = Completer<http.Response>();
          f.held[url] = response;
          await f.tapInRow(t, 'Zulu engine', 'Install');
          await f.until(t, () => f.requests.length == 2);
          final client = f.clients.last;
          await t.pumpWidget(const SizedBox.shrink());
          expect(client.closed, isTrue);
          await t.runAsync(() => p.publish(p.b));
          response.complete(
            http.Response(hubEngineYaml('z9', 'Zulu engine'), 200),
          );
          if (!abort) {
            await f.until(t, () => f.sync.isNotEmpty);
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            expect(f.sync, [(p.b.profileId, 'engine_definitions_changed')]);
          } else {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            expect(f.sync, isEmpty);
          }
          expect(await t.runAsync(() => p.engineIds(p.a)), isEmpty);
          expect(await t.runAsync(() => p.engineIds(p.b)), abort ? [] : ['z9']);
          expect(find.byType(SnackBar), findsNothing);
          expect(f.requests, ['GET $addonHubMetadataUrl', 'GET $url']);
        }, committed: true);
      },
    );
  }
  testWidgets(
    'held save captures A rejects after switch and commits neither profile nor sync',
    (t) async {
      await hubCase(t, (f) async {
        final p = AddonHubProfiles(f);
        await t.runAsync(p.open);
        await f.mount(t);
        await f.engines(t);
        final entered = Completer<void>();
        final release = Completer<void>();
        f.releases.add(() {
          if (!release.isCompleted) release.complete();
        });
        late Future<void> barrier;
        await t.runAsync(() async {
          barrier = ProfilePreferences.captureMutationSnapshot((_) async {
            entered.complete();
            await release.future;
          });
          await entered.future;
        });
        await f.tapInRow(t, 'Zulu engine', 'Install');
        await f.until(t, () => f.requests.length == 2);
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        expect(f.member('blockingProgressUp'), isTrue);
        expect(
          ProfilePreferences.diagnosticMutationState['preferenceBarrierHeld'],
          isTrue,
        );
        await t.pumpWidget(const SizedBox.shrink());
        await t.runAsync(() => p.publish(p.b));
        release.complete();
        await t.runAsync(() => barrier);
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        expect(await t.runAsync(() => p.engineIds(p.a)), isEmpty);
        expect(await t.runAsync(() => p.engineIds(p.b)), isEmpty);
        expect(f.sync, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
      }, committed: true);
    },
  );
  testWidgets(
    'committed addon toggle uses resource storage key and writes preserve order',
    (t) async {
      await hubCase(t, (f) async {
        final p = AddonHubProfiles(f);
        await t.runAsync(() => p.open(seed: true));
        await f.mount(t);
        final addon = (f.member('installed') as List<StremioAddon>).first;
        expect(addon.storageKey, isNot(addon.manifestUrl));
        await f.options(t, 'Zulu', 'Disable');
        await f.until(
          t,
          () =>
              f.member('installedLoading') == false &&
              !(f.member('installed') as List<StremioAddon>)
                  .singleWhere((e) => e.name == 'Zulu')
                  .enabled,
        );
        final saved = await f.saved(t);
        expect(saved.map((e) => e.name), ['Alpha', 'Cinemeta', 'Zulu']);
        expect(saved.singleWhere((e) => e.name == 'Zulu').enabled, isFalse);
        expect(f.sync, [
          (p.a.profileId, ProfilePreferences.webDavSyncRegistryLogicalKey),
        ]);
        expect(await t.runAsync(() => p.addonIds(p.b)), isEmpty);
        expect(f.requests, isEmpty);
      }, committed: true);
    },
  );
  testWidgets(
    'committed Update uses manifest URL rather than resource storage key',
    (t) async {
      await hubCase(t, (f) async {
        final p = AddonHubProfiles(f);
        await t.runAsync(() => p.open(seed: true));
        await f.mount(t);
        final addon = (f.member('installed') as List<StremioAddon>).singleWhere(
          (e) => e.name == 'Zulu',
        );
        expect(addon.storageKey, isNot(addon.manifestUrl));
        expect(addon.manifestUrl, 'https://z9.addon.test/manifest.json');
        f.responses[addon.manifestUrl] = f.json(
          hubManifest('z9', 'Zulu', version: '2.0.0'),
        );
        final pushed = f.observer.pushes.length;
        await f.options(t, 'Zulu', 'Update');
        await f.until(
          t,
          () =>
              find.text('Zulu updated (v1.0.0 → v2.0.0)').evaluate().isNotEmpty,
        );
        expect(f.requests, ['GET https://z9.addon.test/manifest.json']);
        expect(f.observer.pushes.length, pushed + 1); // the options sheet only
        final saved = await f.saved(t);
        expect(saved.map((e) => e.name), ['Alpha', 'Cinemeta', 'Zulu']);
        expect(saved.singleWhere((e) => e.name == 'Zulu').version, '2.0.0');
        expect(
          saved.singleWhere((e) => e.name == 'Zulu').storageKey,
          addon.storageKey,
        );
        expect(f.sync, [
          (p.a.profileId, ProfilePreferences.webDavSyncRegistryLogicalKey),
        ]);
        expect(await t.runAsync(() => p.addonIds(p.b)), isEmpty);
      }, committed: true);
    },
  );
  for (final all in [false, true]) {
    for (final confirm in [false, true]) {
      testWidgets(
        'shared addon remove all=$all confirm=$confirm revokes borrower only on confirmation',
        (t) async {
          await hubCase(t, (f) async {
            final p = AddonHubProfiles(f);
            await t.runAsync(() => p.open(seed: true));
            await t.runAsync(p.grantFirst);
            f.sync.clear();
            await f.mount(t);
            if (all) {
              await t.tap(find.byIcon(Icons.more_horiz_rounded));
              await t.pumpAndSettle();
              await f.tap(t, 'Delete all');
            } else {
              await f.options(t, 'Zulu', 'Remove');
            }
            await f.until(
              t,
              () => find.textContaining('shared with').evaluate().isNotEmpty,
            );
            expect(
              find.textContaining(all ? '1 addon is' : '1 other profile'),
              findsOneWidget,
            );
            await f.tap(
              t,
              confirm ? (all ? 'Delete all' : 'Remove') : 'Cancel',
            );
            if (confirm) {
              await f.until(
                t,
                () =>
                    f.member('installedLoading') == false &&
                    f.ids('installed').length == (all ? 0 : 2),
              );
            }
            expect(
              (await f.saved(t)).map((e) => e.name),
              confirm
                  ? (all ? [] : ['Alpha', 'Cinemeta'])
                  : ['Alpha', 'Cinemeta', 'Zulu'],
            );
            expect(
              await t.runAsync(() => p.addonIds(p.b)),
              confirm ? [] : ['Zulu'],
            );
            expect(
              f.sync,
              confirm
                  ? [
                      (
                        p.a.profileId,
                        ProfilePreferences.webDavSyncRegistryLogicalKey,
                      ),
                    ]
                  : [],
            );
            expect(f.requests, isEmpty);
          }, committed: true);
        },
      );
    }
  }
  testWidgets(
    'held addAddon rejects outgoing authorization and writes neither profile',
    (t) async {
      await hubCase(t, (f) async {
        final p = AddonHubProfiles(f);
        await t.runAsync(p.open);
        await f.mount(t);
        final response = Completer<http.Response>();
        f.held['https://m7.addon.test/manifest.json'] = response;
        await f.tap(t, 'Add addon');
        await t.enterText(
          find.byType(EditableText),
          'https://m7.addon.test/manifest.json',
        );
        await f.tap(t, 'Add');
        await f.until(t, () => f.requests.isNotEmpty);
        await t.pumpWidget(const SizedBox.shrink());
        await t.runAsync(() => p.publish(p.b));
        response.complete(f.json(hubManifest('m7', 'Middle')));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        expect(await t.runAsync(() => p.addonIds(p.a)), isEmpty);
        expect(await t.runAsync(() => p.addonIds(p.b)), isEmpty);
        expect(f.sync, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
        expect(f.requests, ['GET https://m7.addon.test/manifest.json']);
      }, committed: true);
    },
  );
  for (final beforeCapture in [true, false]) {
    testWidgets(
      'metadata preference switch before capture=$beforeCapture preserves acquisition target',
      (t) async {
        await hubCase(t, (f) async {
          final p = AddonHubProfiles(f);
          await t.runAsync(() => p.open(seed: true));
          await f.mount(t);
          final store = (await t.runAsync(AddonHubHeldPreferences.install))!;
          final release = Completer<void>();
          f.releases.add(() {
            if (!release.isCompleted) release.complete();
          });
          Future<void>? barrier;
          if (beforeCapture) {
            store.read = release;
            SharedPreferences.resetStatic();
          } else {
            final entered = Completer<void>();
            await t.runAsync(() async {
              barrier = ProfilePreferences.captureMutationSnapshot((_) async {
                entered.complete();
                await release.future;
              });
              await entered.future;
            });
          }
          final alpha = (f.member('installed') as List<StremioAddon>)
              .singleWhere((e) => e.name == 'Alpha');
          final value = StremioService.metadataProviderValue(alpha);
          await f.dropdown(t, 'Automatic', 'Alpha');
          if (beforeCapture) await f.until(t, () => store.reads.isNotEmpty);
          await t.runAsync(() => p.publish(p.b));
          release.complete();
          if (barrier != null) await t.runAsync(() => barrier!);
          if (beforeCapture) {
            await f.until(t, () => f.sync.isNotEmpty);
            expect(f.sync, [(p.b.profileId, 'stremio_metadata_provider_v1')]);
          } else {
            await f.until(
              t,
              () => find
                  .textContaining("Couldn't save metadata provider:")
                  .evaluate()
                  .isNotEmpty,
            );
            expect(f.member('metadataProviderPreference'), isNull);
            expect(
              t.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
              Colors.red,
            );
            expect(f.sync, isEmpty);
          }
          final prefs = (await t.runAsync(SharedPreferences.getInstance))!;
          expect(
            prefs.getString(p.a.preferenceKey('stremio_metadata_provider_v1')),
            isNull,
          );
          expect(
            prefs.getString(p.b.preferenceKey('stremio_metadata_provider_v1')),
            beforeCapture ? value : null,
          );
          expect(f.requests, isEmpty);
        }, committed: true);
      },
    );
  }
  testWidgets(
    'sheet toggle remains unawaited and reports outgoing resource error after scope handoff',
    (t) async {
      await hubCase(t, (f) async {
        final p = AddonHubProfiles(f);
        await t.runAsync(() => p.open(seed: true));
        await f.mount(t);
        await f.tap(t, 'Zulu');
        await t.runAsync(() => p.publish(p.b));
        Object? error;
        await t.runAsync(() async {
          await runZonedGuarded<Future<void>>(
            () => t.tap(find.text('Disable')),
            (Object e, StackTrace stack) {
              error = e;
            },
          );
        });
        await f.until(t, () {
          error ??= t.takeException();
          return error != null;
        });
        expect(error, isA<ArgumentError>());
        expect(error.toString(), contains('No addon with this storage key'));
        expect(await t.runAsync(() => p.addonIds(p.a)), [
          'Alpha',
          'Cinemeta',
          'Zulu',
        ]);
        expect(await t.runAsync(() => p.addonIds(p.b)), isEmpty);
        expect(f.sync, isEmpty);
      }, committed: true);
    },
  );
  testWidgets(
    'failed metadata write rolls back previous UI snapshot and records no successful sync',
    (t) async {
      await hubCase(t, (f) async {
        final previous = StremioService.metadataProviderValue(
          f.installed.singleWhere((e) => e.id == 'z9'),
        );
        await (await SharedPreferences.getInstance()).setString(
          'stremio_metadata_provider_v1',
          previous,
        );
        await f.mount(t);
        expect(f.member('metadataProviderPreference'), previous);
        final store = (await t.runAsync(AddonHubHeldPreferences.install))!;
        store.failKey = 'stremio_metadata_provider_v1';
        final picker = find.byWidgetPredicate(
          (w) =>
              w is StremioDropdown<String> &&
              w.focusNode == f.member('metadataFocus'),
        );
        await t.tap(picker);
        await t.pumpAndSettle();
        await f.tap(t, 'Automatic');
        await f.until(
          t,
          () => find
              .textContaining("Couldn't save metadata provider:")
              .evaluate()
              .isNotEmpty,
        );
        expect(f.member('metadataProviderPreference'), previous);
        expect(
          (await t.runAsync(
            store.getAll,
          ))!['flutter.stremio_metadata_provider_v1'],
          previous,
        );
        expect(
          t.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
          Colors.red,
        );
        expect(f.sync, isEmpty);
        expect(store.writes.single.$1, 'flutter.stremio_metadata_provider_v1');
        expect(store.writes.single.$2, 'automatic');
      });
    },
  );
  testWidgets(
    'incoming WebDAV definition refresh alone bumps change notifier and reloads hub',
    (t) async {
      await hubCase(t, (f) async {
        final p = AddonHubProfiles(f);
        await t.runAsync(p.open);
        await f.mount(t);
        await f.engines(t);
        final changes = LocalEngineStorage.changes.value;
        final revision = f.member('engineLoadRevision') as int;
        await t.runAsync(
          () => LocalEngineStorage.instance.saveEngine(
            engineId: 'm5',
            fileName: 'm5.yaml',
            yamlContent: hubEngineYaml('m5', 'Middle engine'),
            displayName: 'Middle engine',
          ),
        );
        expect(LocalEngineStorage.changes.value, changes);
        expect(f.ids('importedEngines'), isEmpty);
        expect(f.sync, [(p.a.profileId, 'engine_definitions_changed')]);
        await t.runAsync(
          () => const DefaultWebDavSyncActiveProfileRefresher().refresh({
            LocalEngineStorage.definitionKey('m5'),
          }, authorizationBarrier: () {}),
        );
        await f.until(t, () => f.ids('importedEngines').contains('m5'));
        expect(LocalEngineStorage.changes.value, changes + 1);
        expect(f.member('engineLoadRevision'), revision + 1);
        expect(f.sync, [(p.a.profileId, 'engine_definitions_changed')]);
        expect(f.requests, ['GET $addonHubMetadataUrl']);
      }, committed: true);
    },
  );
}
