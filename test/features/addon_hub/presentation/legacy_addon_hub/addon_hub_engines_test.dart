import 'dart:async';
import 'dart:io';

import 'package:debrify/services/engine/engine_registry.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../support/addon_hub_fixture.dart';

String engineUrl(String name) =>
    'https://gitlab.com/mediacontent/search-engines/-/raw/main/torrents/$name';

void main() {
  testWidgets(
    'metadata single request remote order and refresh cache hits load once',
    (t) async {
      await hubCase(t, (f) async {
        await f.mount(t);
        await f.engines(t);
        expect(f.requests, ['GET $addonHubMetadataUrl']);
        expect(f.ids('availableEngines'), ['z9', 'a2']);
        await t.tap(find.byIcon(Icons.refresh_rounded));
        await f.until(t, () => f.member('enginesLoading') == false);
        expect(f.requests, ['GET $addonHubMetadataUrl']);
        final revision = f.member('engineLoadRevision');
        await f.dropdown(t, 'Torrent Engines', 'Stremio Addons');
        await f.dropdown(t, 'Stremio Addons', 'Torrent Engines');
        expect(f.member('engineLoadRevision'), revision);
        expect(f.requests, ['GET $addonHubMetadataUrl']);
      });
    },
  );
  testWidgets(
    'metadata failure uses uncached tree and per-file requests in service order',
    (t) async {
      await hubCase(t, (f) async {
        f.responses[addonHubMetadataUrl] = http.Response('failure', 500);
        await f.mount(t);
        await f.engines(t);
        final sequence = [
          'GET $addonHubMetadataUrl',
          'GET $addonHubTreeUrl',
          'GET ${engineUrl('z9.yaml')}',
          'GET ${engineUrl('a2.yaml')}',
        ];
        expect(f.requests, sequence);
        expect(f.ids('availableEngines'), ['z9', 'a2']);
        await t.tap(find.byIcon(Icons.refresh_rounded));
        await f.until(t, () => f.member('enginesLoading') == false);
        expect(f.requests, [...sequence, ...sequence]);
      });
    },
  );
  testWidgets(
    'engine Retry error strips prefix and never forces cache invalidation',
    (t) async {
      await hubCase(t, (f) async {
        f.responses[addonHubMetadataUrl] = http.Response('failure', 500);
        f.responses[addonHubTreeUrl] = http.Response('tree failure', 500);
        await f.mount(t);
        await f.engines(t);
        expect(
          f.member('enginesError'),
          'GitLab API returned 500: tree failure',
        );
        f.responses.remove(addonHubMetadataUrl);
        f.responses.remove(addonHubTreeUrl);
        await f.tap(t, 'Retry');
        await f.until(t, () => f.member('enginesLoading') == false);
        expect(f.requests, [
          'GET $addonHubMetadataUrl',
          'GET $addonHubTreeUrl',
          'GET $addonHubMetadataUrl',
        ]);
        expect(f.ids('availableEngines'), ['z9', 'a2']);
      });
    },
  );
  testWidgets(
    'late engine A overwrites known list and bumps shared revision after B',
    (t) async {
      await hubCase(t, (f) async {
        final a = Completer<http.Response>();
        f.held[addonHubMetadataUrl] = a;
        await f.mount(t);
        await f.dropdown(t, 'Stremio Addons', 'Torrent Engines', wait: false);
        await f.until(t, () => f.requests.isNotEmpty);
        f.held.remove(addonHubMetadataUrl);
        final b = (f.member('loadEngines') as Future<void> Function())();
        await f.until(t, () => f.member('enginesLoading') == false);
        await b;
        expect(f.ids('knownRemoteEngines'), ['z9', 'a2']);
        final revision = f.member('engineLoadRevision') as int;
        a.complete(
          http.Response(
            'version: "1.0"\nengines:\n  - name: Late old engine\n    path: torrents/old7.yaml\n',
            200,
          ),
        );
        await f.until(t, () => f.ids('knownRemoteEngines').contains('old7'));
        await f.until(
          t,
          () =>
              f.member('engineLoadRevision') == revision + 1 &&
              f.member('enginesLoading') == false,
        );
        expect(f.ids('availableEngines'), ['old7']);
        expect(f.requests, [
          'GET $addonHubMetadataUrl',
          'GET $addonHubMetadataUrl',
        ]);
      });
    },
  );
  testWidgets(
    'engine timeout closes original zone client and replaces via same factory',
    (t) async {
      await hubCase(t, (f) async {
        final held = Completer<http.Response>();
        f.held[addonHubMetadataUrl] = held;
        await f.mount(t);
        await f.dropdown(
          t,
          'Stremio Addons',
          'Torrent Engines',
          wait: false,
          realIo: false,
        );
        await f.until(t, () => f.requests.isNotEmpty);
        final original = f.clients.last;
        expect(original.closed, isFalse);
        await t.pump(const Duration(seconds: 30));
        await f.until(t, () => f.member('enginesLoading') == false);
        expect(original.closed, isTrue);
        expect(f.clients.last, same(f.clients[3]));
        expect(f.clients.last.closed, isFalse);
        expect(f.requests, [
          'GET $addonHubMetadataUrl',
          'GET $addonHubTreeUrl',
          'GET ${engineUrl('z9.yaml')}',
          'GET ${engineUrl('a2.yaml')}',
        ]);
        f.held.remove(addonHubMetadataUrl);
        held.complete(
          f.respond(http.Request('GET', Uri.parse(addonHubMetadataUrl))),
        );
        await t.pump();
        await t.pumpWidget(const SizedBox.shrink());
        expect(f.clients.last.closed, isTrue);
      });
    },
  );
  for (final success in [true, false]) {
    testWidgets(
      'install engine $success blocking progress and exact durable effects',
      (t) async {
        await hubCase(t, (f) async {
          await f.mount(t);
          await f.engines(t);
          final held = Completer<http.Response>();
          f.held[engineUrl('z9.yaml')] = held;
          await f.tapInRow(t, 'Zulu engine', 'Install');
          await f.until(t, () => f.requests.length == 2);
          expect(f.member('blockingProgressUp'), isTrue);
          expect(find.text('Installing Zulu engine…'), findsOneWidget);
          expect(f.observer.pushes.last is DialogRoute, isTrue);
          expect(
            (f.observer.pushes.last as DialogRoute).barrierDismissible,
            isFalse,
          );
          held.complete(
            http.Response(
              success ? hubEngineYaml('z9', 'Zulu engine') : 'download failure',
              success ? 200 : 500,
            ),
          );
          await f.until(t, () => f.member('blockingProgressUp') == false);
          await f.until(
            t,
            () => find
                .text(
                  success
                      ? 'Zulu engine installed'
                      : 'Failed to install: Exception: Failed to download engine config',
                )
                .evaluate()
                .isNotEmpty,
          );
          await t.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          final saved = (await t.runAsync(
            LocalEngineStorage.instance.getImportedEngines,
          ))!;
          expect(saved.map((e) => e.id), success ? ['z9'] : []);
          if (success) {
            final dir = await t.runAsync(
              LocalEngineStorage.instance.getEnginesDirectoryPath,
            );
            expect(
              await t.runAsync(
                () => File('$dir/${saved.single.fileName}').readAsString(),
              ),
              hubEngineYaml('z9', 'Zulu engine'),
            );
            expect(f.ids('availableEngines'), ['a2']);
          } else {
            expect(
              t.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
              Colors.red,
            );
          }
          expect(f.requests, [
            'GET $addonHubMetadataUrl',
            'GET ${engineUrl('z9.yaml')}',
          ]);
        });
      },
    );
  }
  for (final confirm in [true, false]) {
    testWidgets('delete engine $confirm never opens blocking progress', (
      t,
    ) async {
      await hubCase(t, (f) async {
        await t.runAsync(
          () => LocalEngineStorage.instance.saveEngine(
            engineId: 'z9',
            fileName: 'z9.yaml',
            yamlContent: hubEngineYaml('z9', 'Zulu engine'),
            displayName: 'Zulu engine',
          ),
        );
        await f.mount(t);
        await f.engines(t);
        await f.tapInRow(t, 'Zulu engine', 'Remove');
        expect(find.text('Delete engine'), findsOneWidget);
        expect(f.member('blockingProgressUp'), isFalse);
        final pushed = f.observer.pushes.length;
        await f.tap(t, confirm ? 'Delete' : 'Cancel');
        if (confirm) {
          await f.until(
            t,
            () =>
                f.ids('importedEngines').isEmpty &&
                f.member('enginesLoading') == false,
          );
        }
        expect(f.member('blockingProgressUp'), isFalse);
        expect(f.observer.pushes.length, pushed);
        final saved = (await t.runAsync(
          LocalEngineStorage.instance.getImportedEngines,
        ))!;
        expect(saved.map((e) => e.id), confirm ? [] : ['z9']);
        expect(f.requests, ['GET $addonHubMetadataUrl']);
      });
    });
  }
  testWidgets(
    'failing engine delete remains non-blocking and shows red error',
    (t) async {
      await hubCase(t, (f) async {
        await t.runAsync(
          () => LocalEngineStorage.instance.saveEngine(
            engineId: 'z9',
            fileName: 'z9.yaml',
            yamlContent: hubEngineYaml('z9', 'Zulu engine'),
            displayName: 'Zulu engine',
          ),
        );
        await f.mount(t);
        await f.engines(t);
        await f.tapInRow(t, 'Zulu engine', 'Remove');
        final path = (await t.runAsync(
          LocalEngineStorage.instance.getEnginesDirectoryPath,
        ))!;
        await t.runAsync(
          () => File('$path/metadata.json').writeAsString('bad inventory'),
        );
        final pushed = f.observer.pushes.length;
        await f.tap(t, 'Delete');
        await f.until(t, () => find.byType(SnackBar).evaluate().isNotEmpty);
        expect(f.member('blockingProgressUp'), isFalse);
        expect(f.observer.pushes.length, pushed);
        expect(
          t.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
          Colors.red,
        );
        expect(
          find.textContaining('Failed to delete: FormatException'),
          findsOneWidget,
        );
        expect(f.ids('importedEngines'), ['z9']);
        expect(f.requests, ['GET $addonHubMetadataUrl']);
      });
    },
  );
  for (final variant in [
    'cancel',
    'extension',
    'missing-id',
    'missing-name',
    'bytes',
    'path',
    'replace-cancel',
    'replace',
  ]) {
    testWidgets(
      'YAML import $variant validation replace rule picker and progress',
      (t) async {
        await hubCase(t, (f) async {
          if (variant.startsWith('replace')) {
            await t.runAsync(
              () => LocalEngineStorage.instance.saveEngine(
                engineId: 'm5',
                fileName: 'm5.yaml',
                yamlContent: hubEngineYaml('m5', 'Old engine'),
                displayName: 'Old engine',
              ),
            );
          }
          final content = variant == 'missing-id'
              ? 'display_name: Middle engine\n'
              : variant == 'missing-name'
              ? 'id: m5\n'
              : hubEngineYaml('m5', 'Middle engine');
          if (variant != 'cancel') {
            final file = File('${f.directory.path}/middle.yaml');
            await t.runAsync(() => file.writeAsString(content));
            f.picker.supply(
              variant == 'extension' ? 'middle.txt' : 'middle.yml',
              content,
              path: file.path,
              bytes: variant != 'path',
            );
          }
          await f.mount(t);
          await f.engines(t);
          final loaded = Completer<void>();
          f.releases.add(() {
            if (!loaded.isCompleted) loaded.complete();
          });
          EngineRegistry.debugBeforePublish = () => loaded.future;
          await f.tap(t, 'Import YAML');
          await f.until(t, () => f.picker.calls.isNotEmpty);
          expect(f.picker.calls.single, {
            'type': FileType.any,
            'allowMultiple': false,
            'withData': true,
            'allowedExtensions': null,
          });
          if (variant.startsWith('replace')) {
            await f.until(
              t,
              () => find.text('Engine already exists').evaluate().isNotEmpty,
            );
            expect(f.member('blockingProgressUp'), isFalse);
            await f.tap(t, variant == 'replace-cancel' ? 'Cancel' : 'Replace');
          }
          final success = ['bytes', 'path', 'replace'].contains(variant);
          if (success) {
            await f.until(t, () => f.member('blockingProgressUp') == true);
            await t.pump();
            expect(find.text('Importing Middle engine…'), findsOneWidget);
            expect(find.text('Engine already exists'), findsNothing);
            loaded.complete();
            EngineRegistry.debugBeforePublish = null;
            await f.until(
              t,
              () => find.text('Middle engine imported').evaluate().isNotEmpty,
            );
            final saved = (await t.runAsync(
              LocalEngineStorage.instance.getImportedEngines,
            ))!;
            expect(saved.single.id, 'm5');
            expect(saved.single.displayName, 'Middle engine');
          } else {
            loaded.complete();
            EngineRegistry.debugBeforePublish = null;
            if (['extension', 'missing-id', 'missing-name'].contains(variant)) {
              await f.until(
                t,
                () => find.byType(SnackBar).evaluate().isNotEmpty,
              );
              expect(
                t.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
                Colors.red,
              );
              expect(
                find.text(
                  variant == 'extension'
                      ? 'Please select a YAML file (.yaml or .yml)'
                      : variant == 'missing-id'
                      ? 'YAML must contain an "id" field'
                      : 'YAML must contain a "display_name" field',
                ),
                findsOneWidget,
              );
            }
            expect(
              (await t.runAsync(
                LocalEngineStorage.instance.getImportedEngines,
              ))!.map((e) => e.displayName),
              variant == 'replace-cancel' ? ['Old engine'] : [],
            );
          }
          await t.pumpAndSettle();
          expect(f.member('blockingProgressUp'), isFalse);
          expect(f.requests, ['GET $addonHubMetadataUrl']);
        });
      },
    );
  }
}
