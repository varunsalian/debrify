import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/episodes_panel_fixture.dart';
import 'episodes_panel_watched_test.dart'
    show episodeBody, expectRequest, timestampInWindow;

void main() {
  for (final scenario in [
    'cancel',
    'rate-success',
    'rate-failure',
    'remove-success',
    'remove-failure',
  ]) {
    testWidgets(
      'MDBList episode rating $scenario complete body, snackbar and reopened sheet',
      (t) async {
        final index = [
          'cancel',
          'rate-success',
          'rate-failure',
          'remove-success',
          'remove-failure',
        ].indexOf(scenario);
        await episodesPanelCase(t, 'rating-$scenario', 60 + index, (f) async {
          await t.runAsync(() => f.authenticate({TrackingSource.mdblist}));
          final removal = scenario.startsWith('remove');
          final failure = scenario.endsWith('failure');
          f.initialRating = removal ? 7 : null;
          f.mdblistFails = failure;
          await f.mount(t);
          await f.sheet(t);
          final label = removal
              ? 'Remove MDBList rating (7/10)'
              : 'Rate on MDBList';
          expect(find.text(label), findsOneWidget);
          f.requests.clear();
          final before = DateTime.now().toUtc();
          await t.tap(find.text(label));
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));
          if (!removal) {
            expect(find.byType(AlertDialog), findsOneWidget);
            if (scenario == 'cancel') {
              f.navigator.currentState!.pop();
            } else {
              await t.tap(
                find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.text('7'),
                ),
              );
            }
            await t.pump();
            await t.pump(const Duration(milliseconds: 400));
          }
          if (scenario == 'cancel') {
            expect(f.requests, isEmpty);
            expect(find.byType(SnackBar), findsNothing);
          } else {
            final text = removal
                ? 'Removed rating from MDBList'
                : 'Rated 7/10 on MDBList';
            await f.until(
              t,
              () => find
                  .text(failure ? 'Failed: $text' : text)
                  .evaluate()
                  .isNotEmpty,
            );
            final after = DateTime.now().toUtc();
            expect(f.requests, hasLength(1));
            final r = f.requests.single;
            expectRequest(
              r,
              method: 'POST',
              host: 'api.mdblist.com',
              path: removal ? '/sync/ratings/remove' : '/sync/ratings',
              query: {'apikey': 'episodes-test-mdblist'},
              body: episodeBody(
                {'imdb': f.id},
                attributes: {
                  if (!removal) 'rating': 7,
                  if (!removal)
                    'rated_at': timestampInWindow(r, 'rated_at', before, after),
                },
              ),
            );
            expect(
              t.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
              failure ? const Color(0xFFEF4444) : const Color(0xFF34D399),
            );
          }
          await f.sheet(t);
          final retained = removal ? failure : scenario == 'rate-success';
          expect(
            find.text(
              retained ? 'Remove MDBList rating (7/10)' : 'Rate on MDBList',
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              retained ? 'Rate on MDBList' : 'Remove MDBList rating (7/10)',
            ),
            findsNothing,
          );
        });
      },
    );
  }
}
