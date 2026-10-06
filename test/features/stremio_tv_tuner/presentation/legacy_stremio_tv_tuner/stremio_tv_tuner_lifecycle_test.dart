import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_tuner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/stremio_tv_tuner_fixture.dart';

void main() {
  testWidgets(
    '15 second tick skips covered route, resumes, toggles off and never doubles',
    (tester) async {
      await tunerCase(tester, (f) async {
        f.autoRefresh = true;
        await f.mount(tester);
        f.service.calls.clear();
        await tester.pump(const Duration(seconds: 14));
        expect(
          f.service.calls,
          isEmpty,
          reason: 'no broadcast rebuild before 15 seconds',
        );
        await tester.pump(const Duration(seconds: 1));
        final once = f.service.calls.length;
        expect(once, greaterThan(0), reason: 'first broadcast tick rebuilds');
        await f.refresh(tester);
        f.service.calls.clear();
        await tester.pump(const Duration(seconds: 15));
        expect(
          f.service.calls.length,
          once,
          reason: 'one rebuild per tick after widget update',
        );
        f.navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        f.service.calls.clear();
        await tester.pump(const Duration(seconds: 15));
        expect(
          f.service.calls,
          isEmpty,
          reason: 'covered route suppresses broadcast tick',
        );
        f.navigatorKey.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        f.service.calls.clear();
        await tester.pump(const Duration(seconds: 15));
        expect(
          f.service.calls,
          isNotEmpty,
          reason: 'first tick after pop resumes',
        );
        f.autoRefresh = false;
        await f.refresh(tester);
        f.service.calls.clear();
        await tester.pump(const Duration(seconds: 45));
        expect(
          f.service.calls,
          isEmpty,
          reason: 'disabled broadcast has no periodic work',
        );
      });
    },
  );

  for (final autoRefresh in [true, false]) {
    testWidgets(
      '180ms settle scopes Stage rebuild with autoRefresh=$autoRefresh',
      (tester) async {
        await tunerCase(tester, (f) async {
          f.autoRefresh = autoRefresh;
          await f.mount(tester);
          await f.focus(tester, 0);
          await tester.pump(const Duration(milliseconds: 200));
          final elements = f.cards.evaluate().toList();
          final states = elements
              .map((e) => (e as StatefulElement).state)
              .toList();
          final stage = tester.element(f.stages.first);
          await f.focus(tester, 1);
          expect(
            f.focused.last,
            1,
            reason: 'focused index is reported immediately',
          );
          expect(
            find.descendant(
              of: f.stages,
              matching: find.text('Broadcast channel-0'),
            ),
            findsOneWidget,
          );
          var tunerBuilds = 0;
          var cardBuilds = 0;
          var stageBuilds = 0;
          debugOnRebuildDirtyWidget = (element, builtOnce) {
            if (element == f.tunerKey.currentContext) {
              tunerBuilds++;
            }
            if (elements.contains(element)) {
              cardBuilds++;
            }
            if (element == stage) {
              stageBuilds++;
            }
          };
          try {
            await tester.pump(const Duration(milliseconds: 179));
            expect(
              find.descendant(
                of: f.stages,
                matching: find.text('Broadcast channel-0'),
              ),
              findsOneWidget,
              reason: 'Stage remains old before the settle boundary',
            );
            await tester.pump(const Duration(milliseconds: 1));
            expect(
              find.descendant(
                of: f.stages,
                matching: find.text('Broadcast channel-1'),
              ),
              findsOneWidget,
              reason: 'Stage adopts latest channel at 180ms',
            );
            expect(
              tunerBuilds,
              autoRefresh ? 0 : 1,
              reason: 'settle rebuilds tuner only with auto-refresh off',
            );
            expect(
              cardBuilds,
              autoRefresh ? 0 : elements.length,
              reason: 'settle leaves dial builds scoped',
            );
            expect(
              stageBuilds,
              greaterThan(0),
              reason: 'positive Stage rebuild control',
            );
            expect(
              f.cards.evaluate().toList(),
              orderedEquals(elements),
              reason: 'card Elements persist across settle',
            );
            expect(
              f.cards.evaluate().map((e) => (e as StatefulElement).state),
              orderedEquals(states),
              reason: 'card States persist across settle',
            );
            tunerBuilds = 0;
            cardBuilds = 0;
            await f.refresh(tester);
            expect(
              tunerBuilds,
              greaterThan(0),
              reason: 'positive tuner rebuild control',
            );
            expect(
              cardBuilds,
              greaterThan(0),
              reason: 'positive dial rebuild control',
            );
          } finally {
            debugOnRebuildDirtyWidget = null;
          }
        });
      },
    );
  }

  testWidgets(
    'rapid focus dedupes latest pending channel and removal rejects stale settle',
    (tester) async {
      await tunerCase(tester, (f) async {
        await f.mount(tester);
        await f.focus(tester, 1);
        await tester.pump(const Duration(milliseconds: 100));
        await f.focus(tester, 2);
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.descendant(
            of: f.stages,
            matching: find.text('Broadcast channel-0'),
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 80));
        expect(
          find.descendant(
            of: f.stages,
            matching: find.text('Broadcast channel-2'),
          ),
          findsOneWidget,
          reason: 'only latest settle publishes',
        );
        await f.focus(tester, 3);
        f.channels.removeAt(3);
        await tester.pump(const Duration(milliseconds: 180));
        expect(
          find.descendant(
            of: f.stages,
            matching: find.text('Broadcast channel-2'),
          ),
          findsOneWidget,
          reason: 'removed pending channel cannot replace Stage',
        );
      });
    },
  );

  testWidgets('controller rebinds on update and unbinds on dispose', (
    tester,
  ) async {
    await tunerCase(tester, (f) async {
      final original = f.controller!;
      expect(
        original.focusRealIndex(0),
        isFalse,
        reason: 'absent State rejects focus',
      );
      await f.mount(tester);
      expect(original.focusRealIndex(0), isTrue);
      f.controller = StremioTvTunerController();
      await f.refresh(tester);
      expect(
        original.focusRealIndex(0),
        isFalse,
        reason: 'old controller is unbound',
      );
      expect(
        f.controller!.focusRealIndex(1),
        isTrue,
        reason: 'new controller is bound',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(
        f.controller!.focusRealIndex(1),
        isFalse,
        reason: 'dispose unbinds controller',
      );
    });
  });
  testWidgets(
    'broadcast passes rotation and salt, maps raw progress, and renders future up-next',
    (tester) async {
      await tunerCase(tester, (f) async {
        f.service.next['channel-0'] = tunerPlaying('future', future: true);
        await f.mount(tester);
        expect(
          f.service.calls.every((c) => c.$3 == 37 && c.$4 == 19),
          isTrue,
          reason: 'service reads preserve rotation and salt',
        );
        expect(
          f.service.calls.any((c) => c.$1 == 'next' && c.$2 == 'channel-0'),
          isTrue,
        );
        expect(
          f.progress.every((p) => p.$2 == 1),
          isTrue,
          reason: 'ordinary fixed-past broadcasts supply ended raw progress',
        );
        expect(find.text('Ended'), findsWidgets);
        expect(find.text('UP NEXT'), findsOneWidget);
        expect(find.text('Broadcast future'), findsOneWidget);
        final bar = tester.widget<FractionallySizedBox>(
          find
              .descendant(
                of: f.stages,
                matching: find.byType(FractionallySizedBox),
              )
              .first,
        );
        expect(
          bar.widthFactor,
          0.4,
          reason: 'Stage renders host-mapped progress',
        );
      });
    },
  );
}
