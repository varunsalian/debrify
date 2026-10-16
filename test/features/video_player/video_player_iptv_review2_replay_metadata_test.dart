import 'dart:convert';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final origin in [
    'channel',
    'empty-channel',
    'guide',
    'widget',
    'none',
  ]) {
    testWidgets(
      'P15 review2 replay captures physical metadata before its second owner write origin=$origin',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final channel = IptvChannel(
          name: 'Station $origin',
          url: 'https://p15-replay-meta-$origin.test/live/u/p/123.ts',
          contentType: 'live',
          logoUrl: 'https://p15-replay-meta.test/logo.png',
          group: 'News',
          httpHeaders: {'X-Replay-Origin': origin},
          attributes: {
            if (origin == 'channel') 'source_playlist_id': 'ChannelOwner',
            if (origin == 'empty-channel') 'source_playlist_id': '',
          },
        );
        final hold = IptvAwaitDelivery('_playIptvCatchup', (v) => v == null);
        d.response = iptvPanelReply;
        Future<void>? work;
        try {
          await d.mount([
            channel,
          ], source: origin == 'none' ? null : 'WidgetOwner');
          final sheet = await d.guide();
          sheet.onContextChanged!(
            IptvGuideContext(
              sourceId: ['channel', 'empty-channel', 'guide'].contains(origin)
                  ? 'GuideOwner'
                  : null,
              sourceName: 'Replay guide',
              categories: ['News'],
              selectedCategory: 'News',
              contentType: 'live',
            ),
          );
          await d.settle();
          final programme = iptvProgramme();
          work = hold.run(
            () => d.observe(() => sheet.onPlayProgramme!(channel, programme)),
          );
          await d.f.until(t, () => hold.pending.isNotEmpty);
          final scope = ProfileRuntime.capture();
          final rows = (await t.runAsync(() => iptvPhysicalHistory(d, scope)))!;
          expect(rows, hasLength(1));
          final row = Map<String, Object?>.from(rows.single)
            ..remove('last_played_at');
          final expectedSource = switch (origin) {
            'channel' => 'ChannelOwner',
            'guide' => 'GuideOwner',
            'widget' => 'WidgetOwner',
            _ => '',
          };
          expect(row, {
            'url': contains('/timeshift/'),
            'name': programme.title,
            'logo_url': channel.logoUrl,
            'channel_group': channel.name,
            'playlist_id': expectedSource,
            'http_headers_json': jsonEncode(channel.httpHeaders),
            'series_id': null,
            'series_name': null,
            'season': null,
            'episode': null,
            'has_next': null,
          });
          expect(d.playingUrl, channel.url);
          hold.release();
          await d.f.finish(t, work!);
          await d.advance(const Duration(milliseconds: 400));
          expect(find.textContaining('Preparing replay'), findsNothing);
          final replay = await d.guide();
          expect(replay.channels, hasLength(1));
          expect(replay.channels.single.contentType, 'vod');
          expect(replay.channels.single.name, programme.title);
          expect(replay.channels.single.group, channel.name);
          expect(replay.channels.single.logoUrl, channel.logoUrl);
          expect(replay.channels.single.httpHeaders, channel.httpHeaders);
          expect(
            replay.channels.single.attributes,
            origin == 'none' ? isEmpty : {'source_playlist_id': expectedSource},
          );
          expect(d.playingUrl, contains('/timeshift/'));
          final finalRows = (await t.runAsync(
            () => iptvPhysicalHistory(d, scope),
          ))!;
          expect(finalRows.single['playlist_id'], expectedSource);
          expect(d.errors, isEmpty);
        } finally {
          hold.release();
          if (work != null) await d.f.finish(t, work);
          await d.close();
        }
      },
    );
  }
}
