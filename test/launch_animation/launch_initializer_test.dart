import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/widgets/launch/launch_ident.dart';

import 'package:debrify/services/launch_animation/launch_animation_library.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/app_initializer.dart';
import 'package:debrify/widgets/initial_setup_flow.dart';
import 'package:debrify/widgets/launch/imported_launch_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/golden_harness.dart' show disableRuntimeFonts;

Future<List<int>> imagePairBytes(int frames) async {
  final fixture = ZipDecoder().decodeBytes(
    await File(
      'dev/launch_animations/samples/hello-image.lottie',
    ).readAsBytes(),
  );
  final archive = Archive();
  void addJson(String name, Object value) {
    final bytes = utf8.encode(jsonEncode(value));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  final artwork =
      jsonDecode(utf8.decode(fixture.findFile('a/hello-image.json')!.content))
          as Map<String, dynamic>;
  addJson('manifest.json', {
    'version': '2.0',
    'animations': [
      {'id': 'image-landscape'},
      {'id': 'image-portrait'},
    ],
  });
  for (final portrait in [false, true]) {
    addJson('a/image-${portrait ? 'portrait' : 'landscape'}.json', {
      ...artwork,
      'op': frames,
      'w': portrait ? 540 : 960,
      'h': portrait ? 960 : 540,
    });
  }
  final image = fixture.findFile('i/square.png')!;
  archive.addFile(ArchiveFile(image.name, image.size, image.content));
  return ZipEncoder().encode(archive);
}

void main() {
  for (final tv in [false, true]) {
    for (final mode in [
      'slow',
      'ready',
      'onboarding',
      'dispose',
      'failure',
      'lateInit',
      'builtIn',
    ]) {
      final ready = ['ready', 'lateInit', 'builtIn'].contains(mode);
      testWidgets('imported startup completes its flow (TV=$tv, mode=$mode)', (
        tester,
      ) async {
        disableRuntimeFonts();
        final manifest = Completer<StremioAddon>();
        final previousFetcher = StremioService.instance.debugManifestFetcher;
        var manifestRequested = false;
        if (mode == 'lateInit') {
          StremioService.instance.debugManifestFetcher = (_) {
            manifestRequested = true;
            return manifest.future;
          };
        }
        addTearDown(
          () => StremioService.instance.debugManifestFetcher = previousFetcher,
        );

        SharedPreferences.setMockInitialValues({
          'initial_setup_complete_v1': mode != 'onboarding',
          'remote_control_enabled': false,
          'essential_addon_cinemeta_seeded': mode != 'lateInit',
          'essential_addon_opensubtitles_seeded': true,
          'essential_addon_opensubtitles_official_seeded': true,
          'essential_addon_watch_next_seeded': true,
          'app_last_version': 'test',
          'app_last_build_number': '1',
        });
        PackageInfo.setMockInitialValues(
          appName: 'Debrify',
          packageName: 'test',
          version: 'test',
          buildNumber: '1',
          buildSignature: '',
        );
        PlatformUtil.debugSetAndroidTvCached(tv);
        ProfileRuntime.debugReset();
        ProfileRuntime.initializeLegacy();
        MainPageBridge.homeBoardReady.value = ready;
        late Directory root;
        await tester.runAsync(() async {
          root = await Directory.systemTemp.createTemp(
            'launch-initializer-test-',
          );
          AppStorage.debugOverride(support: root);
          final source = await File(
            '${root.path}/source.lottie',
          ).writeAsBytes(await imagePairBytes(mode == 'lateInit' ? 30 : 150));
          final entry = await LaunchAnimationLibrary.instance.install(source);
          await StorageService.setImportedLaunchAnimation(entry.id);
          if (mode == 'builtIn') {
            await StorageService.setLaunchAnimation('trace');
          }
          await StorageService.getLaunchAnimation();
        });
        addTearDown(() async {
          await root.delete(recursive: true);
          AppStorage.debugReset();
          PlatformUtil.debugSetAndroidTvCached(null);
        });
        var homeMounts = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: AppInitializer(
              homeBuilder: (_) {
                homeMounts++;
                return const SizedBox(key: Key('home'));
              },
            ),
          ),
        );
        for (
          var attempt = 0;
          mode != 'builtIn' &&
              attempt < 40 &&
              find.byType(ImportedLaunchPlayer).evaluate().isEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
        expect(homeMounts, 0);
        final imported = mode == 'builtIn'
            ? null
            : tester
                  .widget<ImportedLaunchPlayer>(
                    find.byType(ImportedLaunchPlayer),
                  )
                  .animation;
        final assets = [
          ...?imported?.composition.images.values,
          ...?imported?.alternate?.composition.images.values,
        ];
        if (imported != null) {
          expect(assets, hasLength(2));
          expect(assets.every((asset) => asset.loadedImage != null), isTrue);
        }
        void expectAssetsReleased() {
          expect(
            assets.every((asset) => asset.loadedImage == null),
            isTrue,
            reason: 'Startup images must be released when the player detaches.',
          );
        }

        if (mode == 'builtIn' || mode == 'lateInit') {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
          if (mode == 'builtIn') {
            expect(find.byType(ImportedLaunchPlayer), findsNothing);
            final duration = launchIdentFor(
              StorageService.launchAnimationCached,
            ).revealDuration;
            await tester.pump(duration - const Duration(milliseconds: 100));
            expect(find.byKey(const Key('home')), findsNothing);
            await tester.pump(const Duration(milliseconds: 200));
          } else {
            expect(manifestRequested, isTrue);
            await tester.pump(const Duration(seconds: 2));
            expect(
              tester
                  .widget<ImportedLaunchPlayer>(
                    find.byType(ImportedLaunchPlayer),
                  )
                  .progress
                  .value,
              1,
            );
            expect(find.byKey(const Key('home')), findsNothing);
            manifest.completeError(StateError('offline during initialization'));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
          }
          await tester.pump();
          expect(find.byKey(const Key('home')), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));
          expect(find.byType(ImportedLaunchPlayer), findsNothing);
          expect(tester.takeException(), isNull);
          expectAssetsReleased();
          await tester.pumpWidget(const SizedBox());
          return;
        }
        expect(find.byType(ImportedLaunchPlayer), findsOneWidget);

        if (mode == 'failure') {
          final player = tester.widget<ImportedLaunchPlayer>(
            find.byType(ImportedLaunchPlayer),
          );
          player.onError(StateError('recoverable paint failure'));
          await tester.pump();
          expect(player.progress.value, 1);
          expect(find.byType(ImportedLaunchPlayer), findsNothing);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
          expect(find.byKey(const Key('home')), findsOneWidget);
          MainPageBridge.homeBoardReady.value = true;
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          expectAssetsReleased();
          await tester.pumpWidget(const SizedBox());
          return;
        }
        if (mode == 'dispose') {
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 16));
          expectAssetsReleased();
          expect(tester.takeException(), isNull);
          return;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));
        expect(find.byKey(const Key('home')), findsNothing);
        await tester.pump(const Duration(milliseconds: 1100));
        await tester.pump();
        if (mode == 'onboarding') {
          expect(find.byType(InitialSetupFlow), findsOneWidget);
          expect(find.byKey(const Key('home')), findsNothing);
          Navigator.of(
            tester.element(find.byType(InitialSetupFlow)),
          ).pop(false);
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        } else {
          expect(find.byKey(const Key('home')), findsOneWidget);
          expect(find.byType(ImportedLaunchPlayer), findsOneWidget);
        }
        if (mode == 'slow') {
          await tester.pump(const Duration(seconds: 9));
          expect(find.byType(ImportedLaunchPlayer), findsOneWidget);
          await tester.pump(const Duration(seconds: 1));
        }
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(find.byKey(const Key('home')), findsOneWidget);
        expect(find.byType(ImportedLaunchPlayer), findsNothing);
        expect(tester.takeException(), isNull);
        expectAssetsReleased();
        expect(find.byType(AppInitializer), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
