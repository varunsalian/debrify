import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/p21_controls_driver.dart';

const _right = LogicalKeyboardKey.arrowRight;
const _goBack = LogicalKeyboardKey.goBack;

Future<P21Driver> _tv(WidgetTester t) async {
  final d = P21Driver(t, tv: true);
  await d.initialize();
  await d.mount(screen: P21Driver.screen());
  await d.wait(4000);
  await d.at(const Duration(seconds: 300));
  return d;
}

/// Sends [key] and returns whether the app handled it. An unhandled BACK
/// goes back to the platform, which treats it as the system back. The host
/// test platform has no physical goBack key, so goBack rides the Escape
/// position with the remote's BACK key code (the logical key the screen
/// reads is goBack).
Future<bool> _send(P21Driver d, LogicalKeyboardKey key) async {
  final physical = key == _goBack ? PhysicalKeyboardKey.escape : null;
  final handled = await d.observe(() async {
    final down = await d.t.sendKeyDownEvent(key, physicalKey: physical);
    await d.t.sendKeyUpEvent(key, physicalKey: physical);
    return down;
  });
  await d.wait(50);
  return handled;
}

/// Phase 21a Step 0c, class 7: the remote's key aliases and the order of its
/// checks: `goBack` is BACK everywhere `escape` is, LEFT/RIGHT still zap
/// before the first ready, and presses made while there is no timeline do
/// not count toward a hold.
void main() {
  p21Timeouts();

  testWidgets('P21 TV goBack during a scrub cancels it like escape', (t) async {
    final d = await _tv(t);
    try {
      for (var i = 0; i < 3; i++) {
        await d.key(_right);
      }
      expect(d.bar.scrubPreview, const Duration(seconds: 330));
      final seeks = d.seeks.length;
      expect(await _send(d, _goBack), isTrue);
      expect(d.bar.scrubPreview, isNull);
      expect(d.seeks, hasLength(seeks));
      expect(d.count('play'), 1, reason: 'the cancel resumed');
      expect(d.focused, 'tvPlayPause');
      expect(d.barUp, isTrue);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P21 TV goBack on the raised bar lowers it and returns focus to the root',
    (t) async {
      final d = await _tv(t);
      try {
        await d.key(LogicalKeyboardKey.arrowDown);
        expect(d.barUp, isTrue);
        expect(await _send(d, _goBack), isTrue);
        expect(d.barUp, isFalse);
        expect(d.focused, 'tvPlayerRoot');
        expect(d.playerRouteOpen, isTrue);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV goBack before the first ready is left to the system rather than swallowed',
    (t) async {
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mountUnready(P21Driver.screen());
        final calls = d.player.calls.length;
        // The other remote keys are swallowed until ready.
        expect(await _send(d, LogicalKeyboardKey.select), isTrue);
        expect(await _send(d, LogicalKeyboardKey.arrowDown), isTrue);
        expect(await _send(d, _goBack), isFalse);
        expect(d.player.calls.length, calls);
        await d.ready();
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV goBack during a transition is left to the system rather than swallowed',
    (t) async {
      final next = Completer<Map<String, String>?>();
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mount(
          screen: P21Driver.screen(requestMagicNext: () => next.future),
        );
        await d.wait(4000);
        d.observe(d.bar.onNext!);
        await d.wait(100);
        expect(await _send(d, LogicalKeyboardKey.select), isTrue);
        expect(await _send(d, _goBack), isFalse);
        next.complete(null);
        await d.wait(100);
        expect(d.errors, isEmpty);
      } finally {
        if (!next.isCompleted) next.complete(null);
        await d.close();
      }
    },
  );

  for (final key in [_right, LogicalKeyboardKey.arrowLeft]) {
    testWidgets(
      'P21 TV ${key == _right ? 'RIGHT' : 'LEFT'} before the first ready still zaps a live channel',
      (t) async {
        final channels = [for (var i = 0; i < 3; i++) P21Driver.channel(i)];
        final d = P21Driver(t, tv: true);
        await d.initialize();
        try {
          await d.mountUnready(P21Driver.iptv(channels));
          final opens = d.opens.length;
          expect(await _send(d, key), isTrue);
          await d.wait(500);
          expect(d.opens.length, greaterThan(opens));
          expect(d.opens.last.uri, channels[key == _right ? 1 : 2].url);
          expect(d.seeks, isEmpty);
          await d.ready();
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P21 TV presses made while there is no timeline do not count toward a hold once the length arrives',
    (t) async {
      final d = await _tv(t);
      try {
        await d.length(Duration.zero);
        await d.key(_right);
        await d.key(_right);
        expect(d.seeks, isEmpty, reason: 'nothing to seek');
        await d.length(const Duration(minutes: 20));
        // Quick, but the first counted press: a ten-second nudge.
        await d.key(_right);
        expect(d.bar.scrubPreview, isNull);
        expect(d.seeks, [const Duration(seconds: 310)]);
        await d.key(_right);
        expect(d.bar.scrubPreview, isNull);
        await d.key(_right);
        expect(d.bar.scrubPreview, const Duration(seconds: 330));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a no-seekbar session swallows LEFT and RIGHT on the raised bar too and never scrubs',
    (t) async {
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mount(screen: P21Driver.screen(hideSeekbar: true));
        await d.wait(4000);
        await d.key(LogicalKeyboardKey.arrowDown);
        expect(d.barUp, isTrue);
        for (var i = 0; i < 4; i++) {
          await d.key(_right);
        }
        expect(d.seeks, isEmpty);
        expect(d.count('pause'), 0);
        expect(d.bar.scrubPreview, isNull);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
