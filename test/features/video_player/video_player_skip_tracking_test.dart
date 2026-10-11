import 'dart:convert';

import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/skip_segment_button.dart';
import 'package:debrify/services/storage/mdblist_storage.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/storage/trakt_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'support/player_actions.dart';
import 'support/skip_segment_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'skip publishes clock before seek, queues tracking before haptic and preserves remote stop order',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      final oldPrint = debugPrint;
      try {
        await d.configure();
        await t.runAsync(() async {
          await TraktStorage.setTraktAccessToken('fixture-trakt');
          await SimklStorage.setSimklAccessToken('fixture-simkl');
          await MdblistStorage.saveMdblistApiKey('fixture-mdblist');
          await TrackingSourceStorage.setTrackingScrobbleTargets({
            TrackingSource.trakt,
            TrackingSource.simkl,
            TrackingSource.mdblist,
          });
        });
        f.network.handler = (request) {
          if (request.url.host == 'api.skipdb.tv') {
            return skipReply(start: 900, end: 1100);
          }
          if (request.url.path.contains('/scrobble/')) {
            return http.Response(
              jsonEncode({
                'action': request.url.path.split('/').last,
                'progress': 91.6667,
              }),
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          );
        };
        await f.mount(
          t,
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/skip.mp4',
            title: 'Skip trackers',
            contentImdbId: 'tt4100000',
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
            traktScrobble: true,
            simklScrobble: true,
            mdblistScrobble: true,
          ),
        );
        await d.tick(950);
        d.expectButton(true);
        final before = f.network.requests.length;
        final clock = playerControls(t).clock;
        final hapticsBefore = f.channels
            .where((c) => c.$2.method == 'HapticFeedback.vibrate')
            .length;
        final order = <String>[];
        void observeClock() {
          if (clock.value.position == const Duration(seconds: 1100)) {
            expect(
              f.player.calls.where(
                (c) => c.$1 == 'seek' && c.$2 == const Duration(seconds: 1100),
              ),
              isEmpty,
            );
            order.add('clock');
          }
        }

        clock.addListener(observeClock);
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message?.contains('scrobble queued action=stop') == true) {
            expect(order, ['clock']);
            expect(f.player.calls.last.$1, 'seek');
            expect(
              f.channels.where((c) => c.$2.method == 'HapticFeedback.vibrate'),
              hasLength(hapticsBefore),
            );
            order.add('tracking');
          }
        };
        t.widget<SkipSegmentButton>(find.byType(SkipSegmentButton)).onPressed();
        clock.removeListener(observeClock);
        expect(order, ['clock', 'tracking']);
        expect(clock.value.position, const Duration(seconds: 1100));
        expect(
          f.player.calls.where((c) => c.$1 == 'seek').last.$2,
          const Duration(seconds: 1100),
        );
        await f.until(
          t,
          () =>
              f.network.requests
                  .skip(before)
                  .where((r) => r.url.path == '/scrobble/stop')
                  .length ==
              3,
        );
        final stops = f.network.requests
            .skip(before)
            .where((r) => r.url.path == '/scrobble/stop')
            .toList();
        expect(stops.map((r) => r.url.host), [
          'api.simkl.com',
          'api.trakt.tv',
          'api.mdblist.com',
        ]);
        for (final request in stops) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(
            (body['progress'] as num).toDouble(),
            closeTo(1100 / 1200 * 100, 0.01),
          );
        }
        d.expectButton(false);
      } finally {
        debugPrint = oldPrint;
        await f.close(t);
      }
    },
  );

  testWidgets('skip tracker seek order arms Trakt heartbeat before Simkl', (
    t,
  ) async {
    final f = VideoPlayerEnvironment();
    await t.runAsync(f.initialize);
    final d = SkipSegmentDriver(t, f);
    final oldPrint = debugPrint;
    try {
      await d.configure();
      await t.runAsync(() async {
        await TraktStorage.setTraktAccessToken('fixture-trakt');
        await SimklStorage.setSimklAccessToken('fixture-simkl');
        await TrackingSourceStorage.setTrackingScrobbleTargets({
          TrackingSource.trakt,
          TrackingSource.simkl,
        });
      });
      f.network.handler = (request) {
        if (request.url.host == 'api.skipdb.tv') {
          return request.url.queryParameters['duration'] == '1200'
              ? skipReply(start: 900, end: 1100)
              : skipReply(start: 100, end: 300);
        }
        return http.Response(
          '{}',
          request.url.path.contains('/scrobble/') ? 201 : 200,
          headers: {'content-type': 'application/json'},
        );
      };
      await f.mount(
        t,
        const VideoPlayerScreen(
          videoUrl: 'https://player.test/skip.mp4',
          title: 'Skip heartbeat order',
          contentImdbId: 'tt4100000',
          contentType: 'series',
          contentSeason: 2,
          contentEpisode: 3,
          traktScrobble: true,
          simklScrobble: true,
        ),
      );
      await d.tick(950);
      t.widget<SkipSegmentButton>(find.byType(SkipSegmentButton)).onPressed();
      await f.until(
        t,
        () =>
            f.network.requests
                .where((r) => r.url.path == '/scrobble/stop')
                .length ==
            2,
      );
      // Both trackers stopped above 80%; skipping back below it re-arms both
      // periodic checkpoints at the same fake time through the original caller.
      await d.duration(const Duration(seconds: 900));
      await d.tick(150);
      t.widget<SkipSegmentButton>(find.byType(SkipSegmentButton)).onPressed();
      expect(
        playerControls(t).clock.value.position,
        const Duration(seconds: 300),
      );
      final order = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message?.startsWith('Trakt: Heartbeat scrobble') == true) {
          order.add('Trakt');
        }
        if (message?.startsWith('Simkl: Heartbeat pause checkpoint') == true) {
          order.add('Simkl');
        }
      };
      await f.advance(t, const Duration(minutes: 2));
      expect(order, ['Trakt', 'Simkl']);
    } finally {
      debugPrint = oldPrint;
      await f.close(t);
    }
  });
}
