import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recordings_fixture.dart';

void main() {
  testWidgets(
    'each revision reloads once while mounted and never after dispose',
    (t) async {
      await recordingsCase(t, (f) async {
        await f.mount(t);
        for (final desktop in [false, true]) {
          final before = f.paths.reads;
          await f.revision(t, desktop: desktop);
          expect(
            f.paths.reads - before,
            1,
            reason: 'each mounted revision has exactly one reload',
          );
        }
        await t.pumpWidget(const SizedBox());
        final disposed = f.paths.reads;
        await f.revision(t);
        await f.revision(t, desktop: true);
        expect(f.paths.reads, disposed, reason: 'disposed page never reloads');
      });
    },
  );

  testWidgets(
    'pause cancels ticker hidden revision cannot rearm resume reloads',
    (t) async {
      await recordingsCase(t, (f) async {
        await f.seedSchedules([f.schedule('visible')]);
        await f.mount(t);
        final clock = f.clock(t);
        var ticks = 0;
        void changed() => ticks++;
        clock.addListener(changed);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await t.pump(const Duration(seconds: 2));
        expect(ticks, 0, reason: 'paused cancels ticker');
        await f.revision(t);
        await t.pump(const Duration(seconds: 2));
        expect(ticks, 0, reason: 'hidden revision cannot rearm ticker');
        final reads = f.paths.reads;
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await f.settle(t);
        expect(f.paths.reads - reads, 1, reason: 'resume reloads recordings');
        await t.pump(const Duration(seconds: 2));
        expect(
          ticks,
          greaterThan(0),
          reason: 'resume rearms ticker for schedule',
        );
        clock.removeListener(changed);
      });
    },
  );

  testWidgets(
    'load completion after disposal does not publish into dead State',
    (t) async {
      await recordingsCase(t, (f) async {
        f.paths.held = Completer<String?>();
        await f.mount(t, wait: false);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        f.paths.held!.complete(f.directory.path);
        await f.settle(t);
        expect(t.takeException(), isNull, reason: 'disposed load is rejected');
      });
    },
  );
}
