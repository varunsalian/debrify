import 'package:debrify/services/storage/iptv_audio_storage.dart';
import 'support/iptv_workflow_driver.dart';
import 'video_player_iptv_memory_test.dart' show iptvEpisode, iptvAudioTracks;

void main() {
  testWidgets(
    'P15 subtitle-only menu change captures current series audio through the retained menu callback',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.mount([iptvEpisode(1)]);
        iptvAudioTracks(d);
        await d.settle();
        final m = await openPlayerMenu(t, d.f);
        expect(
          d.timed
              .where((v) => v.$1 == const Duration(milliseconds: 4500))
              .every((v) => !v.$2.isActive),
          true,
        );
        expect(
          await d.f.finish(t, m.onEmbeddedSubtitleSelected('1', '2')),
          true,
        );
        await d.settle();
        expect(
          await d.f.finish(
            t,
            IptvAudioStorage.getIptvSeriesAudioLanguage('provider::series'),
          ),
          'fra',
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 opening the unified menu on live IPTV cancels its floating banner timer',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.mount([iptvChannel(0)]);
        final hide = d.timed
            .lastWhere((v) => v.$1 == const Duration(milliseconds: 4500))
            .$2;
        expect(hide.isActive, true);
        final menu = await openPlayerMenu(t, d.f);
        expect(hide.isActive, false);
        menu.onClose();
        await d.settle();
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
