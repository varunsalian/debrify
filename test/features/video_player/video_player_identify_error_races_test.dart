import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/identify_held_inventory.dart';
import 'support/identify_title_driver.dart';
import 'support/trakt_transport.dart';
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

void main() {
  TraktTestTransport.install();
  for (final event in [
    'dismiss',
    'dispose',
    'empty submission',
    'newer success',
  ]) {
    testWidgets(
      'identify held stable inventory error after $event cannot publish stale search error',
      (t) async {
        final d = IdentifyTitleDriver(t, committed: false);
        await d.setupIdentity();
        IdentifyHeldInventory? store;
        try {
          await d.mountIdentity(rooted: true);
          final pending = d.start(await d.menu());
          await d.found('Chosen title');
          StremioService.instance.invalidateCache();
          store = await t.runAsync(IdentifyHeldInventory.install);
          if (event == 'dismiss') {
            await d.observeFuture(() => d.submit('old failure'));
          } else {
            await d.submit('old failure');
          }
          await d.f.until(t, () => store!.entered);
          expect(find.text('Search failed. Try again.'), findsNothing);
          expect(d.catalogQueries, ['Launch Title']);
          if (event == 'dismiss') {
            await d.dismiss();
          } else if (event == 'dispose') {
            d.f.navigator.currentState!.removeRoute(d.playerRoute!);
            await d.f.until(
              t,
              () => find.byType(VideoPlayerScreen).evaluate().isEmpty,
            );
            expect(find.byType(VideoPlayerScreen), findsNothing);
            expect(find.text('FIX THE TITLE'), findsOneWidget);
          } else if (event == 'empty submission') {
            await d.submit(' ');
          } else {
            store!.freshLoad();
            d.metas = [IdentifyTitleDriver.identityMeta('Newer result')];
            await d.submit('newer');
            await d.found('Newer result');
          }
          expect(store!.gate.isCompleted, isFalse);
          store.release();
          await d.f.actions.settle(t);
          expect(t.takeException(), isNull);
          expect(find.text('Search failed. Try again.'), findsNothing);
          expect(
            find.text('Newer result'),
            event == 'newer success' ? findsOneWidget : findsNothing,
          );
          expect(
            d.catalogQueries,
            event == 'newer success'
                ? ['Launch Title', 'newer']
                : ['Launch Title'],
          );
          store.freshLoad();
          if (event != 'dismiss') await d.dismiss();
          expect(await d.f.finish(t, pending), isNull);
          expect(d.errors, isEmpty);
        } finally {
          store?.release();
          store?.freshLoad();
          if (d.f.navigator.currentState?.canPop() ?? false) await d.dismiss();
          await removeFixture(d);
        }
      },
    );
  }
}
