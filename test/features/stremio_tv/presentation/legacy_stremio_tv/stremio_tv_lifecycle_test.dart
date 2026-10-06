import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/stremio_tv_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_tuner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/stremio_tv_fixture.dart';
import '../../../../support/debrify_tv_handoff.dart';

void main() {
  testWidgets(
    'C3 (O) P2 original RD route is captured without mounting a player',
    (t) async {
      await stremioTvCase(t, (f) async {
        await f.mount(t);
        await f.play(t);
        expect(f.observer.players, hasLength(1));
        expect(find.byType(VideoPlayerScreen), findsNothing);
        final p = f.observer.players.single;
        expect(p.videoUrl, 'https://video.test/original.mp4');
        expect(p.stremioTvCurrentChannelId, f.channelId(1));
        expect(p.startAtPercent, isNull);
        expect(p.contentImdbId, f.meta(1).effectiveImdbId);
        expect(p.title, f.meta(1).name);
        expect(p.stremioSources, hasLength(2));
        expect(p.stremioCurrentSourceIndex, 0);
        expect(debrifyTvPlayerFields(p)['requestMagicNext'], isNull);
        final paths = f.requests.map((r) => r.url.path).toList();
        expect(paths.any((p) => p.contains('/stream/movie/')), isTrue);
        expect(
          paths
              .where(
                (p) =>
                    p.contains('/torrents/') || p.endsWith('/unrestrict/link'),
              )
              .toList(),
          [
            '/rest/1.0/torrents/addMagnet',
            '/rest/1.0/torrents/info/original-1',
            '/rest/1.0/torrents/selectFiles/original-1',
            '/rest/1.0/torrents/info/original-1',
            '/rest/1.0/unrestrict/link',
            '/rest/1.0/unrestrict/link',
          ],
        );
      });
    },
  );
  testWidgets('C1 (R/O) lifecycle hooks focus filtering and disposal', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      await f.mount(t);
      expect(MainPageBridge.watchStremioTvChannel, isNotNull);
      expect(MainPageBridge.requestTvContentFocus(), isTrue);
      await t.pump();
      expect(f.node('searchBtn').hasFocus, isTrue);
      await f.key(t, LogicalKeyboardKey.enter);
      await t.enterText(find.byType(EditableText), ' channel 2 ');
      await f.settle(t);
      expect(f.tuner(t).channels.map((c) => c.id), [f.channelId(2)]);
      await t.pumpWidget(const SizedBox());
      await f.settle(t);
      expect(MainPageBridge.watchStremioTvChannel, isNull);
      expect(MainPageBridge.requestTvContentFocus(), isFalse);
    });
  });
  testWidgets(
    'C4 (R/O) unavailable provider resets and available menu persists',
    (t) async {
      await stremioTvCase(t, (f) async {
        await t.runAsync(() async {
          await TorboxStorage.saveTorboxApiKey('original-torbox');
          await TorboxStorage.setTorboxIntegrationEnabled(true);
          await StremioTvStorage.setStremioTvDebridProvider('premiumize');
        });
        await f.mount(t);
        expect(
          await t.runAsync(StremioTvStorage.getStremioTvDebridProvider),
          'auto',
        );
        f.node('providerBtn').requestFocus();
        await t.pump();
        await f.key(t, LogicalKeyboardKey.enter);
        expect(find.text('Auto (Real-Debrid)'), findsOneWidget);
        expect(find.text('Premiumize'), findsNothing);
        await f.tap(t, find.widgetWithText(MenuItemButton, 'TorBox'));
        expect(
          await t.runAsync(StremioTvStorage.getStremioTvDebridProvider),
          'torbox',
        );
        expect(find.text('TB'), findsOneWidget);
      });
    },
  );
  testWidgets('C8 (R/O) header directional keys and search Escape ladder', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      await f.mount(t);
      f.node('searchBtn').requestFocus();
      await t.pump();
      await f.key(t, LogicalKeyboardKey.arrowLeft);
      expect(f.probes, contains('sidebar'));
      await f.key(t, LogicalKeyboardKey.arrowRight);
      expect(f.node('menuBtn').hasFocus, isTrue);
      await f.key(t, LogicalKeyboardKey.arrowLeft);
      expect(f.node('searchBtn').hasFocus, isTrue);
      await f.key(t, LogicalKeyboardKey.enter);
      await t.enterText(find.byType(EditableText), 'original');
      await f.settle(t);
      await f.key(t, LogicalKeyboardKey.escape);
      expect(
        t.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty,
      );
      await f.key(t, LogicalKeyboardKey.escape);
      expect(find.byType(EditableText), findsNothing);
      expect(f.node('searchBtn').hasFocus, isTrue);
      await f.key(t, LogicalKeyboardKey.arrowDown);
      expect(f.node('searchBtn').hasFocus, isFalse);
      expect(find.byType(StremioTvTuner), findsOneWidget);
    });
  });
}
