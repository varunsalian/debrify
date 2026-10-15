import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'support/recording_driver.dart';

void main() {
  testWidgets(
    'p13 TEE zapped directory start completes its public callback without arming',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      final directory = Completer<String?>();
      try {
        await d.mountRecording();
        d.paths.gate = directory;
        d.record();
        await d.f.until(t, () => d.paths.reads == 1);
        expect(d.recordActions.single.isCompleted, isFalse);
        await d.zap();
        directory.complete(d.paths.path);
        await d.f.until(
          t,
          () => d.recordActions.every((action) => action.isCompleted),
          reason: 'observe completion before cleanup can cancel a late start',
        );
        expect(d.propertyWrites, isEmpty);
        expect(d.active, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        if (!directory.isCompleted) directory.complete(d.paths.path);
        await d.close();
      }
    },
  );
}
