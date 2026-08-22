import 'dart:async';
import 'dart:io';

import 'package:debrify/screens/video_player/services/media_kit_audio_feature_tap.dart';
import 'package:debrify/screens/video_player/services/media_kit_subtitle_auto_sync.dart';
import 'package:debrify/screens/video_player/services/subtitle_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'subtitle deactivation cannot strand an in-flight filter install',
    () async {
      final directory = await Directory.systemTemp.createTemp('autosync-race-');
      addTearDown(() => directory.delete(recursive: true));
      final subtitle = File('${directory.path}/track.srt');
      await subtitle.writeAsString(
        '1\n00:00:01,000 --> 00:00:03,000\nA spoken line.\n',
      );

      final tap = _BlockingTap();
      final notices = <SubtitleAutoSyncNotice>[];
      final controller = MediaKitSubtitleAutoSync.forTesting(
        tap: tap,
        enabled: true,
        currentPositionMs: () => 0,
        isPlaying: () => true,
        currentOffsetMs: () => 0,
        applyOffsetMs: (_) async {},
        onNotice: notices.add,
      );
      addTearDown(controller.dispose);

      final activation = controller.activateSubtitle(subtitle.path);
      await tap.installStarted.future;
      final deactivation = controller.deactivateSubtitle();
      tap.allowInstall.complete();
      await Future.wait(<Future<void>>[activation, deactivation]);

      expect(tap.installed, isFalse);
      expect(tap.installCalls, 1);
      expect(tap.uninstallCalls, greaterThanOrEqualTo(1));
      expect(notices, isEmpty);
    },
  );
}

class _BlockingTap implements MediaKitAudioFeatureTap {
  final Completer<void> installStarted = Completer<void>();
  final Completer<void> allowInstall = Completer<void>();

  int installCalls = 0;
  int uninstallCalls = 0;
  bool _installed = false;

  @override
  double get anchoredDurationMs => 0;

  @override
  bool get installed => _installed;

  @override
  Future<bool> install() async {
    installCalls++;
    installStarted.complete();
    await allowInstall.future;
    _installed = true;
    return true;
  }

  @override
  Future<void> uninstall() async {
    uninstallCalls++;
    _installed = false;
  }

  @override
  void reset({int? anchorMs}) {}

  @override
  Future<void> resetForAudioTrack({required int anchorMs}) async {}

  @override
  bool observePosition(int positionMs) => false;

  @override
  List<AudioFeatureSegment> snapshot() => const <AudioFeatureSegment>[];

  @override
  void ingestMetadata(Map<String, String> metadata) {}

  @override
  Future<void> dispose() async {
    await uninstall();
  }
}
