import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/identify_title_driver.dart';
import 'support/local_completion_driver.dart' show CompletionDelivery;
import 'support/trakt_transport.dart';
import 'video_player_identify_races_test.dart'
    show identifyRaceScreen, identifyBoundary;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

void main() {
  TraktTestTransport.install();
  for (final event in [
    'same playback',
    'dismiss',
    'reset',
    'profile',
    'dispose',
  ]) {
    testWidgets(
      'identify empty captured result after $event uses mounted-only notification without another token guard',
      (t) async {
        final d = IdentifyTitleDriver(t);
        await d.setupIdentity();
        d.discovery = (_) => http.Response('{"subtitles":[]}', 200);
        final delivery = CompletionDelivery(
          'identifyTitleAndFetchSubtitles',
          (v) => v == null,
        );
        var returned = false;
        try {
          await d.mountIdentity(screen: identifyRaceScreen, rooted: true);
          final menu = await d.menu();
          final pending = delivery.run(() => d.start(menu));
          pending.then((_) => returned = true);
          await d.found('Chosen title');
          await t.tap(find.text('Chosen title'));
          await d.f.until(t, () => delivery.pending.isNotEmpty);
          expect(returned, isFalse);
          expect(
            find.text('No online subtitles found for this title'),
            findsNothing,
          );
          expect(d.subtitlePaths, ['/subtitles/movie/tt1200002.json']);
          if (event != 'same playback') {
            await identifyBoundary(d, event, modal: false);
          }
          expect(returned, isFalse);
          delivery.release();
          final result = await d.f.finish(t, pending);
          expect(result?.imdbId, 'tt1200002');
          expect(result?.identityLabel, 'Subtitles for Chosen title');
          expect(result?.subtitles, isEmpty);
          expect(result?.slots?.single.subtitles, isEmpty);
          expect(
            find.text('No online subtitles found for this title'),
            event == 'dispose' ? findsNothing : findsOneWidget,
          );
          expect(d.errors, isEmpty);
        } finally {
          delivery.release();
          await removeFixture(d);
        }
      },
    );
  }
}
