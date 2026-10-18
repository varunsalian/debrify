import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
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
  testWidgets(
    'P17 old-instance duration listener seeks live replacement after Stremio channel pick',
    (t) async {
      final f = VideoPlayerEnvironment(native: true);
      final d = _P17RendererDriver(t, f);
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
            stremioTvChannels: tvDirectory,
            stremioTvChannelSwitchProvider: (id) async => null,
          ),
        );
        playerControls(t).onShowGuide!();
        await f.until(
          t,
          () => find.byType(StremioTvGuideSheet).evaluate().isNotEmpty,
        );
        final dynamic pick = t
            .widget<StremioTvGuideSheet>(find.byType(StremioTvGuideSheet))
            .onChannelSwitched;
        await f.finish<dynamic>(
          t,
          d.observe<dynamic>(
            () => pick(
              'b',
              'https://player.test/b.mp4',
              'B',
              startAtPercent: 0.4,
            ),
          ),
        );
        final old = f.player;
        old.emit('error', 'synthetic MediaCodec video output failure');
        await f.until(t, () => f.players.length == 2);
        final fresh = f.player;
        fresh.deliverReady();
        await f.until(t, () => fresh.calls.any((c) => c.$1 == 'open'));
        await d.settle();
        expect(old.disposed.isCompleted, isTrue);
        final before = fresh.calls.where((c) => c.$1 == 'seek').length;
        old.emit('duration', const Duration(seconds: 300));
        await f.advance(t);
        expect(
          fresh.calls
              .where((c) => c.$1 == 'seek')
              .skip(before)
              .map((c) => c.$2),
          [const Duration(seconds: 120)],
        );
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

class _P17RendererDriver extends PipLifecycleDriver {
  _P17RendererDriver(super.t, super.f);
  final _captured = P17ObservedErrors();
  @override
  List<Object> get errors => _captured;
}
