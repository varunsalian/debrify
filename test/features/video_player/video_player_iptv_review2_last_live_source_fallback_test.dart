import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/iptv_last_channel_storage.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 last-live memory falls back to launch source after all-source browsing',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.mount([iptvChannel(0)]);
        final guide = await d.guide();
        guide.onContextChanged!(
          IptvGuideContext(
            categories: ['News'],
            selectedCategory: 'News',
            sourceId: null,
            sourceName: 'All sources',
            contentType: 'live',
          ),
        );
        await d.closeGuide(guide);
        await d.f.finish(t, IptvLastChannelStorage.clearIptvLastLiveChannel());
        d.observe(() => d.player.emit('playing', true));
        await d.settle();
        final timer = d.timed
            .lastWhere(
              (v) => d.timerOwners[v.$2]!.contains('noteLiveChannelPlaying'),
            )
            .$2;
        await d.timerAge(timer, const Duration(seconds: 1));
        final prefs = await d.f.finish(t, ProfilePreferences.instance());
        await d.f.until(t, () => prefs.containsKey('iptv_last_live_channel'));
        final row = await d.f.finish(
          t,
          IptvLastChannelStorage.getIptvLastLiveChannel(),
        );
        expect(row!['playlistId'], 'launch-source');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
