import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/recording_driver.dart';

void main() {
  testWidgets(
    'p13 TEE automatic zap stop has no saved notice after the start notice is dismissed',
    (t) async {
      final d = RecordingDriver(t);
      await d.setup();
      try {
        await d.mountRecording();
        d.record();
        final path = await d.armed();
        await d.started();
        await t.runAsync(() => File(path).writeAsBytes([0x47]));
        await d.dismissNotice();
        await d.zap();
        await d.f.actions.settle(t);
        expect(d.active, isFalse);
        expect(find.text('Recording saved: $path'), findsNothing);
        expect(find.textContaining('Recording failed'), findsNothing);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
