import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/recording_driver.dart';

void main() {
  for (final ending in ['user', 'pause', 'zap', 'dispose']) {
    for (final bytes in [0, 1, 188]) {
      testWidgets('p13 TEE $ending output=$bytes preserves its stop protocol', (
        t,
      ) async {
        final d = RecordingDriver(t);
        await d.setup();
        try {
          await d.mountRecording();
          d.record();
          final path = await d.armed();
          await d.started();
          if (bytes > 0) {
            await t.runAsync(
              () => File(path).writeAsBytes(List.filled(bytes, 0x47)),
            );
          }
          expect(path.endsWith('.mkv'), isTrue);
          expect(path, contains('Live_News_'));
          if (ending == 'user') await d.dismissNotice();
          d.player.calls.clear();
          d.native.calls.clear();
          switch (ending) {
            case 'user':
              d.record();
            case 'pause':
              await d.background();
            case 'zap':
              await d.zap();
            case 'dispose':
              await d.removePlayer();
          }
          await d.f.until(t, () => d.propertyWrites.isNotEmpty);
          expect(d.propertyWrites.map((c) => (c.$2 as (String, String)).$2), [
            '',
          ]);
          await d.f.advance(t, const Duration(milliseconds: 300));
          if (ending == 'pause') await d.foreground();
          if (ending != 'dispose') {
            await d.f.advance(t);
            expect(d.active, isFalse);
          }
          if (ending == 'user') {
            await d.f.until(
              t,
              () => find
                  .text(
                    bytes > 0
                        ? 'Recording saved: $path'
                        : 'Recording failed — mpv wrote no file (see logs)',
                  )
                  .evaluate()
                  .isNotEmpty,
            );
            expect(
              find.text(
                bytes > 0
                    ? 'Recording saved: $path'
                    : 'Recording failed — mpv wrote no file (see logs)',
              ),
              findsOneWidget,
            );
          } else {
            expect(find.textContaining('Recording saved:'), findsNothing);
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      });
    }
  }
  for (final boundary in ['directory', 'arm', 'echo']) {
    for (final event in ['pause', 'zap', 'dispose']) {
      testWidgets(
        'p13 TEE held $boundary then $event rejects or disarms the captured start',
        (t) async {
          final d = RecordingDriver(t);
          await d.setup();
          final gate = Completer<void>();
          try {
            await d.mountRecording();
            if (boundary == 'directory') d.paths.gate = Completer<String?>();
            d.native.heldOperation = (name, value) =>
                name == (boundary == 'arm' ? 'setProperty' : 'getProperty') &&
                (boundary == 'arm'
                    ? value is (String, String) &&
                          value.$1 == 'stream-record' &&
                          value.$2.isNotEmpty
                    : value == 'stream-record');
            d.native.beforeOperation = (name, value) async {
              if (d.native.heldOperation!(name, value)) await gate.future;
            };
            d.record();
            await d.f.until(
              t,
              () => boundary == 'directory'
                  ? d.paths.reads > 0
                  : d.native.calls.any(
                      (c) => d.native.heldOperation!(c.$1, c.$2),
                    ),
            );
            String? path;
            if (boundary != 'directory') {
              path = await d.armed();
              await t.runAsync(() => File(path!).writeAsBytes([0x47]));
            }
            switch (event) {
              case 'pause':
                await d.background();
              case 'zap':
                await d.zap();
              case 'dispose':
                await d.removePlayer();
            }
            d.paths.gate?.complete(d.paths.path);
            gate.complete();
            await d.f.actions.settle(t);
            if (boundary == 'directory') {
              expect(
                d.propertyWrites,
                isEmpty,
                reason: 'generation/mounted guard precedes arming',
              );
            } else {
              await d.f.until(
                t,
                () => d.propertyWrites.any(
                  (c) => (c.$2 as (String, String)).$2.isEmpty,
                ),
              );
              expect(d.propertyWrites.last.$2, ('stream-record', ''));
              expect(await t.runAsync(() => File(path!).exists()), isFalse);
            }
            if (event != 'dispose') expect(d.active, isFalse);
            expect(find.text('Recording started'), findsNothing);
            expect(d.errors, isEmpty);
          } finally {
            if (!gate.isCompleted) gate.complete();
            await d.close();
          }
        },
      );
    }
  }
  for (final failure in ['directory', 'arm', 'echo']) {
    testWidgets(
      'p13 TEE $failure failure preserves original admission and feedback',
      (t) async {
        final d = RecordingDriver(t);
        await d.setup();
        try {
          await d.mountRecording();
          if (failure == 'directory') {
            d.paths.failure = StateError('target unavailable');
          }
          d.native.beforeOperation = (name, value) {
            if (failure == 'arm' &&
                name == 'setProperty' &&
                value is (String, String) &&
                value.$1 == 'stream-record' &&
                value.$2.isNotEmpty) {
              throw StateError('arm failed');
            }
            if (failure == 'echo' &&
                name == 'getProperty' &&
                value == 'stream-record') {
              throw StateError('echo failed');
            }
          };
          d.record();
          await d.f.until(
            t,
            () => failure == 'echo'
                ? d.active
                : d.logs.any((s) => s.contains('start recording failed')),
          );
          await d.f.advance(t, const Duration(milliseconds: 300));
          expect(d.active, failure == 'echo');
          expect(
            find.text(
              failure == 'echo'
                  ? 'Recording started'
                  : 'Could not start recording',
            ),
            findsOneWidget,
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final clearFails in [false, true]) {
    testWidgets(
      'p13 TEE held clear failure=$clearFails permits restart before old stop completes',
      (t) async {
        final d = RecordingDriver(t);
        await d.setup();
        final gate = Completer<void>();
        var held = false;
        try {
          await d.mountRecording();
          d.record();
          final first = await d.armed();
          await d.started();
          await t.runAsync(() => File(first).writeAsBytes([0x47]));
          d.native.beforeOperation = (name, value) async {
            if (name == 'setProperty' &&
                value == ('stream-record', '') &&
                !held) {
              held = true;
              await gate.future;
              if (clearFails) throw StateError('old clear failed');
            }
          };
          d.native.heldOperation = (name, value) =>
              name == 'setProperty' &&
              value == ('stream-record', '') &&
              !gate.isCompleted;
          d.record();
          await d.f.until(t, () => held);
          await d.f.advance(t);
          expect(
            d.active,
            isFalse,
            reason: 'State clears synchronously before the native await',
          );
          d.record();
          await d.started();
          final targets = d.propertyWrites
              .map((c) => (c.$2 as (String, String)).$2)
              .where((p) => p.isNotEmpty)
              .toList();
          expect(targets, hasLength(2));
          expect(targets[1], isNot(first));
          d.player.emit(
            'log',
            const mk.PlayerLog(
              prefix: 'recorder',
              level: 'error',
              text: 'p13-restart-log',
            ),
          );
          await d.f.advance(t);
          expect(
            d.logs.where(
              (s) =>
                  s.startsWith('VideoPlayer: mpv[') &&
                  s.contains('p13-restart-log'),
            ),
            hasLength(1),
          );
          gate.complete();
          await d.f.actions.settle(t);
          expect(d.active, isTrue);
          expect(
            d.native.properties['stream-record'],
            clearFails ? targets[1] : '',
            reason: 'old clear can disarm the newer recording as-is',
          );
          d.player.emit(
            'log',
            const mk.PlayerLog(
              prefix: 'recorder',
              level: 'error',
              text: 'p13-after-old-clear',
            ),
          );
          await d.f.advance(t);
          expect(
            d.logs.where(
              (s) =>
                  s.startsWith('VideoPlayer: mpv[') &&
                  s.contains('p13-after-old-clear'),
            ),
            isEmpty,
          );
          expect(d.errors, isEmpty);
        } finally {
          if (!gate.isCompleted) gate.complete();
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'p13 TEE dispose issues clear before player teardown without awaiting it',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      final gate = Completer<void>();
      final order = <String>[];
      try {
        await d.mountRecording();
        d.record();
        await d.armed();
        await d.started();
        d.player.calls.clear();
        d.native.calls.clear();
        d.native.beforeOperation = (name, value) async {
          if (name == 'setProperty' && value == ('stream-record', '')) {
            order.add('clear');
            await gate.future;
          }
        };
        d.player.beforeOperation = (name, value) {
          if (name == 'dispose') order.add('dispose');
        };
        d.native.heldOperation = (name, value) =>
            name == 'setProperty' && value == ('stream-record', '');
        await d.removePlayer();
        expect(gate.isCompleted, isFalse);
        expect(d.propertyWrites.single.$2, ('stream-record', ''));
        expect(order, ['clear', 'dispose']);
        gate.complete();
        await d.f.actions.settle(t);
        expect(find.textContaining('Recording saved'), findsNothing);
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await d.close();
      }
    },
  );
  testWidgets(
    'p13 TEE two pending starts followed by stop invalidate both original generations',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      final a = Completer<String?>(), b = Completer<String?>();
      try {
        await d.mountRecording();
        d.paths.gate = a;
        d.record();
        await d.f.until(t, () => d.paths.reads == 1);
        d.paths.gate = b;
        d.record();
        await d.f.until(t, () => d.paths.reads == 2);
        await d.background();
        a.complete(d.paths.path);
        b.complete(d.paths.path);
        await d.f.actions.settle(t);
        expect(d.propertyWrites, isEmpty);
        expect(d.active, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        if (!a.isCompleted) a.complete(d.paths.path);
        if (!b.isCompleted) b.complete(d.paths.path);
        await d.close();
      }
    },
  );
  testWidgets(
    'p13 TEE overlapping stops issue one clear while a later zap can finish first',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      final gate = Completer<void>();
      try {
        await d.mountRecording();
        d.record();
        await d.armed();
        await d.started();
        d.player.calls.clear();
        d.native.calls.clear();
        d.native.heldOperation = (name, value) =>
            name == 'setProperty' && value == ('stream-record', '');
        d.native.beforeOperation = (name, value) async {
          if (d.native.heldOperation!(name, value)) await gate.future;
        };
        d.record();
        await d.f.until(t, () => d.propertyWrites.isNotEmpty);
        await d.f.advance(t);
        expect(d.active, isFalse);
        await d.zap();
        await d.f.until(t, () => d.player.calls.any((c) => c.$1 == 'open'));
        expect(gate.isCompleted, isFalse);
        expect(d.propertyWrites, hasLength(1));
        gate.complete();
        await d.f.actions.settle(t);
        expect(d.propertyWrites, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await d.close();
      }
    },
  );
}
