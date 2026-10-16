import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/iptv_last_channel_storage.dart';
import 'support/iptv_workflow_driver.dart';
import 'support/iptv_storage_driver.dart';

void main() {
  testWidgets(
    'P15 review2 on-demand playing never owns a last-live settle timer',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.mount([iptvChannel(0, live: false)]);
        expect(
          d.timed.where(
            (v) => d.timerOwners[v.$2]!.contains('noteLiveChannelPlaying'),
          ),
          isEmpty,
        );
        expect(
          await d.f.finish(t, IptvLastChannelStorage.getIptvLastLiveChannel()),
          isNull,
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P15 review2 another playing URL replaces the active last-live timer',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.mount([iptvChannel(0), iptvChannel(1)]);
        d.observe(() => d.player.emit('playing', true));
        await d.settle();
        final first = d.timed
            .lastWhere(
              (v) => d.timerOwners[v.$2]!.contains('noteLiveChannelPlaying'),
            )
            .$2;
        expect(first.isActive, true);
        await d.zap(1);
        final second = d.timed
            .lastWhere(
              (v) => d.timerOwners[v.$2]!.contains('noteLiveChannelPlaying'),
            )
            .$2;
        expect(identical(first, second), false);
        expect(first.isActive, false);
        expect(second.isActive, true);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  for (final origin in ['widget', 'guide', 'channel']) {
    testWidgets(
      'P15 review2 last-live storage captures $origin source and headers',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final live = iptvChannel(
          0,
          headers: {'X-P15-Memory': 'stored'},
          attributes: origin == 'channel'
              ? {'source_playlist_id': 'channel-origin'}
              : {},
        );
        try {
          await d.mount([live]);
          if (origin != 'widget') {
            final guide = await d.guide();
            guide.onContextChanged!(
              IptvGuideContext(
                categories: ['News'],
                selectedCategory: 'News',
                sourceId: 'guide-origin',
                sourceName: 'Guide origin',
                contentType: 'live',
              ),
            );
            await d.closeGuide(guide);
          }
          await d.f.finish(
            t,
            IptvLastChannelStorage.clearIptvLastLiveChannel(),
          );
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
          expect(row!['playlistId'], switch (origin) {
            'channel' => 'channel-origin',
            'guide' => 'guide-origin',
            _ => 'launch-source',
          });
          expect(row['httpHeaders'], {'X-P15-Memory': 'stored'});
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final populated in [false, true]) {
    testWidgets(
      'P15 review2 last-live header capture before storage await populated=$populated',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final headers = <String, String>{
          if (populated) 'X-P15-Memory': 'before',
        };
        final live = iptvChannel(0, headers: headers);
        final delivery = IptvAwaitDelivery(
          'setIptvLastLiveChannel',
          (v) => v is ProfilePreferences,
        );
        delivery.armed = false;
        try {
          await delivery.run(() => d.mount([live], source: null));
          await d.f.finish(
            t,
            IptvLastChannelStorage.clearIptvLastLiveChannel(),
          );
          delivery.armed = true;
          d.observe(() => d.player.emit('playing', true));
          await d.settle();
          final timer = d.timed
              .lastWhere(
                (v) => d.timerOwners[v.$2]!.contains('noteLiveChannelPlaying'),
              )
              .$2;
          await d.timerAge(timer, const Duration(seconds: 1));
          await d.f.until(t, () => delivery.pending.isNotEmpty);
          headers['X-P15-Memory'] = 'after';
          delivery.release();
          await d.settle();
          final prefs = await d.f.finish(t, ProfilePreferences.instance());
          await d.f.until(t, () => prefs.containsKey('iptv_last_live_channel'));
          final row = await d.f.finish(
            t,
            IptvLastChannelStorage.getIptvLastLiveChannel(),
          );
          expect(
            row!['httpHeaders'],
            populated ? {'X-P15-Memory': 'after'} : isNull,
          );
          expect(d.errors, isEmpty);
        } finally {
          delivery.release();
          await d.close();
        }
      },
    );
  }
}
