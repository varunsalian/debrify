import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_collection_resource_facade.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_driver.dart';

void main() {
  testWidgets(
    'p13 recording disabled committed source is absent from the fresh resource binding',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      try {
        await d.f.finish(
          t,
          IptvPlaylistStorage.setIptvPlaylists([
            IptvPlaylist(
              id: 'p13-disabled',
              name: 'Disabled playback source',
              url: 'https://player.test/playlist.m3u',
              addedAt: DateTime(2024),
            ),
          ]),
        );
        final source = (await d.f.finish(
          t,
          IptvPlaylistStorage.getIptvPlaylists(forSettings: true),
        )).single;
        await d.f.finish(
          t,
          ProfileCollectionResourceFacade.setLocalEnabled(
            resourceId: source.connectionResourceId!,
            resourceRevision: source.connectionResourceRevision!,
            feature: ProfileFeature.iptv,
            enabled: false,
          ),
        );
        expect(
          await d.f.finish(
            t,
            IptvPlaylistStorage.getIptvPlaylists(forSettings: false),
          ),
          isEmpty,
        );
        final url = await d.loopback();
        await d.mountRecording(url: url, tee: false, sourceId: source.id);
        d.native.properties['file-format'] = 'mpegts';
        d.desktopRecord();
        final capture = await d.captured(url);
        expect(capture.connectionResourceId, isNull);
        expect(capture.resourceAuthorizationRevision, isNull);
        final jobs = await d.f.finish(t, d.f.registry!.listJobOwnership());
        final job = jobs.singleWhere(
          (job) => job['external_job_id'] == capture.jobId,
        );
        expect(job, contains('resource_id'));
        expect(job['resource_id'], isNull);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
