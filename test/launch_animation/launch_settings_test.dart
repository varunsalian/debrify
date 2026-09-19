import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/services/launch_animation/launch_animation_library.dart';
import 'package:debrify/screens/settings/imported_launch_animations.dart';
import 'package:debrify/widgets/launch/imported_launch_player.dart';

void main() {
  testWidgets(
    'preview gates Use, replays, changes layout and persists selection',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      late Directory root;
      late InstalledLaunchAnimation entry;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('launch-settings-test-');
        AppStorage.debugOverride(support: root);
        entry = await LaunchAnimationLibrary.instance.install(
          File('dev/launch_animations/samples/hello-landscape.lottie'),
        );
        await StorageService.getLaunchAnimation();
      });
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: ImportedLaunchDetail(entry: entry, onSelectionChanged: () {}),
        ),
      );
      expect(find.text('Remove animation'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use animation'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Remove animation'));
      await tester.pump();
      expect(find.text('Remove ${entry.name}?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      for (
        var attempt = 0;
        attempt < 40 && find.byType(ImportedLaunchPlayer).evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
      }
      expect(find.byType(ImportedLaunchPlayer), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use animation'),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('Landscape preview'), findsOneWidget);
      await tester.ensureVisible(find.text('Landscape preview'));
      await tester.tap(find.text('Landscape preview'));
      await tester.pump();
      expect(find.text('Portrait preview'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Use animation'));
      await tester.tap(find.text('Use animation'));
      for (
        var attempt = 0;
        attempt < 40 &&
            StorageService.importedLaunchAnimationCached != entry.id;
        attempt++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
      }
      expect(
        StorageService.importedLaunchAnimationCached,
        entry.id,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await root.delete(recursive: true);
      });
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      AppStorage.debugReset();
    },
  );
  testWidgets(
    'TV without a document provider offers paired transfer and preserves selection',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      PlatformUtil.debugSetAndroidTvCached(true);
      FilePickerIO.registerWith();
      const channel = MethodChannel(
        'miguelruivo.flutter.plugins.filepicker',
        JSONMethodCodec(),
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        _,
      ) async {
        throw PlatformException(
          code: 'invalid_format_type',
          message: "Can't handle the provided file type.",
        );
      });
      late Directory root;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('launch-picker-test-');
        AppStorage.debugOverride(support: root);
        await LaunchAnimationLibrary.instance.list();
        await StorageService.setImportedLaunchAnimation('a' * 32);
      });
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        PlatformUtil.debugSetAndroidTvCached(null);
        AppStorage.debugReset();
        await root.delete(recursive: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportedLaunchAnimations(onSelectionChanged: () {}),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.tap(find.text('Import .lottie file'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No file picker is available on this TV.'),
        findsOneWidget,
      );
      expect(StorageService.importedLaunchAnimationCached, 'a' * 32);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
