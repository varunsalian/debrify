import 'dart:async';
import 'package:debrify/models/series_source.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/alldebrid_files_fixture.dart';

void main() {
  for (final web in [false, true]) {
    testWidgets(
      'pushed picker binding awaits once before pop and preserves every source field web=$web',
      (t) => allDebridCase(t, (f) async {
        final selected = <SeriesSource>[];
        final gate = Completer<void>();
        await f.mount(
          t,
          pushed: true,
          picker: true,
          selected: (s) async {
            selected.add(s);
            await gate.future;
          },
        );
        if (web) {
          await f.web(t);
        }
        final before = DateTime.now().millisecondsSinceEpoch;
        await f.tap(t, find.text(web ? 'Saved w8.mkv' : 'Library z9'));
        expect(selected.length, 1);
        expect(f.observer.popped, isEmpty);
        expect(find.text('Caller'), findsNothing);
        final source = selected.single;
        expect(
          source.boundAt,
          inInclusiveRange(before, DateTime.now().millisecondsSinceEpoch),
        );
        expect({...source.toJson()}..remove('boundAt'), {
          'torrentHash': web ? '' : 'hash-z9',
          'torrentName': web ? 'Saved w8.mkv' : 'Library z9',
          'debridService': 'alldebrid',
          'debridTorrentId': web
              ? SeriesSource.opaqueCloudReference('https://locked.test/w8')
              : 'z9',
          if (web) 'cloudSourceKind': SeriesSource.cloudKindWebDownload,
        });
        gate.complete();
        await t.pump();
        await t.pump(const Duration(milliseconds: 600));
        expect(selected.length, 1);
        expect(f.observer.popped.length, 1);
        expect(find.text('Caller'), findsOneWidget);
        expect(f.log, [adList(), if (web) adLinks()]);
      }),
    );
  }
  testWidgets(
    'picker rejects whitespace infohash and a non-video saved link has no tap',
    (t) => allDebridCase(t, (f) async {
      f.magnets = [adMagnet('z9', hash: '  ')];
      var calls = 0;
      await f.mount(
        t,
        pushed: true,
        picker: true,
        selected: (_) async {
          calls++;
        },
      );
      await f.tap(t, find.text('Library z9'));
      expect(
        find.text('This AllDebrid magnet has no infohash to bind.'),
        findsOneWidget,
      );
      expect(calls, 0);
      expect(f.observer.popped, isEmpty);
      await f.web(t);
      final disabled = t.widget<CloudFileRow>(f.row('Saved b3.zip'));
      expect(disabled.onTap, isNull);
      expect(disabled.actions, isEmpty);
      await f.tap(t, find.text('Saved b3.zip'));
      expect(calls, 0);
      expect(f.observer.popped, isEmpty);
      expect(f.log, [adList(), adLinks()]);
    }),
  );
  testWidgets(
    'picker hides mutation actions and retains one search focus attachment even with zero matches',
    (t) => allDebridCase(t, (f) async {
      await f.mount(t, picker: true);
      expect(find.text('Select AllDebrid Source'), findsOneWidget);
      for (final tip in [
        'Select items',
        'Delete all magnets',
        'Add magnet link',
      ]) {
        expect(find.byTooltip(tip), findsNothing);
      }
      Finder searchButton() => find.byWidgetPredicate(
        (w) =>
            w is IconButton &&
            identical(w.focusNode, f.focus('toolbarSearchFocusNode')),
      );
      expect(searchButton(), findsOneWidget);
      await f.search(t, 'no-match');
      expect(find.text('No magnets match your search.'), findsOneWidget);
      expect(searchButton(), findsOneWidget);
      await f.web(t);
      for (final tip in ['Delete all links', 'Add link', 'Select items']) {
        expect(find.byTooltip(tip), findsNothing);
      }
      expect(searchButton(), findsOneWidget);
      await f.search(t, 'no-match');
      expect(find.text('No links match your search.'), findsOneWidget);
      expect(searchButton(), findsOneWidget);
      expect(f.log, [adList(), adLinks()]);
    }),
  );
  testWidgets(
    'picker with empty backing lists renders no toolbar search button in either view',
    (t) => allDebridCase(t, (f) async {
      f.magnets = [];
      f.links = [];
      await f.mount(t, picker: true);
      expect(find.byTooltip('Search magnets'), findsNothing);
      await f.web(t);
      expect(find.byTooltip('Search links'), findsNothing);
      expect(f.focus('toolbarSearchFocusNode').context, isNull);
      expect(f.log, [adList(), adLinks()]);
    }),
  );
  testWidgets(
    'same-key picker widget update reads the new onSourceSelected callback live',
    (t) => allDebridCase(t, (f) async {
      var oldCalls = 0, newCalls = 0;
      final gate = Completer<void>();
      await f.mount(
        t,
        picker: true,
        selected: (_) async {
          oldCalls++;
        },
      );
      final state = f.key.currentState;
      await f.update(
        t,
        selected: (_) async {
          newCalls++;
          await gate.future;
        },
      );
      expect(f.key.currentState, same(state));
      await f.tap(t, find.text('Library a2'));
      expect((oldCalls, newCalls), (0, 1));
      expect(f.log, [adList()]);
      await f.close(t);
      gate.complete();
      await t.pump();
      expect(t.takeException(), isNull);
    }),
  );
}
