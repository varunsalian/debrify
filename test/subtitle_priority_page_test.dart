import 'dart:convert';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/subtitle_source_priority.dart';
import 'package:debrify/screens/settings/subtitle_priority_page.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late String a, b;
  setUp(() {
    final addons = [
      for (final name in ['A', 'B'])
        StremioAddon.fromManifest({
          'id': name,
          'name': 'Subtitle $name',
          'resources': ['subtitles'],
        }, 'https://example.test/$name/manifest.json'),
    ];
    a = SubtitleSourcePriority.addon(addons[0].portableConfigurationKey);
    b = SubtitleSourcePriority.addon(addons[1].portableConfigurationKey);
    SharedPreferences.setMockInitialValues({
      'stremio_addons_v1': jsonEncode(addons.map((s) => s.toJson()).toList()),
    });
    StremioService.instance.invalidateCache();
    PlatformUtil.debugSetTvOS(true);
  });
  tearDown(() {
    StremioService.instance.invalidateCache();
    PlatformUtil.debugSetTvOS(null);
  });
  testWidgets(
    'remote picks up, moves, saves, and cancels while retaining focus',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SubtitlePriorityPage()));
      await tester.pumpAndSettle();
      expect(find.text('Subtitle A'), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'subtitle-priority-embedded',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'subtitle-priority-embedded',
      );
      expect(await StorageService.getSubtitleSourcePriority(), ['embedded']);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(await StorageService.getSubtitleSourcePriority(), [
        a,
        b,
        'embedded',
      ]);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await StorageService.getSubtitleSourcePriority(), [
        a,
        b,
        'embedded',
      ]);
      expect(
        tester.getTopLeft(find.text('Embedded subtitles')).dy,
        greaterThan(tester.getTopLeft(find.text('Subtitle B')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
