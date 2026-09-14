import 'dart:async';

import 'package:debrify/services/remote_control/remote_transfer_activity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'failed transfer clears progress even when display plugins are unavailable',
    () async {
      final activity = RemoteTransferActivityController();
      await expectLater(
        activity.run(() async {
          activity.progress(1, 10);
          throw const FormatException('invalid incoming package');
        }),
        throwsFormatException,
      );
      expect(activity.active, isFalse);
      expect(activity.status.value, isNull);
    },
  );

  test(
    'finishing one transfer keeps progress until the remaining import finishes',
    () async {
      final activity = RemoteTransferActivityController();
      final importStarted = Completer<void>();
      final finishImport = Completer<void>();
      final importing = activity.run(() async {
        importStarted.complete();
        await finishImport.future;
      });
      await importStarted.future;
      await activity.run(() async {});
      expect(activity.active, isTrue);
      expect(activity.status.value, isNotNull);
      finishImport.complete();
      await importing;
      expect(activity.active, isFalse);
      expect(activity.status.value, isNull);
    },
  );
}
