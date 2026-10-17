import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/pip_lifecycle_driver.dart';
import 'support/player_actions.dart';
import 'support/trakt_transport.dart';
import 'support/tv_episode_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  for (final route in ['next', 'by id']) {
    testWidgets(
      'P17 $route channel updates the URI used by real renderer replacement',
      (t) async {
        final f = VideoPlayerEnvironment(native: true);
        final d = _ChannelRendererDriver(t, f);
        await d.initialize();
        try {
          await f.finish(
            t,
            PlayerSettingsStorage.setAndroidVideoRendererMode(
              AndroidVideoRendererMode.directSurface,
            ),
          );
          await d.mount(
            VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              channelDirectory: tvDirectory,
              requestChannelById: (id) async => {
                'url': 'https://player.test/b.mp4',
              },
              requestNextChannel: () async => {
                'url': 'https://player.test/b.mp4',
              },
            ),
          );
          if (route == 'next') {
            final dynamic action = playerControls(t).onNextChannel!;
            await f.finish<dynamic>(t, d.observe<dynamic>(() => action()));
          } else {
            playerControls(t).onShowGuide!();
            await f.until(
              t,
              () => find.byType(ChannelGuide).evaluate().isNotEmpty,
            );
            final guide = t.widget<ChannelGuide>(find.byType(ChannelGuide));
            final dynamic pick = guide.onChannelSelected;
            await f.finish<dynamic>(
              t,
              d.observe<dynamic>(() => pick(guide.channels.last)),
            );
          }
          expect(
            f.player.state.playlist.medias.single.uri,
            'https://player.test/b.mp4',
          );
          final old = f.player;
          old.emit('error', 'synthetic MediaCodec video output failure');
          await f.until(t, () => f.players.length == 2);
          final fresh = f.player;
          fresh.deliverReady();
          await f.until(t, () => fresh.calls.any((c) => c.$1 == 'open'));
          await d.settle();
          expect(old.disposed.isCompleted, isTrue);
          expect(
            fresh.state.playlist.medias.single.uri,
            'https://player.test/b.mp4',
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}

class _ChannelRendererDriver extends PipLifecycleDriver {
  _ChannelRendererDriver(super.t, super.f);
  final _captured = P17ObservedErrors();
  @override
  List<Object> get errors => _captured;
}
