import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'support/display_mode_driver.dart';
import 'support/fake_player.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

void main() {
  const url = 'https://player.test/p14-keys.mp4';
  const cases = <(String, PlaylistEntry, String)>[
    (
      'torbox web before torrent',
      PlaylistEntry(
        url: url,
        title: 'Resume keys.mkv',
        provider: 'ToRbOx',
        torboxWebDownloadId: 11,
        torboxTorrentId: 22,
        torboxFileId: 33,
      ),
      'torbox_web_11_33',
    ),
    (
      'torbox torrent',
      PlaylistEntry(
        url: url,
        title: 'Resume keys.mkv',
        provider: 'torbox',
        torboxTorrentId: 22,
        torboxFileId: 33,
      ),
      'torbox_22_33',
    ),
    (
      'torbox missing file',
      PlaylistEntry(
        url: url,
        title: 'Resume keys.mkv',
        provider: 'torbox',
        torboxTorrentId: 22,
      ),
      'hash',
    ),
    (
      'pikpak case insensitive',
      PlaylistEntry(
        url: url,
        title: 'Resume keys.mkv',
        provider: 'PiKpAk',
        pikpakFileId: 'p14-file',
      ),
      'pikpak_p14-file',
    ),
    (
      'pikpak empty id',
      PlaylistEntry(
        url: url,
        title: 'Resume keys.mkv',
        provider: 'pikpak',
        pikpakFileId: '',
      ),
      'hash',
    ),
    (
      'pikpak missing id',
      PlaylistEntry(url: url, title: 'Resume keys.mkv', provider: 'pikpak'),
      'hash',
    ),
    (
      'foreign provider ignores torbox ids',
      PlaylistEntry(
        url: url,
        title: 'Resume keys.mkv',
        provider: 'other',
        torboxTorrentId: 22,
        torboxFileId: 33,
      ),
      'hash',
    ),
    (
      'empty filename uses launch title',
      PlaylistEntry(url: url, title: ''),
      'launch-hash',
    ),
  ];
  for (final (label, entry, rawKey) in cases) {
    testWidgets(
      'Resume P14 key $label restores and saves the selected identity',
      (t) async {
        final f = VideoPlayerEnvironment(native: true);
        await t.runAsync(f.initialize);
        final previousPrint = debugPrint;
        final logs = <String>[];
        debugPrint = (message, {wrapWidth}) {
          logs.add(message ?? '');
          previousPrint(message, wrapWidth: wrapWidth);
        };
        final key = rawKey == 'hash'
            ? 'Resume keys'.hashCode.toString()
            : rawKey == 'launch-hash'
            ? 'Launch title'.hashCode.toString()
            : rawKey;
        try {
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(key, {
              'positionMs': 180000,
              'speed': 1.5,
              'aspect': '4:3',
            }),
          );
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(url, {
              'positionMs': 60000,
              'speed': 0.5,
              'aspect': 'contain',
            }),
          );
          await f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: url,
              title: 'Launch title',
              playlist: [entry],
            ),
          );
          await f.until(t, () => f.player.calls.any((c) => c.$1 == 'seek'));
          expect(
            f.player.calls.where((c) => c.$1 == 'seek').map((c) => c.$2),
            contains(const Duration(minutes: 3)),
          );
          final display = DisplayModeDriver(t, f);
          expect((await display.menu(PlayerMenuSection.speed)).speed, 1.5);
          await display.closeMenu();
          expect(playerControls(t).speed, 1.5);
          display.expectAspect(AspectMode.aspect4_3, BoxFit.cover, 4 / 3);
          expect(
            (f.player.platform as FakeNativePlayer).properties['video-zoom'],
            '0.000000',
          );
          playerControls(t).onPlayPause();
          await f.until(t, () => !f.player.state.playing);
          final state = await f.finish(
            t,
            VideoProgressStorage.getVideoPlaybackState(videoTitle: key),
          );
          expect(state?['positionMs'], 180000);
          expect(state?['speed'], 1.5);
          expect(state?['aspect'], '4:3');
          expect(state?['url'], url);
          expect(
            logs,
            contains(
              'Resume Save: storing state resumeId=$key pos=180000 dur=1200000',
            ),
          );
          final diagnostic = rawKey.startsWith('torbox_web')
              ? 'ResumeKey: using torbox key $key for index 0'
              : rawKey.startsWith('torbox_')
              ? 'ResumeKey: using torbox key $key for index 0'
              : rawKey.startsWith('pikpak_')
              ? 'ResumeKey: using pikpak key $key for index 0'
              : 'ResumeKey: using playlist entry id $key for index 0';
          expect(logs, contains(diagnostic));
          if (rawKey.startsWith('torbox_') || rawKey.startsWith('pikpak_')) {
            expect(
              logs,
              isNot(
                contains('ResumeKey: using playlist entry id $key for index 0'),
              ),
            );
          }
          const helperDiagnostics = {
            'torbox web before torrent':
                'ResumeKey: torbox web download detected web=11 file=33',
            'torbox torrent':
                'ResumeKey: torbox entry detected torrent=22 file=33',
            'torbox missing file':
                'ResumeKey: torbox entry missing IDs torrent=22 web=null file=null',
            'pikpak case insensitive':
                'ResumeKey: pikpak entry detected fileId=p14-file',
            'pikpak empty id': 'ResumeKey: pikpak entry missing fileId',
            'pikpak missing id': 'ResumeKey: pikpak entry missing fileId',
          };
          if (helperDiagnostics.containsKey(label)) {
            expect(logs, contains(helperDiagnostics[label]));
          }

          expect(
            (await f.finish(
              t,
              VideoResumeStorage.getVideoResume(url),
            ))?['positionMs'],
            60000,
          );
        } finally {
          debugPrint = previousPrint;
          await f.close(t);
        }
      },
    );
  }
}
