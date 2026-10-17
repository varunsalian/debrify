import 'dart:async';

import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/startup_driver.dart';

void main() {
  for (final result in ['null', 'empty', 'empty first URL', 'valid']) {
    testWidgets(
      'P16 sheet resolver $result preserves the URL, pending adoption and caller boundary',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        final a = startupSource('sheet-a');
        final b = startupSource('sheet-b');
        final entries = result == 'null'
            ? null
            : result == 'empty'
            ? <PlaylistEntry>[]
            : [
                PlaylistEntry(
                  url: result == 'empty first URL' ? '' : b.directUrl!,
                  title: 'Incoming entry',
                ),
              ];
        try {
          await d.begin(
            d.screen(
              sources: [a, b],
              playlist: (s, {canContinue}) async => entries,
            ),
          );
          await d.committed();
          await d.settle();
          final sheet = await d.sheet();
          final resolved = await d.f.finish(t, sheet.resolveSource(b));
          expect(resolved, result == 'valid' ? b.directUrl : isNull);
          expect(d.opens, [a.directUrl]);
          if (result == 'valid') {
            final action = d.select(sheet, 1, resolved!);
            await d.f.finish(t, action.future);
            expect(d.opens, [a.directUrl, b.directUrl]);
            expect(d.commits, [a, b]);
            expect(find.byType(SourceSheet), findsNothing);
          }
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final retirement in ['close', 'dispose', 'newer result']) {
    testWidgets(
      'P16 sheet pending resolution rejects $retirement before pending playlist adoption',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        final a = startupSource('pending-a');
        final b = startupSource('pending-b');
        final c = startupSource('pending-c');
        final gate = Completer<List<PlaylistEntry>?>();
        final active = <bool Function()>[];
        try {
          await d.begin(
            d.screen(
              sources: [a, b, c],
              playlist: (s, {canContinue}) async {
                active.add(canContinue!);
                return s == b
                    ? gate.future
                    : [PlaylistEntry(url: c.directUrl!, title: 'C entry')];
              },
            ),
          );
          await d.committed();
          await d.settle();
          final sheet = await d.sheet();
          final pending = d.f.actions.start(
            'pending source resolution',
            () => sheet.resolveSource(b),
            held: true,
          );
          await d.f.until(t, () => active.isNotEmpty);
          expect(active.first(), isTrue);
          expect(pending.isCompleted, isFalse);
          if (retirement == 'close') {
            sheet.onClose();
            await d.tick();
            expect(find.byType(SourceSheet), findsNothing);
            await d.sheet();
          } else if (retirement == 'dispose') {
            d.f.navigator.currentState!.pop();
            await d.tick(const Duration(milliseconds: 400));
            await d.f.until(t, () => d.player.disposed.isCompleted);
          } else {
            expect(await d.f.finish(t, sheet.resolveSource(c)), c.directUrl);
          }
          expect(active.first(), isFalse);
          gate.complete([PlaylistEntry(url: b.directUrl!, title: 'Late B')]);
          expect(await d.f.finish(t, pending.future), isNull);
          expect(d.opens, [a.directUrl]);
          if (retirement == 'newer result') {
            final action = d.select(sheet, 2, c.directUrl!);
            await d.f.finish(t, action.future);
            expect(d.opens, [a.directUrl, c.directUrl]);
            expect(d.commits, [a, c]);
          }
        } finally {
          if (!gate.isCompleted) gate.complete(null);
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P16 source callbacks stay equal across rebuilds while the playlist resolver remains fresh and reads the live selector',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource('live-a');
      final b = startupSource('live-b');
      final calls = <String>[];
      Future<List<PlaylistEntry>?> first(
        s, {
        bool Function()? canContinue,
      }) async {
        calls.add('first');
        return [PlaylistEntry(url: a.directUrl!, title: 'A')];
      }

      Future<List<PlaylistEntry>?> second(
        s, {
        bool Function()? canContinue,
      }) async {
        calls.add('second');
        return [PlaylistEntry(url: b.directUrl!, title: 'B')];
      }

      try {
        await d.begin(d.screen(sources: [a, b], playlist: first));
        await d.committed();
        await d.settle();
        final sheet = await d.sheet();
        await d.update(d.screen(sources: [a, b], playlist: second));
        final rebuilt = t.widget<SourceSheet>(find.byType(SourceSheet));
        expect(rebuilt.onSourceSelected == sheet.onSourceSelected, isTrue);
        expect(rebuilt.onClose == sheet.onClose, isTrue);
        expect(rebuilt.resolveSource == sheet.resolveSource, isFalse);
        expect(
          await d.f.finish(t, sheet.resolveSource(b)),
          b.directUrl,
          reason:
              'Even the outgoing closure reads the current widget selector at invocation',
        );
        expect(calls, ['second']);
        final selected = d.select(rebuilt, 1, b.directUrl!);
        await d.f.finish(t, selected.future);
        expect(d.opens, [a.directUrl, b.directUrl]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P16 a captured source button rechecks an empty live source list before opening its sheet',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource('empty-list');
      try {
        await d.begin(
          d.screen(sources: [a], resolve: (s) async => s.directUrl),
        );
        await d.committed();
        await d.initialized();
        await d.settle();
        final captured = playerControls(t).onShowStremioSources!;
        await d.update(
          d.screen(sources: [], resolve: (s) async => s.directUrl),
        );
        captured();
        await d.tick();
        expect(find.byType(SourceSheet), findsNothing);
        await d.update(
          d.screen(sources: [a], resolve: (s) async => s.directUrl),
        );
        expect(find.byType(SourceSheet), findsNothing);
        expect(d.opens, [a.directUrl]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P16 direct resolver identity stays the supplied callback and a source pick consumes no invented playlist',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource('direct-a');
      final b = startupSource('direct-b');
      Future<String?> resolve(s) async => s.directUrl;
      try {
        await d.begin(d.screen(sources: [a, b], resolve: resolve));
        await d.committed();
        await d.settle();
        final sheet = await d.sheet();
        expect(sheet.resolveSource == resolve, isTrue);
        final url = await d.f.finish(t, sheet.resolveSource(b));
        final action = d.select(sheet, 1, url!);
        await d.f.finish(t, action.future);
        expect(d.opens, [a.directUrl, b.directUrl]);
        expect(d.commits, [a, b]);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P16 a resolved pack is consumed once before a later direct source choice',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource('once-a'),
          b = startupSource('once-b'),
          c = startupSource('once-c');
      try {
        await d.begin(
          d.screen(
            sources: [a, b, c],
            playlist: (s, {canContinue}) async => [
              PlaylistEntry(url: b.directUrl!, title: 'B pack'),
            ],
          ),
        );
        await d.committed();
        await d.initialized();
        final sheet = await d.sheet();
        expect(await d.f.finish(t, sheet.resolveSource(b)), b.directUrl);
        await d.f.finish(t, d.select(sheet, 1, b.directUrl!).future);
        expect(d.opens, [a.directUrl, b.directUrl]);
        await d.update(
          d.screen(sources: [a, b, c], resolve: (s) async => s.directUrl),
        );
        final fresh = await d.sheet();
        expect(await d.f.finish(t, fresh.resolveSource(c)), c.directUrl);
        await d.f.finish(t, d.select(fresh, 2, c.directUrl!).future);
        expect(d.opens, [a.directUrl, b.directUrl, c.directUrl]);
        expect(d.commits, [a, b, c]);
      } finally {
        await d.close();
      }
    },
  );
}
