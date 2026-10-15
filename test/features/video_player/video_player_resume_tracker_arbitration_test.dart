import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/local_completion_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  const cases =
      <
        (
          String,
          double?,
          double?,
          double?,
          double,
          double,
          double,
          int,
          WatchProgressSource,
          int,
        )
      >[
        (
          'MDBList equal explicit promise does not replace non-explicit Trakt',
          null,
          10,
          null,
          10,
          10,
          5,
          480000,
          WatchProgressSource.smart,
          480000,
        ),
        (
          'Simkl equal explicit promise does not replace non-explicit Trakt',
          null,
          null,
          10,
          10,
          5,
          10,
          480000,
          WatchProgressSource.smart,
          480000,
        ),
        (
          'larger stored MDBList clears lower Trakt launch promise',
          10,
          null,
          null,
          10,
          20,
          5,
          480000,
          WatchProgressSource.smart,
          480000,
        ),
        (
          'larger stored Simkl clears lower Trakt launch promise',
          10,
          null,
          null,
          10,
          5,
          20,
          480000,
          WatchProgressSource.smart,
          480000,
        ),
        (
          'lower Trakt launch still supplies rewatch provenance after stored MDBList wins the fold',
          20,
          null,
          null,
          0,
          40,
          0,
          1100000,
          WatchProgressSource.smart,
          480000,
        ),
        (
          'local policy masks explicit Trakt launch',
          60,
          null,
          null,
          0,
          0,
          0,
          480000,
          WatchProgressSource.local,
          480000,
        ),
        (
          'Trakt policy masks explicit MDBList launch',
          null,
          40,
          null,
          20,
          0,
          0,
          480000,
          WatchProgressSource.trakt,
          240000,
        ),
        (
          'Trakt policy masks explicit Simkl launch',
          null,
          null,
          50,
          20,
          0,
          0,
          480000,
          WatchProgressSource.trakt,
          240000,
        ),
        (
          'stored remote at exact low boundary starts fresh',
          null,
          null,
          null,
          1 / 6,
          0,
          0,
          0,
          WatchProgressSource.smart,
          0,
        ),
        (
          'stored remote at exact high boundary starts fresh',
          null,
          null,
          null,
          90,
          0,
          0,
          0,
          WatchProgressSource.smart,
          0,
        ),
        (
          'exact local completion blocks a non-explicit MDBList partial',
          null,
          null,
          null,
          0,
          20,
          0,
          1080000,
          WatchProgressSource.smart,
          0,
        ),
        (
          'Trakt partial migrates legacy completion to a rewatch',
          null,
          null,
          null,
          20,
          0,
          0,
          1100000,
          WatchProgressSource.smart,
          240000,
        ),
        (
          'independent Simkl completion prevents Trakt rewatch migration',
          null,
          null,
          null,
          20,
          0,
          100,
          1100000,
          WatchProgressSource.smart,
          0,
        ),
        (
          'independent MDBList completion prevents Trakt rewatch migration',
          null,
          null,
          null,
          20,
          100,
          0,
          1100000,
          WatchProgressSource.smart,
          0,
        ),
        (
          'local policy masks every foreign rewatch input',
          null,
          null,
          null,
          20,
          0,
          0,
          1100000,
          WatchProgressSource.local,
          0,
        ),
        (
          'Trakt policy ignores newer local position but restores presentation',
          null,
          null,
          null,
          20,
          100,
          100,
          480000,
          WatchProgressSource.trakt,
          240000,
        ),
        (
          'NaN leading candidate masks a valid lower provider as in the original',
          double.nan,
          20,
          null,
          0,
          0,
          0,
          0,
          WatchProgressSource.smart,
          0,
        ),
        (
          'infinite leading candidate masks a valid lower provider as in the original',
          double.infinity,
          20,
          null,
          0,
          0,
          0,
          0,
          WatchProgressSource.smart,
          0,
        ),
        (
          '100 percent leading candidate rejects a lower valid promise',
          100,
          20,
          null,
          0,
          0,
          0,
          300000,
          WatchProgressSource.smart,
          300000,
        ),
      ];
  for (final (
        label,
        trakt,
        mdb,
        simkl,
        tStore,
        mStore,
        sStore,
        local,
        policy,
        expected,
      )
      in cases) {
    testWidgets('Resume P14 tracker arbitration $label', (t) async {
      final f = VideoPlayerEnvironment();
      final d = LocalCompletionDriver(t, f);
      await d.initialize();
      const id = 'tt1412001', url = 'https://player.test/p14-trackers.mp4';
      try {
        await f.finish(
          t,
          TrackerEpisodeProgressStorage.saveEpisodeTraktProgress(
            imdbId: id,
            percents: {'2_3': tStore},
          ),
        );
        await f.finish(
          t,
          TrackerEpisodeProgressStorage.saveEpisodeMdblistProgress(
            imdbId: id,
            percents: {'2_3': mStore},
          ),
        );
        await f.finish(
          t,
          TrackerEpisodeProgressStorage.saveEpisodeSimklProgress(
            imdbId: id,
            percents: {'2_3': sStore},
          ),
        );
        await f.finish(t, TrackingSourceStorage.setWatchProgressSource(policy));
        await f.finish(
          t,
          VideoResumeStorage.upsertVideoResume(url, {
            'positionMs': local,
            'speed': 1.5,
            'aspect': 'contain',
          }),
        );
        await f.mount(
          t,
          VideoPlayerScreen(
            videoUrl: url,
            title: 'P14 tracker arbitration',
            contentImdbId: id,
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
            traktProgressPercent: trakt,
            mdblistProgressPercent: mdb,
            simklProgressPercent: simkl,
          ),
        );
        await f.actions.settle(t);
        final seeks = f.player.calls
            .where((c) => c.$1 == 'seek')
            .map((c) => (c.$2 as Duration).inMilliseconds);
        expect(seeks, expected == 0 ? isEmpty : [expected]);
        expect(
          f.player.calls.where((c) => c.$1 == 'rate').map((c) => c.$2),
          contains(1.5),
          reason: 'Progress ownership gates position, never the stored speed',
        );
        expect(
          await f.finish(t, TrackingSourceStorage.getWatchProgressSource()),
          policy,
        );
      } finally {
        await d.close();
      }
    });
  }
}
