import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/subtitle_apply_driver.dart';

void main() {
  for (final id in ['4', '5']) {
    for (final mode in [
      AndroidVideoRendererMode.directSurface,
      AndroidVideoRendererMode.directMediaCodec,
    ]) {
      for (final tv in [false, true]) {
        testWidgets(
          'subtitle Android ${id == '4' ? 'bitmap codec' : 'image'} renderer ${mode.name} ${tv ? 'TV exempt' : 'phone'} selection preserves rejection and native visibility',
          (t) async {
            final d = SubtitleApplyDriver(t);
            await d.initialize();
            try {
              VpS2Hooks.install(
                VpS2Hooks(android: () => true, ios: () => false),
              );
              PlatformUtil.debugSetAndroidTvCached(tv);
              await d.f.finish(
                t,
                PlayerSettingsStorage.setAndroidVideoRendererMode(mode),
              );
              await d.mount();
              final panel = await d.menu();
              d.native.calls.clear();
              d.player.calls.clear();
              final allowed =
                  tv || mode == AndroidVideoRendererMode.directMediaCodec;
              expect(await d.select(id, panel: panel), allowed);
              expect(d.player.state.track.subtitle.id, allowed ? id : '1');
              final applications = d.player.calls
                  .where((v) => v.$1 == 'subtitle')
                  .map((v) => (v.$2 as mk.SubtitleTrack).id);
              expect(applications, allowed ? [id] : isEmpty);
              final visibility = d.native.calls
                  .where(
                    (v) =>
                        v.$1 == 'setProperty' &&
                        (v.$2 as (String, String)).$1 == 'sub-visibility',
                  )
                  .map((v) => (v.$2 as (String, String)).$2);
              expect(visibility, allowed ? ['yes'] : isEmpty);
              if (allowed) {
                expect((await d.saved())?['subtitleTrackId'], id);
              } else {
                expect(await d.saved(), isNull);
                expect(
                  find.text(
                    'Bitmap subtitles require MediaCodec + GPU. Change Video renderer in Settings and restart playback.',
                  ),
                  findsOneWidget,
                );
                expect(
                  d.logs.where(
                    (v) =>
                        v ==
                        '[SubtitleDiag] apply rejected source=player-menu-embedded reason=android_renderer_incompatible',
                  ),
                  hasLength(1),
                );
              }
              expect(d.errors, isEmpty);
            } finally {
              await d.close();
              VpS2Hooks.install(null);
              PlatformUtil.debugSetAndroidTvCached(false);
            }
          },
        );
      }
    }
  }
}
