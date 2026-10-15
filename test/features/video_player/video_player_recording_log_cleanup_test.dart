import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/recording_driver.dart';

void main() {
  for (final ending in ['stale', 'arm-failure']) {
    testWidgets(
      'p13 TEE $ending completion cancels its recording log subscription',
      (t) async {
        final d = RecordingDriver(t);
        await d.setup();
        final arm = Completer<void>();
        try {
          await d.mountRecording();
          d.native.heldOperation = (name, value) =>
              name == 'setProperty' &&
              value is (String, String) &&
              value.$1 == 'stream-record' &&
              value.$2.isNotEmpty;
          d.native.beforeOperation = (name, value) async {
            if (!d.native.heldOperation!(name, value)) return;
            if (ending == 'arm-failure') throw StateError('fixture arm failed');
            await arm.future;
          };
          d.record();
          await d.armed();
          if (ending == 'stale') {
            await d.zap();
            arm.complete();
          }
          await d.f.until(
            t,
            () => d.recordActions.every((action) => action.isCompleted),
          );
          expect(d.active, isFalse);
          d.player.emit(
            'log',
            const mk.PlayerLog(
              prefix: 'recorder',
              level: 'error',
              text: 'p13-after-inactive-start',
            ),
          );
          await d.f.advance(t);
          expect(
            d.logs.where(
              (line) =>
                  line.startsWith('VideoPlayer: mpv[') &&
                  line.contains('p13-after-inactive-start'),
            ),
            isEmpty,
          );
          expect(d.errors, isEmpty);
        } finally {
          if (!arm.isCompleted) arm.complete();
          await d.close();
        }
      },
    );
  }
}
