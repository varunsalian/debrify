import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:debrify/screens/settings/iptv_channel_order_page.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    IptvMediaStore.debugResetMigration();
    DebrifyTvDatabase.debugDatabaseOverride = await databaseFactoryFfiNoIsolate
        .openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: 1,
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
            onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
          ),
        );
    for (final entry in const [
      ('http://h/a', 'Alpha'),
      ('http://h/b', 'Bravo'),
      ('http://h/c', 'Charlie'),
    ]) {
      await StorageService.setIptvChannelFavorited(
        entry.$1,
        true,
        channelName: entry.$2,
      );
    }
    PlatformUtil.debugSetAndroidTvCached(true);
  });

  tearDown(() async {
    PlatformUtil.debugSetAndroidTvCached(null);
    await DebrifyTvDatabase.debugDatabaseOverride?.close();
    DebrifyTvDatabase.debugDatabaseOverride = null;
    IptvMediaStore.debugResetMigration();
  });

  testWidgets('TV OK picks up, DPAD moves, OK drops, and Done persists', (
    tester,
  ) async {
    Future<void> drainAsync() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: const IptvChannelOrderPage(),
        ),
      ),
    );
    await drainAsync();
    expect(find.text('FAVORITES AND LISTS'), findsOneWidget);
    expect(
      find.text('CATEGORIES'),
      findsNothing,
      reason: 'source-category channel ordering is not exposed in Settings',
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'iptv-channel-order-first-target',
    );
    await tester.tap(find.text('Favorites'));
    await drainAsync();

    expect(find.text('Alpha'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      startsWith('iptv-channel-order-'),
    );
    final firstFocus = FocusManager.instance.primaryFocus?.debugLabel;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot(firstFocus));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, firstFocus);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.text('Moving…'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, firstFocus);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('Moving…'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Moving…'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      startsWith('iptv-channel-order-'),
      reason: 'focus follows the row being moved',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.text('Moving…'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'iptv-channel-order-done',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await drainAsync();

    late Map<String, Map<String, dynamic>> favorites;
    await tester.runAsync(() async {
      favorites = await StorageService.getIptvFavoriteChannels();
    });
    expect(favorites.keys, ['http://h/b', 'http://h/a', 'http://h/c']);
    expect(tester.takeException(), isNull);
  });
}
