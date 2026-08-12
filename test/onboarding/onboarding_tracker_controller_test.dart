import 'dart:async';

import 'package:debrify/widgets/onboarding/controllers/tracker_auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dispose cancels tracker polling', (tester) async {
    var polls = 0;
    final controller = TrackerAuthController.forTesting(
      TrackerKind.trakt,
      isAuthenticated: () async => false,
      getUsername: () async => null,
      requestCode: () async => <String, dynamic>{
        'device_code': 'secret',
        'user_code': 'ABCD',
        'verification_url': 'https://example.com',
        'expires_in': 60,
        'interval': 1,
      },
      poll: (_) async {
        polls++;
        return 'authorization_pending';
      },
    );

    expect(await controller.start(), isTrue);
    expect(controller.phase, TrackerAuthPhase.code);
    await tester.pump(const Duration(seconds: 1));
    expect(polls, 1);
    controller.dispose();
    await tester.pump(const Duration(seconds: 5));
    expect(polls, 1);
  });

  testWidgets('a device-code result cannot revive a disposed controller', (
    tester,
  ) async {
    final request = Completer<Map<String, dynamic>?>();
    final controller = TrackerAuthController.forTesting(
      TrackerKind.simkl,
      isAuthenticated: () async => false,
      getUsername: () async => null,
      requestCode: () => request.future,
      poll: (_) async => 'authorization_pending',
    );

    final started = controller.start();
    controller.dispose();
    request.complete(<String, dynamic>{
      'user_code': '1234',
      'verification_url': 'https://example.com',
      'expires_in': 60,
      'interval': 1,
    });
    expect(await started, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}
