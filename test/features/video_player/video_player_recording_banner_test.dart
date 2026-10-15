import 'dart:async';
import 'package:debrify/screens/video_player/widgets/iptv_zap_banner.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/recording_driver.dart';

void main() {
  for (final twin in [false, true]) {
    testWidgets(
      'p13 recording banner and dock measurement generation follow live capture state twin=$twin',
      (t) async {
        final d = RecordingDriver(t);
        await d.setup();
        try {
          final base = await d.loopback();
          final url = twin
              ? '${Uri.parse(base).origin}/live/user/password/42.m3u8'
              : base;
          await d.mountRecording(url: url, tee: false);
          d.native.properties['file-format'] = twin ? 'hls' : 'mpegts';
          await d.f.actions.settle(t);
          await d.f.advance(t);
          final before = playerControls(t).infoPanelGeneration;
          expect(
            (playerControls(t).infoPanel as IptvZapBanner).isRecording,
            isFalse,
          );
          d.desktopRecord();
          final capture = await d.captured(
            twin ? LiveRecordingService.xtreamTsTwin(url)! : url,
          );
          await d.started();
          await d.f.advance(t);
          expect(
            (playerControls(t).infoPanel as IptvZapBanner).isRecording,
            isTrue,
          );
          expect(playerControls(t).infoPanelGeneration, greaterThan(before));
          final recordingGeneration = playerControls(t).infoPanelGeneration;
          d.desktopRecord();
          await d.f.until(t, () => !capture.isActive);
          await d.f.advance(t);
          expect(
            (playerControls(t).infoPanel as IptvZapBanner).isRecording,
            isFalse,
          );
          expect(
            playerControls(t).infoPanelGeneration,
            greaterThan(recordingGeneration),
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'p13 desktop HTTPS admission reaches directory work before a disposed caller is rejected',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      try {
        await d.mountRecording(
          url: 'https://player.test/channel.ts',
          tee: false,
        );
        d.native.properties['file-format'] = 'mpegts';
        d.paths.gate = Completer<String?>();
        d.desktopRecord();
        await d.f.until(t, () => d.paths.reads == 1);
        expect(d.active, isFalse);
        await d.removePlayer();
        d.paths.gate!.complete(d.paths.path);
        await d.f.actions.settle(t);
        expect(d.propertyWrites, isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
