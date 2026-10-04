import 'dart:async';

import 'package:debrify/screens/addons/addon_hub_screen.dart';
import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../support/addon_hub_fixture.dart';
import '../../../../support/addon_hub_profiles.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  for (final operation in ['install', 'delete', 'import']) {
    for (final unmount in [false, true]) {
      testWidgets(
        '$operation unmount=$unmount commits captured profile once then original load follows reload',
        (t) async {
          await hubCase(t, (f) async {
            final p = AddonHubProfiles(f);
            await t.runAsync(p.open);
            if (operation == 'delete') {
              await t.runAsync(
                () => LocalEngineStorage.instance.saveEngine(
                  engineId: 'z9',
                  fileName: 'z9.yaml',
                  yamlContent: hubEngineYaml('z9', 'Zulu engine'),
                  displayName: 'Zulu engine',
                ),
              );
            }
            await f.mount(t);
            await f.engines(t);
            f.sync.clear();
            final change = LocalEngineStorage.changes.value;
            final entered = Completer<void>();
            final release = Completer<void>();
            f.releases.add(() {
              if (!release.isCompleted) release.complete();
            });
            EngineRegistry.debugBeforePublish = () async {
              if (!entered.isCompleted) entered.complete();
              await release.future;
            };
            if (operation == 'install') {
              await f.tapInRow(t, 'Zulu engine', 'Install');
            } else if (operation == 'delete') {
              await f.tapInRow(t, 'Zulu engine', 'Remove');
              await f.tap(t, 'Delete');
            } else {
              f.picker.supply('m5.yaml', hubEngineYaml('m5', 'Middle engine'));
              await f.tap(t, 'Import YAML');
            }
            await f.until(t, () => entered.isCompleted);
            expect(f.sync, [(p.a.profileId, 'engine_definitions_changed')]);
            expect(LocalEngineStorage.changes.value, change);
            expect(f.member('blockingProgressUp'), operation != 'delete');
            final state = f.key.currentState!;
            if (unmount) {
              await t.pumpWidget(const SizedBox.shrink());
              expect(state.mounted, isFalse);
            }
            release.complete();
            EngineRegistry.debugBeforePublish = null;
            if (unmount) {
              await t.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 100)),
              );
              expect(find.byType(SnackBar), findsNothing);
              expect(
                addonHubTestAccess(state)['blockingProgressUp'],
                operation != 'delete',
              );
            } else {
              final name = operation == 'import'
                  ? 'Middle engine imported'
                  : operation == 'install'
                  ? 'Zulu engine installed'
                  : 'Zulu engine deleted';
              await f.until(t, () => find.text(name).evaluate().isNotEmpty);
              expect(f.member('blockingProgressUp'), isFalse);
            }
            expect(
              await t.runAsync(() => p.engineIds(p.a)),
              operation == 'delete'
                  ? []
                  : [operation == 'import' ? 'm5' : 'z9'],
            );
            expect(await t.runAsync(() => p.engineIds(p.b)), isEmpty);
            expect(f.sync, [(p.a.profileId, 'engine_definitions_changed')]);
            expect(f.requests, [
              'GET $addonHubMetadataUrl',
              if (operation == 'install')
                'GET ${addonHubMetadataUrl.replaceFirst('metadata.yaml', 'z9.yaml')}',
            ]);
          }, committed: true);
        },
      );
    }
  }
  testWidgets(
    'original loadEngines entry after disposal throws before any request',
    (t) async {
      await hubCase(t, (f) async {
        await f.mount(t);
        final load = f.member('loadEngines') as Future<void> Function();
        await t.pumpWidget(const SizedBox.shrink());
        await expectLater(
          load(),
          throwsA(
            isA<FlutterError>().having(
              (e) => e.toString(),
              'message',
              contains('setState() called after dispose'),
            ),
          ),
        );
        expect(f.requests, isEmpty);
      });
    },
  );
  testWidgets(
    'cancel engine import and no-op delete notify nothing in either profile',
    (t) async {
      await hubCase(t, (f) async {
        final p = AddonHubProfiles(f);
        await t.runAsync(p.open);
        await f.mount(t);
        await f.engines(t);
        await f.tap(t, 'Import YAML');
        await f.until(t, () => f.picker.calls.isNotEmpty);
        await t.runAsync(
          () => LocalEngineStorage.instance.deleteEngine('missing6'),
        );
        expect(f.sync, isEmpty);
        expect(await t.runAsync(() => p.engineIds(p.a)), isEmpty);
        expect(await t.runAsync(() => p.engineIds(p.b)), isEmpty);
        expect(f.member('blockingProgressUp'), isFalse);
      }, committed: true);
    },
  );
}
