import 'dart:convert';
import 'dart:io';

import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'support/recording_delivery.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recording_driver.dart';

void main() {
  for (final lookup in [
    'fresh',
    'launch',
    'source-attribute',
    'series-attribute',
    'none',
  ]) {
    testWidgets(
      'p13 recording resource $lookup preserves fresh-read precedence and launch fallback',
      (t) async {
        final d = RecordingDriver(t, committed: false);
        await d.setup();
        try {
          SharedPreferences.setMockInitialValues({
            if (lookup == 'fresh')
              'iptv_playlists': [
                jsonEncode({
                  'id': 'p13-source',
                  'name': 'Source',
                  'url': '',
                  'addedAt': '2024-01-01T00:00:00.000',
                  '_connectionResourceId': 'fresh-resource',
                  '_connectionResourceRevision': 8,
                }),
              ],
          });
          final url = await d.loopback();
          await d.mountRecording(
            url: url,
            tee: false,
            sourceId: lookup == 'none' ? null : 'p13-source',
            attributes: lookup == 'source-attribute'
                ? {'source_playlist_id': 'attribute-source'}
                : lookup == 'series-attribute'
                ? {'series_playlist_id': 'attribute-source'}
                : const {},
            sources: [
              {
                'id': 'p13-source',
                'connectionResourceId': 'launch-resource',
                'connectionResourceRevision': 3,
              },
              {
                'id': 'attribute-source',
                'connectionResourceId': 'attribute-resource',
                'connectionResourceRevision': 5,
              },
            ],
          );
          d.native.properties['file-format'] = 'mpegts';
          d.desktopRecord();
          final capture = await d.captured(url);
          expect(
            capture.connectionResourceId,
            lookup == 'fresh'
                ? 'fresh-resource'
                : lookup.endsWith('attribute')
                ? 'attribute-resource'
                : lookup == 'none'
                ? null
                : 'launch-resource',
          );
          expect(
            capture.resourceAuthorizationRevision,
            lookup == 'fresh'
                ? 8
                : lookup.endsWith('attribute')
                ? 5
                : lookup == 'none'
                ? null
                : 3,
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'p13 desktop capacity cancel starts no second capture and never falls through to TEE',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      try {
        await d.f.finish(t, LiveRecordingService.setMaxConcurrent(1));
        final busy = await d.loopback();
        final url = await d.loopback();
        await d.mountRecording(url: url, tee: false);
        final blocker = await d.f.finish(
          t,
          HttpOverrides.runWithHttpOverrides(
            () => DesktopRecordingService.instance.start(
              url: busy,
              path: '${d.f.directory.path}/blocker.ts',
              channelName: 'Busy',
              headers: {},
            ),
            d.realNetwork,
          ),
        );
        d.captures.add(blocker!);
        await d.f.until(t, () => blocker.bytes >= 188);
        d.native.properties['file-format'] = 'mpegts';
        d.desktopRecord();
        await d.f.until(
          t,
          () => find.text('Recording conflict').evaluate().isNotEmpty,
        );
        expect(DesktopRecordingService.instance.activeCount, 1);
        await t.tap(find.text('Cancel'));
        await d.f.actions.settle(t);
        expect(DesktopRecordingService.instance.captureForUrl(url), isNull);
        expect(d.propertyWrites, isEmpty);
        expect(d.paths.reads, 0);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'p13 resource await reads launch selectors live after a public widget update',
    (t) async {
      final d = RecordingDriver(t, committed: false);
      await d.setup();
      final hold = RecordingDelivery((v) => v is List<IptvPlaylist>);
      try {
        final url = await d.loopback();
        await d.mountRecording(
          url: url,
          tee: false,
          sourceId: 'source-p13',
          sources: [
            {
              'id': 'source-p13',
              'connectionResourceId': 'old',
              'connectionResourceRevision': 1,
            },
          ],
        );
        d.native.properties['file-format'] = 'mpegts';
        hold.run(d.desktopRecord);
        await d.f.until(t, () => hold.pending.isNotEmpty);
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: d.f.navigator,
            theme: ThemeData.dark(),
            home: VideoPlayerScreen(
              videoUrl: url,
              title: 'Recording fixture',
              iptvChannels: [d.channel(url)],
              iptvStartIndex: 0,
              iptvSourceId: 'source-p13',
              iptvSources: [
                {
                  'id': 'source-p13',
                  'connectionResourceId': 'new',
                  'connectionResourceRevision': 2,
                },
              ],
            ),
          ),
        );
        await d.f.advance(t);
        hold.release();
        final capture = await d.captured(url);
        expect(capture.connectionResourceId, 'new');
        expect(capture.resourceAuthorizationRevision, 2);
        expect(d.errors, isEmpty);
      } finally {
        hold.release();
        await d.close();
      }
    },
  );
}
