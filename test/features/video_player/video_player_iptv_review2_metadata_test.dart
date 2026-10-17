import 'dart:convert';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/iptv_audio_storage.dart';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';
import 'video_player_iptv_memory_test.dart' show iptvAudioTracks;

void main() {
  for (final origin in ['series', 'source', 'empty-source', 'widget', 'none']) {
    testWidgets(
      'P15 review2 physical metadata and audio key preserve independent origin $origin',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final headers = {'X-Metadata': origin};
        final channel = IptvChannel(
          name: 'Metadata $origin',
          url: 'https://p15-meta.test/$origin.mp4',
          contentType: 'vod',
          group: 'Group title',
          logoUrl: 'https://p15-meta.test/logo.png',
          httpHeaders: headers,
          attributes: {
            'series_id': 'Sid',
            'season': '2',
            'episode': '3',
            if (origin == 'series') 'series_playlist_id': 'SeriesOwner',
            if (origin == 'series' || origin == 'source')
              'source_playlist_id': 'SourceOwner',
            if (origin == 'empty-source') 'source_playlist_id': '',
          },
        );
        try {
          await d.mount([
            iptvChannel(0),
          ], source: origin == 'none' ? null : 'WidgetOwner');
          await d.pick([channel], 0);
          final scope = ProfileRuntime.capture();
          List<Map<String, Object?>> rows = [];
          for (var attempt = 0; attempt < 50 && rows.isEmpty; attempt++) {
            rows = (await t.runAsync(() => iptvPhysicalHistory(d, scope)))!;
            if (rows.isEmpty) {
              await d.advance(const Duration(milliseconds: 50));
            }
          }
          expect(rows, hasLength(1));
          final row = Map<String, Object?>.from(rows.single)
            ..remove('last_played_at');
          expect(row, {
            'url': channel.url,
            'name': channel.name,
            'logo_url': channel.logoUrl,
            'channel_group': channel.group,
            'playlist_id': switch (origin) {
              'series' => 'SeriesOwner',
              'source' => 'SourceOwner',
              'widget' => 'WidgetOwner',
              _ => '',
            },
            'http_headers_json': jsonEncode(headers),
            'series_id': 'Sid',
            'series_name': 'Group title',
            'season': 2,
            'episode': 3,
            'has_next': null,
          });
          iptvAudioTracks(d);
          await d.settle();
          final menu = await openPlayerMenu(t, d.f);
          await d.f.finish(t, menu.onAudioSelected('2', '1'));
          menu.onClose();
          final key = origin == 'series' ? 'SeriesOwner::Sid' : '::Sid';
          expect(
            await d.f.finish(
              t,
              IptvAudioStorage.getIptvSeriesAudioLanguage(key),
            ),
            'fra',
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final initiallyEmpty in [false, true]) {
    testWidgets(
      'P15 review2 history snapshots scalar metadata but borrows nonempty headers initiallyEmpty=$initiallyEmpty',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final headers = <String, String>{
          if (!initiallyEmpty) 'X-Before': 'before',
        };
        final attributes = {
          'series_id': 'BeforeId',
          'series_name': 'Before name',
          'season': '2',
          'episode': '3',
          'has_next_episode': 'true',
          'source_playlist_id': 'BeforeSource',
        };
        final channel = IptvChannel(
          name: 'Mutable metadata',
          url: 'https://p15-meta.test/mutable-$initiallyEmpty.mp4',
          contentType: 'vod',
          attributes: attributes,
          httpHeaders: headers,
        );
        final held = IptvAwaitDelivery('recordIptvWatch', (v) => v == true);
        try {
          await d.mount([iptvChannel(0)]);
          final sheet = await d.guide();
          await d.f.finish(
            t,
            held.run(() => sheet.onChannelSelected([channel], 0)),
          );
          await d.f.until(t, () => held.pending.isNotEmpty);
          attributes.addAll({
            'series_id': 'AfterId',
            'series_name': 'After name',
            'season': '9',
            'episode': '8',
            'has_next_episode': 'false',
            'source_playlist_id': 'AfterSource',
          });
          headers
            ..clear()
            ..['X-Late'] = 'after';
          held.release();
          final scope = ProfileRuntime.capture();
          List<Map<String, Object?>> rows = [];
          for (var attempt = 0; attempt < 50 && rows.isEmpty; attempt++) {
            rows = (await t.runAsync(() => iptvPhysicalHistory(d, scope)))!;
            if (rows.isEmpty) {
              await d.advance(const Duration(milliseconds: 50));
            }
          }
          expect(rows, hasLength(1));
          final row = rows.single;
          expect(row['series_id'], 'BeforeId');
          expect(row['series_name'], 'Before name');
          expect(row['season'], 2);
          expect(row['episode'], 3);
          expect(row['has_next'], 1);
          expect(row['playlist_id'], 'BeforeSource');
          expect(
            row['http_headers_json'],
            initiallyEmpty ? null : jsonEncode({'X-Late': 'after'}),
          );
          expect(d.errors, isEmpty);
        } finally {
          held.release();
          await d.close();
        }
      },
    );
  }
}
