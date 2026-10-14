import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/identify_title_driver.dart';
import 'support/trakt_transport.dart';
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

void main() {
  TraktTestTransport.install();
  testWidgets(
    'identify typing does not search, suffix and repeated submissions do, empty submission clears',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      try {
        await d.mountIdentity();
        final menu = await d.menu();
        expect(menu.subtitleIdentityLabel, 'Detected: Launch Title');
        final result = d.start(menu);
        await d.found('Chosen title');
        expect(d.catalogQueries, ['Launch Title']);
        final field = d.searchField;
        final firstFocus = t
            .widget<InkWell>(
              find
                  .ancestor(
                    of: find.text('Chosen title'),
                    matching: find.byType(InkWell),
                  )
                  .first,
            )
            .focusNode!;
        expect(field.controller.text, 'Launch Title');
        expect(field.focusNode!.debugLabel, 'identify-title-search');
        await d.type('  edited query  ');
        expect(d.catalogQueries, ['Launch Title']);
        await d.suffix();
        await d.found('Chosen title');
        expect(d.catalogQueries, ['Launch Title', 'edited query']);
        await d.submit('edited query');
        await d.found('Chosen title');
        await d.submit('edited query');
        await d.found('Chosen title');
        expect(d.catalogQueries, [
          'Launch Title',
          'edited query',
          'edited query',
          'edited query',
        ]);
        await d.submit('   ');
        expect(find.text('Chosen title'), findsNothing);
        expect(find.text('No IMDb-backed results found'), findsNothing);
        expect(
          find.descendant(
            of: find
                .ancestor(
                  of: find.text('FIX THE TITLE'),
                  matching: find.byType(SafeArea),
                )
                .first,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing,
        );
        expect(d.catalogQueries, hasLength(4));
        await d.dismiss();
        expect(await d.f.finish(t, result), isNull);
        expect(() => field.controller.addListener(() {}), throwsFlutterError);
        expect(() => field.focusNode!.addListener(() {}), throwsFlutterError);
        expect(() => firstFocus.addListener(() {}), throwsFlutterError);
      } finally {
        await removeFixture(d);
      }
    },
  );
  for (final next in ['submit', 'edit', 'empty']) {
    testWidgets(
      'identify old response after $next obeys submitted token only',
      (t) async {
        final d = IdentifyTitleDriver(t);
        await d.setupIdentity();
        final held = Completer<http.Response>();
        try {
          await d.mountIdentity();
          final result = d.start(await d.menu());
          await d.found('Chosen title');
          d.catalog = (r) => r.url.path.contains('search=old')
              ? held.future
              : d.response([IdentifyTitleDriver.identityMeta('New result')]);
          await d.submit('old');
          await d.f.until(t, () => d.catalogQueries.contains('old'));
          expect(
            find.descendant(
              of: find
                  .ancestor(
                    of: find.text('FIX THE TITLE'),
                    matching: find.byType(SafeArea),
                  )
                  .first,
              matching: find.byType(CircularProgressIndicator),
            ),
            findsOneWidget,
          );
          if (next == 'submit') {
            await d.submit('new');
            await d.found('New result');
          }
          if (next == 'edit') await d.type('not submitted');
          if (next == 'empty') await d.submit(' ');
          held.complete(
            d.response([IdentifyTitleDriver.identityMeta('Old result')]),
          );
          await d.f.actions.settle(t);
          expect(
            find.text('Old result'),
            next == 'edit' ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('New result'),
            next == 'submit' ? findsOneWidget : findsNothing,
          );
          if (next == 'empty') {
            expect(
              find.descendant(
                of: find
                    .ancestor(
                      of: find.text('FIX THE TITLE'),
                      matching: find.byType(SafeArea),
                    )
                    .first,
                matching: find.byType(CircularProgressIndicator),
              ),
              findsNothing,
            );
          }
          expect(
            d.searchField.controller.text,
            next == 'edit'
                ? 'not submitted'
                : next == 'empty'
                ? ' '
                : 'new',
          );
          expect(
            d.catalogQueries,
            next == 'submit'
                ? ['Launch Title', 'old', 'new']
                : ['Launch Title', 'old'],
          );
          await d.dismiss();
          expect(await d.f.finish(t, result), isNull);
        } finally {
          if (!held.isCompleted) held.complete(d.response([]));
          await removeFixture(d);
        }
      },
    );
  }
  for (final failure in ['http', 'json', 'throw']) {
    testWidgets(
      'identify catalog $failure failure is empty results, not search error',
      (t) async {
        final d = IdentifyTitleDriver(t);
        await d.setupIdentity();
        d.catalog = (_) {
          if (failure == 'throw') throw StateError('Synthetic catalog failure');
          return http.Response(
            failure == 'json' ? '[' : '{}',
            failure == 'http' ? 503 : 200,
          );
        };
        try {
          await d.mountIdentity();
          final result = d.start(await d.menu());
          await d.found('No IMDb-backed results found');
          final empty = t.widget<Text>(
            find.text('No IMDb-backed results found'),
          );
          expect(empty.style!.fontSize, 14);
          expect(empty.style!.color, Colors.white.withValues(alpha: .65));
          expect(d.catalogQueries, ['Launch Title']);
          expect(find.text('Search failed. Try again.'), findsNothing);
          expect(find.text('Chosen title'), findsNothing);
          await d.dismiss();
          expect(await d.f.finish(t, result), isNull);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
}
