import 'dart:async';

import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_driver.dart';
import 'support/lease_steps.dart';

/// Another output (an ambient trailer) still holding the process's one slot.
Future<VideoOutputLeaseHandle> _trailer(EngineDriver d) =>
    d.f.finish(d.t, VideoOutputLease.acquire(debugLabel: 'trailer'));

const _proceeding =
    'VideoOutputLease: player proceeding without the slot — a previous '
    'video output has not released after 3s.';

void main() {
  testWidgets('P19 a free slot is taken at once, without the held-slot wait', (
    t,
  ) async {
    final d = EngineDriver(t);
    await d.initialize();
    try {
      await pumpScreen(d);
      final waited = await elapsedUntil(
        d,
        () => d.f.players.isNotEmpty,
        limit: const Duration(seconds: 1),
      );
      expect(waited, lessThan(const Duration(milliseconds: 500)));
      await finishMount(d);
      expect(d.logs, isNot(contains(_proceeding)));
    } finally {
      await d.close();
    }
  });

  testWidgets('P19 a free slot is claimed and held while playing', (t) async {
    final d = EngineDriver(t);
    await d.initialize();
    try {
      expect(VideoOutputLease.isHeld, isFalse);
      await d.mount();
      expect(VideoOutputLease.isHeld, isTrue);
      expect(d.logs, isNot(contains(_proceeding)));
    } finally {
      await d.close();
    }
    expect(VideoOutputLease.isHeld, isFalse);
  });

  testWidgets(
    'P19 a held slot parks player construction until it is released',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      final trailer = await _trailer(d);
      try {
        await pumpScreen(d);
        await d.f.advance(t, const Duration(milliseconds: 2500));
        expect(d.f.players, isEmpty);
        expect(d.f.controllers, isEmpty);
        trailer.release();
        await finishMount(d);
        expect(VideoOutputLease.isHeld, isTrue, reason: 'player now holds it');
        expect(d.logs, isNot(contains(_proceeding)));
      } finally {
        trailer.release();
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 a slot that never frees is waited for 3 s, then playback proceeds and adopts it later',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      final trailer = await _trailer(d);
      try {
        await pumpScreen(d);
        final waited = await elapsedUntil(d, () => d.f.players.isNotEmpty);
        expect(waited, greaterThanOrEqualTo(const Duration(seconds: 3)));
        expect(waited, lessThan(const Duration(milliseconds: 3300)));
        expect(d.logs, contains(_proceeding));
        await finishMount(d);
        trailer.release();
        await d.f.advance(t);
        expect(
          VideoOutputLease.isHeld,
          isTrue,
          reason: 'the live player takes the late slot instead of leaving it',
        );
        // Taken by the player: a second waiter is parked behind it.
        var granted = false;
        unawaited(
          VideoOutputLease.acquire(debugLabel: 'probe').then((h) {
            granted = true;
            h.release();
          }),
        );
        await d.f.advance(t, const Duration(milliseconds: 100));
        expect(granted, isFalse);
        await t.pumpWidget(const SizedBox.shrink());
        await d.f.until(t, () => granted);
      } finally {
        trailer.release();
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 a late slot arriving after the screen closed is handed straight back',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      final trailer = await _trailer(d);
      try {
        await pumpScreen(d);
        await elapsedUntil(d, () => d.f.players.isNotEmpty);
        await finishMount(d);
        await t.pumpWidget(const SizedBox.shrink());
        await d.f.until(t, () => d.player.disposed.isCompleted);
        expect(VideoOutputLease.isHeld, isTrue, reason: 'trailer still holds');
        trailer.release();
        await d.f.advance(t);
        expect(VideoOutputLease.isHeld, isFalse);
      } finally {
        trailer.release();
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 closing while parked on the slot releases it when granted and builds nothing',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      final trailer = await _trailer(d);
      try {
        await pumpScreen(d);
        await d.f.advance(t, const Duration(seconds: 1));
        await t.pumpWidget(const SizedBox.shrink());
        await d.f.advance(t);
        trailer.release();
        await d.f.advance(t, const Duration(seconds: 1));
        expect(VideoOutputLease.isHeld, isFalse);
        expect(d.f.players, isEmpty);
        expect(d.logs, isNot(contains(_proceeding)));
      } finally {
        trailer.release();
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 closing during the 3 s wait releases the slot granted at the timeout race',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      final trailer = await _trailer(d);
      try {
        await pumpScreen(d);
        await d.f.advance(t, const Duration(milliseconds: 2900));
        await t.pumpWidget(const SizedBox.shrink());
        await d.f.advance(t, const Duration(milliseconds: 500));
        trailer.release();
        await d.f.advance(t, const Duration(seconds: 1));
        expect(VideoOutputLease.isHeld, isFalse);
      } finally {
        trailer.release();
        await d.close();
      }
    },
  );

  testWidgets('P19 the slot frees only after the player disposal completes', (
    t,
  ) async {
    final d = EngineDriver(t);
    await d.initialize();
    final disposal = Completer<void>();
    try {
      await d.mount();
      d.player.delays['dispose'] = disposal;
      await t.pumpWidget(const SizedBox.shrink());
      await d.f.until(t, () => d.player.calls.any((c) => c.$1 == 'dispose'));
      await d.f.advance(t, const Duration(seconds: 1));
      expect(VideoOutputLease.isHeld, isTrue);
      disposal.complete();
      await d.f.until(t, () => d.player.disposed.isCompleted);
      await d.f.advance(t);
      expect(VideoOutputLease.isHeld, isFalse);
    } finally {
      if (!disposal.isCompleted) disposal.complete();
      await d.close();
    }
  });
}
