import 'dart:io';

import 'package:debrify/services/remote_control/remote_control_state.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the whenComplete self-deadlock fix: the handshake dedup map stored
/// the WRAPPED attempt future, and an arrow-body cleanup callback returned
/// that same future out of Map.remove — which whenComplete then awaited,
/// deadlocking the attempt on itself. The inner 6s timeout fired, but no
/// caller ever observed it: "Transfer Everything" spun forever against any
/// TV that doesn't answer the v2 handshake.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cache;
  setUp(() async {
    cache = await Directory.systemTemp.createTemp('remote-handshake-test-');
    AppStorage.debugOverride(cache: cache);
  });
  tearDown(() async {
    await RemoteControlState().debugResetForTesting();
    AppStorage.debugReset();
    await cache.delete(recursive: true);
  });

  test('a handshake nobody answers resolves null instead of hanging', () async {
    final state = RemoteControlState()..debugReliablePort = 0;
    // Real socket, loopback target, no listener: hs1 goes nowhere and the
    // 1s inner timeout is the only way out. Pre-fix this await never
    // completed and the outer guard below fired.
    final session = await state
        .ensureEncryptedSession(
          '127.0.0.1',
          timeout: const Duration(seconds: 1),
        )
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail(
            'ensureEncryptedSession never resolved — the whenComplete '
            'self-deadlock is back',
          ),
        );
    expect(session, isNull);

    // The dedup entry must be gone too: a second call gets a fresh attempt
    // (which also resolves) rather than a cached dead future.
    final again = await state
        .ensureEncryptedSession(
          '127.0.0.1',
          timeout: const Duration(seconds: 1),
        )
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('second attempt reused a poisoned entry'),
        );
    expect(again, isNull);
  });
}
