import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/src/player/native/utils/native_player_disposal.dart';

void main() {
  group('native player disposal', () {
    test('keeps wakeup callback alive until termination completes', () async {
      final termination = Completer<void>();
      var callbackClosed = false;

      final disposal = completeNativePlayerDisposal(
        terminate: () => termination.future,
        closeWakeupCallback: () => callbackClosed = true,
      );

      await Future<void>.delayed(Duration.zero);
      expect(callbackClosed, isFalse);

      termination.complete();
      await disposal;
      expect(callbackClosed, isTrue);
    });

    test('closes wakeup callback when termination fails', () async {
      var callbackClosed = false;

      await expectLater(
        completeNativePlayerDisposal(
          terminate: () => Future<void>.error(StateError('native failure')),
          closeWakeupCallback: () => callbackClosed = true,
        ),
        throwsStateError,
      );

      expect(callbackClosed, isTrue);
    });
  });
}
