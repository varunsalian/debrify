import 'dart:async';

import 'package:debrify/features/home/presentation/home_item_actions.dart';
import 'package:debrify/features/home/presentation/home_playlist_actions.dart';
import 'package:debrify/features/home/presentation/home_saved_iptv_actions.dart';
import 'package:debrify/features/home/presentation/home_watchlist_actions.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Saved-content writes run after an awaited prompt and resolve the active
// profile when they execute, so a profile switch while the prompt is open must
// cancel them. The normal path must still write.
void main() {
  late BuildContext hostContext;

  Future<void> host(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: AppThemeScope(
        theme: AppThemes.legacy,
        child: Scaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    ),
  );

  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(ProfileRuntime.debugReset);

  group('playlist delete', () {
    final item = <String, dynamic>{
      'title': 'Saved Movie',
      'url': 'https://example.invalid/movie.mkv',
      'provider': 'direct',
    };

    Future<bool> deleteAfterSwitch(
      WidgetTester tester, {
      required bool switchProfile,
    }) async {
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(() => StorageService.addPlaylistItemRaw(item));
      await host(tester);
      var current = true;
      final actions = HomePlaylistActions((
        mounted: () => true,
        profileCurrent: () => current,
        context: () => hostContext,
        controller: () => throw UnimplementedError(),
        reload: () async {},
        play: (_, _, {playRandom = false}) async {},
      ));
      final done = actions.confirmDeletePlaylistItem(item);
      await tester.pumpAndSettle();
      if (switchProfile) current = false;
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => done);
      final rows = await tester.runAsync(StorageService.getPlaylistItemsRaw);
      return rows!.isNotEmpty;
    }

    testWidgets('a profile switch during the prompt writes nothing', (
      tester,
    ) async {
      expect(await deleteAfterSwitch(tester, switchProfile: true), isTrue);
    });

    testWidgets('the same profile still deletes', (tester) async {
      expect(await deleteAfterSwitch(tester, switchProfile: false), isFalse);
    });
  });

  group('watchlist removal', () {
    Future<int> removeAfterSwitch(
      WidgetTester tester, {
      required bool switchProfile,
    }) async {
      await host(tester);
      var current = true;
      var removals = 0;
      final actions = HomeWatchlistActions(
        (
          mounted: () => true,
          profileCurrent: () => current,
          context: () => hostContext,
          isTelevision: () => false,
          remove: (_) async => removals++,
          reload: () async {},
          addonForContinue: (_) => throw UnimplementedError(),
          refreshAfterPlayback: ({trackers = false}) async {},
        ),
        _FakeIptv(),
        _FakeItems(),
      );
      final done = actions.offerRemoveUnavailableWatchlistItem(
        StremioMeta.fromJson({'id': 'tt1', 'type': 'series', 'name': 'Gone'}),
        message: 'Unavailable',
      );
      await tester.pumpAndSettle();
      if (switchProfile) current = false;
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await done;
      return removals;
    }

    testWidgets('a profile switch during the prompt writes nothing', (
      tester,
    ) async {
      expect(await removeAfterSwitch(tester, switchProfile: true), 0);
    });

    testWidgets('the same profile still removes', (tester) async {
      expect(await removeAfterSwitch(tester, switchProfile: false), 1);
    });
  });
}

// Removal never reaches IPTV or item opening; these only satisfy the constructor.
class _FakeIptv extends Fake implements HomeSavedIptvActions {}

class _FakeItems extends Fake implements HomeItemActions {}
