import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/debrify_tv_fixture.dart';

void main() {
  testWidgets(
    'C4 C8 R/O filter chip persists quality and invalidates stage memo',
    (t) async {
      await debrifyTvCase(t, (f) async {
        f.style = 'spotlight';
        await f.mount(t);
        f.spotlight.view.onChannelFocused(f.channels.first);
        await f.until(t, () => f.spotlight.view.stats != null);
        expect(f.spotlight.view.stats!.atYourQuality, 1);
        await f.settings(t);
        await t.tap(find.text('4K'));
        await t.pump(const Duration(milliseconds: 50));
        expect(f.spotlight.view.stats, isNull);
        expect(await t.runAsync(DebrifyTvStorage.getDebrifyTvFilterQualities), [
          'ultraHd',
        ]);
        await f.until(t, () => f.spotlight.view.stats != null);
        expect(f.spotlight.view.stats!.atYourQuality, 0);
      });
    },
  );

  testWidgets(
    'C9 R/O choice chip Select persists provider and KeyRepeat moves focus',
    (t) async {
      await debrifyTvCase(t, (f) async {
        f.style = 'spotlight';
        await t.runAsync(() => f.provider('torbox'));
        await f.mount(t);
        await f.settings(t);
        final rd = Focus.of(t.element(find.text('Real Debrid')));
        rd.requestFocus();
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.select);
        await f.settle(t);
        expect(
          await t.runAsync(DebrifyTvStorage.getDebrifyTvProvider),
          'real_debrid',
        );
        rd.requestFocus();
        await t.pump();
        await t.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
        await t.pump();
        final torbox = Focus.of(t.element(find.text('Torbox')));
        expect(torbox.hasFocus, isTrue);
        await t.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await t.pump();
        expect(
          torbox.hasFocus,
          isFalse,
          reason: 'choice chip KeyRepeat traverses focus',
        );
        await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      });
    },
  );

  testWidgets(
    'C9 R grid channel long press opens actions Escape restores focus',
    (t) async {
      await debrifyTvCase(t, (f) async {
        f.television = true;
        await f.mount(t);
        final entry = f.node('DebrifyTVQuickPlay');
        entry.requestFocus();
        await t.pump();
        await t.longPress(find.text('ORIGINAL CHANNEL 1'));
        await f.settle(t);
        expect(find.text('Edit channel'), findsOneWidget);
        expect(find.text('Pin channel'), findsOneWidget);
        expect(find.text('Delete channel'), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await f.settle(t);
        expect(find.text('Edit channel'), findsNothing);
        expect(entry.hasFocus, isTrue);
      });
    },
  );
}
