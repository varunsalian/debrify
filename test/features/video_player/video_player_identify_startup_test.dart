import 'package:debrify/services/profiles/profile_async_authorization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/identify_deferred_search.dart';
import 'support/identify_title_driver.dart';
import 'support/local_completion_driver.dart' show CompletionDelivery;
import 'support/trakt_transport.dart';
import 'video_player_identify_races_test.dart'
    show identifyRaceScreen, identifyBoundary;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

void main() {
  TraktTestTransport.install();
  for (final boundary in ['initial scheduling', 'inventory']) {
    for (final event in ['dismiss', 'reset', 'profile', 'dispose']) {
      testWidgets(
        'identify $boundary held across $event preserves original guard and resource timing',
        (t) async {
          final d = IdentifyTitleDriver(t);
          await d.setupIdentity();
          final scheduling = IdentifyDeferredSearch();
          final inventory = CompletionDelivery(
            '_getAddons',
            (v) => v is ProfileAsyncAuthorization,
          );
          try {
            await d.mountIdentity(screen: identifyRaceScreen, rooted: true);
            final menu = await d.menu();
            final action = boundary == 'inventory'
                ? inventory.run(() => d.start(menu))
                : scheduling.run(() => d.start(menu));
            if (boundary == 'inventory') {
              await inventory.run(
                () => d.f.until(t, () => inventory.pending.isNotEmpty),
              );
            } else {
              await d.observeFuture(
                () => scheduling.run(
                  () => d.f.until(t, () => scheduling.pending.isNotEmpty),
                ),
              );
            }
            final field = d.searchField;
            expect(d.catalogQueries, isEmpty);
            expect(field.controller.text, 'First title');
            expect(() => field.controller.addListener(() {}), returnsNormally);
            await identifyBoundary(d, event);
            expect(d.catalogQueries, isEmpty);
            if (boundary == 'initial scheduling') {
              d.observe(scheduling.release);
            } else {
              inventory.release();
            }
            await d.f.actions.settle(t);
            if (boundary == 'inventory' && event == 'profile') {
              expect(d.catalogQueries, isEmpty);
              expect(find.text('No IMDb-backed results found'), findsOneWidget);
            } else if (boundary == 'initial scheduling' && event == 'dismiss') {
              expect(d.catalogQueries, isEmpty);
              expect(d.errors.whereType<FlutterError>(), hasLength(1));
              expect(
                d.errors.single.toString(),
                contains('setState() called after dispose'),
              );
            } else {
              expect(d.catalogQueries, ['First title']);
              expect(d.errors, isEmpty);
            }
            expect(
              find.text('Chosen title'),
              ['reset', 'profile'].contains(event) &&
                      !(boundary == 'inventory' && event == 'profile')
                  ? findsOneWidget
                  : findsNothing,
            );
            if (event != 'dismiss') await d.dismiss();
            expect(await d.f.finish(t, action), isNull);
            expect(
              () => field.controller.addListener(() {}),
              throwsFlutterError,
            );
            expect(
              () => field.focusNode!.addListener(() {}),
              throwsFlutterError,
            );
          } finally {
            d.observe(scheduling.release);
            inventory.release();
            await removeFixture(d);
          }
        },
      );
    }
  }
}
