import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/playlist_content_view_screen.dart';
import 'package:debrify/screens/profiles/profile_gate.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../support/playlist_content_fixture.dart';
import '../../../pikpak_files/presentation/legacy_pikpak/pikpak_profile_test.dart'
    show ProfileFixture;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  testWidgets(
    'real ProfileGate picker disposes content route back handler and timers',
    (t) => playlistContentCase(t, (f) async {
      final p = ProfileFixture();
      await t.runAsync(p.open);
      try {
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: f.navigatorKey,
            home: const ProfileGate(child: Scaffold(body: Text('Gate child'))),
          ),
        );
        await f.until(t, () => find.text('Gate child').evaluate().isNotEmpty);
        late String b;
        await t.runAsync(() async {
          final admin = (await p.registry.getProfile(p.a))!;
          b = (await p.registry.createProfile(
            name: 'B',
            role: UserProfileRole.member,
            actingProfileId: p.a,
            actingAuthorizationRevision: admin.authorizationRevision,
            actingSessionEpoch: ProfileRuntime.capture().sessionEpoch,
          )).id;
        });
        f.item['provider'] = 'webdav';
        f.navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                PlaylistContentViewScreen(key: f.key, playlistItem: f.item),
          ),
        );
        await t.pump();
        await f.until(
          t,
          () =>
              f.key.currentState != null &&
              f.member('currentViewNodes') != null,
        );
        await t.pump(const Duration(milliseconds: 600));
        f.member('applyViewMode')(FolderViewMode.seriesArrange);
        await t.pump();
        final state = f.key.currentState!;
        final timer = f.member('ottViewAutoSwitchTimer');
        expect(timer.isActive, isTrue);
        var sentinelCalls = 0;
        bool sentinel() {
          sentinelCalls++;
          return true;
        }

        MainPageBridge.registerTabBackHandler('playlist', sentinel);
        MainPageBridge.setActiveTab('playlist');
        try {
          MainPageBridge.switchProfile!(b);
          await t.pump();
          await t.pump(const Duration(milliseconds: 600));
          await f.until(t, () => !state.mounted);
          await f.until(t, () => ProfileRuntime.capture().profileId == b);
          expect(f.key.currentState, isNull);
          expect(timer.isActive, isFalse);
          expect(MainPageBridge.handleBackNavigation(), isTrue);
          expect(sentinelCalls, 1);
          await t.pump(const Duration(seconds: 3));
        } finally {
          MainPageBridge.unregisterTabBackHandler('playlist', sentinel);
        }
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        await t.runAsync(p.close);
        ProfileRuntime.initializeLegacy();
      }
    }),
  );
}
