import 'dart:convert';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/tv_episode_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  TraktTestTransport.install();
  for (final launchIdentity in [true, false]) {
    testWidgets(
      'P17 tracker launch A to Stremio B launchIdentity=$launchIdentity preserves actual session targets',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = _P17TrackerDriver(t, f);
        await d.initialize(
          targets: {
            TrackingSource.trakt,
            TrackingSource.simkl,
            TrackingSource.mdblist,
          },
        );
        try {
          await d.mount(
            VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Launch A',
              contentImdbId: launchIdentity ? 'tt5100000' : null,
              contentType: 'series',
              contentSeason: 1,
              contentEpisode: 2,
              traktScrobble: true,
              simklScrobble: true,
              mdblistScrobble: true,
              stremioTvChannels: tvDirectory,
              stremioTvCurrentChannelId: 'a',
              stremioTvChannelSwitchProvider: (id) async => null,
            ),
          );
          await d.drain();
          final before = {
            for (final name in ['trakt', 'simkl', 'mdblist'])
              name: d.forTracker(name).length,
          };
          playerControls(t).onShowGuide!();
          await f.until(
            t,
            () => find.byType(StremioTvGuideSheet).evaluate().isNotEmpty,
          );
          final g = t.widget<StremioTvGuideSheet>(
            find.byType(StremioTvGuideSheet),
          );
          final dynamic callback = g.onChannelSwitched;
          await f.finish<dynamic>(
            t,
            d.observe<dynamic>(
                  () => callback(
                    'b',
                    'https://player.test/b.mp4',
                    'Channel B',
                    contentImdbId: 'tt2222222',
                    contentType: 'series',
                    contentSeason: 3,
                    contentEpisode: 4,
                  ),
                )
                as Future<dynamic>,
          );
          expect(
            f.player.state.playlist.medias.single.uri,
            'https://player.test/b.mp4',
          );
          expect(f.player.calls.where((c) => c.$1 == 'open'), hasLength(2));
          await d.position(300000);
          await d.playing(true);
          await d.tick(const Duration(minutes: 2));
          for (final tracker in ['trakt', 'simkl', 'mdblist']) {
            final requests = d.forTracker(tracker);
            if (launchIdentity) {
              expect(
                requests.length,
                greaterThan(before[tracker]!),
                reason:
                    'Observe real transport traffic after the channel action',
              );
              for (final request in requests) {
                final body = jsonDecode(request.body) as Map;
                expect((body['show'] as Map)['ids'], {'imdb': 'tt5100000'});
                if (tracker == 'mdblist') {
                  expect((body['show'] as Map)['episode'], 2);
                } else {
                  expect((body['episode'] as Map)['number'], 2);
                }
                expect(request.body, isNot(contains('tt2222222')));
              }
            } else {
              expect(requests, isEmpty);
            }
          }
          expect(d.uncaught, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}

class _P17TrackerDriver extends SecondaryTrackerDriver {
  _P17TrackerDriver(super.t, super.f);
  final _captured = P17ObservedErrors();
  @override
  List<Object> get uncaught => _captured;
}
