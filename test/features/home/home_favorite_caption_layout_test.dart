import 'dart:async';

import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/services/home_row_refresh.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/home_appearance_storage.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class _Channels extends Fake implements Database {
  final initial = Completer<List<Map<String, Object?>>>();
  bool failed = false;
  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    if (failed) throw StateError('database');
    return table == 'tv_channels'
        ? initial.future
        : [
            {'keyword': 'query fixture'},
          ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // These bundled files are real TrueType fonts (the legacy Roboto asset is not).
    for (final family in ['Inter', 'Poppins']) {
      final bytes = await rootBundle.load('assets/fonts/$family-Regular.ttf');
      expect(
        bytes.getUint32(0),
        0x00010000,
        reason: 'Use real TrueType metrics',
      );
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  });
  for (final font in ['Inter', 'Poppins']) {
    for (final scale in [1.0, 1.25, 2.0]) {
      for (final size in [const Size(800, 600), const Size(1280, 720)]) {
        testWidgets(
          'favourite caption fits $font scale $scale at $size through refresh',
          (tester) async {
            await tester.binding.setSurfaceSize(size);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            ProfileRuntime.debugReset();
            ProfileRuntime.initializeLegacy();
            PlatformUtil.debugSetAndroidTvCached(false);
            PlatformUtil.debugSetTvOS(false);
            final channels = _Channels();
            DebrifyTvDatabase.debugDatabaseOverride = channels;
            SharedPreferences.setMockInitialValues({
              'stremio_addons_v1': '[]',
              'tv_home_style': 'classic',
              'home_hero_source_v1': '{"mode":"auto","ids":[]}',
              'debrify_tv_favorite_channels_v1': '{"fixture":true}',
            });
            HomeAppearanceStorage.tvHomeStyleCached = 'classic';
            StremioService.instance.invalidateCache();
            addTearDown(() {
              DebrifyTvDatabase.debugDatabaseOverride = null;
              PlatformUtil.debugSetAndroidTvCached(null);
              PlatformUtil.debugSetTvOS(null);
              ProfileRuntime.debugReset();
            });
            final client = MockClient((_) async => http.Response('[]', 200));
            addTearDown(client.close);
            Future<void> drive(FutureOr<void> Function() action) =>
                tester.runAsync(
                  () => http.runWithClient(() async {
                    await action();
                    await Future<void>.delayed(
                      const Duration(milliseconds: 150),
                    );
                  }, () => client),
                );
            await drive(
              () => tester.pumpWidget(
                ProviderScope(
                  child: MaterialApp(
                    theme: ThemeData(fontFamily: font),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                    home: SearchScreen(isTelevision: true),
                  ),
                ),
              ),
            );
            await drive(
              () => channels.initial.complete([
                {
                  'channel_id': 'fixture',
                  'name': 'Channel fixture with a longer programme title',
                  'channel_number': 0,
                },
              ]),
            );
            await tester.pump(const Duration(milliseconds: 100));
            expect(
              find.text('Channel fixture with a longer programme title'),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            final title = find.text(
              'Channel fixture with a longer programme title',
            );
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: title, matching: find.byType(RichText)),
            );
            expect(paragraph.text.style!.fontFamily, font);
            expect(paragraph.textScaler.scale(14), 14 * scale);
            expect(paragraph.maxLines, 2);
            final before = tester.getSize(title);
            Focus.of(tester.element(title)).requestFocus();
            await tester.pump();
            expect(tester.takeException(), isNull);
            channels.failed = true;
            await drive(() => HomeRowRefreshSignal.dispatch({'tv/ch'}));
            await tester.pump(const Duration(milliseconds: 100));
            expect(tester.takeException(), isNull);
            expect(tester.getSize(title), before);
            await drive(() async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('debrify_tv_favorite_channels_v1', '{}');
              HomeRowRefreshSignal.dispatch({
                'debrify_tv_favorite_channels_v1',
              });
            });
            await tester.pump(const Duration(milliseconds: 100));
            expect(tester.takeException(), isNull);
            expect(title, findsNothing);
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 1));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
