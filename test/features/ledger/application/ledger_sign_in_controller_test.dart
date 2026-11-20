import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/features/ledger/application/ledger_sign_in_controller.dart';
import 'package:debrify/services/ledger/ledger_auth_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway implements LedgerSignInGateway {
  LedgerDeviceCode? code = const LedgerDeviceCode(
    deviceCode: 'dc',
    userCode: 'ABCD-EFGH',
    verificationUri: 'https://ledger.test/activate',
    verificationUriComplete: 'https://ledger.test/activate?code=ABCD-EFGH',
    expiresIn: Duration(minutes: 10),
    interval: Duration(seconds: 5),
  );
  final polls = <LedgerPollStatus>[];
  final cancelled = <String>[];
  var afterSignInCalls = 0;
  var pollCount = 0;

  @override
  Future<LedgerDeviceCode?> start() async => code;

  @override
  Future<LedgerPollStatus> poll(String deviceCode) async {
    pollCount++;
    return polls.isEmpty ? LedgerPollStatus.pending : polls.removeAt(0);
  }

  @override
  void cancel(String deviceCode) => cancelled.add(deviceCode);

  @override
  Future<void> afterSignIn() async => afterSignInCalls++;
}

void main() {
  // Ledger is behind a feature flag (off in builds).
  setUp(() => debugLedgerEnabled = true);
  tearDown(() => debugLedgerEnabled = null);

  late _Gateway gateway;
  late List<Duration> delays;
  late Object? scope;
  var clock = DateTime(2026, 11, 20);

  ProviderContainer container() {
    final c = ProviderContainer.test(
      overrides: [
        ledgerSignInGatewayProvider.overrideWithValue(gateway),
        ledgerSignInClockProvider.overrideWithValue(() => clock),
        ledgerSignInDelayProvider.overrideWithValue((d) async {
          delays.add(d);
          clock = clock.add(d);
          // Yield so the poll loop interleaves with the test.
          await Future<void>.delayed(Duration.zero);
        }),
        ledgerSignInScopeProvider.overrideWithValue(() => scope),
      ],
    );
    c.listen(ledgerSignInControllerProvider, (_, _) {});
    return c;
  }

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    gateway = _Gateway();
    delays = [];
    scope = 'profile-a';
    clock = DateTime(2026, 11, 20);
  });

  test('shows the code, polls at the interval and finishes once', () async {
    final c = container();
    gateway.polls.addAll([LedgerPollStatus.pending, LedgerPollStatus.approved]);
    await c.read(ledgerSignInControllerProvider.notifier).start();
    final waiting = c.read(ledgerSignInControllerProvider);
    expect(waiting, isA<LedgerSignInWaiting>());
    expect((waiting as LedgerSignInWaiting).userCode, 'ABCD-EFGH');
    await settle();
    expect(c.read(ledgerSignInControllerProvider), isA<LedgerSignInDone>());
    expect(gateway.afterSignInCalls, 1);
    expect(delays, everyElement(const Duration(seconds: 5)));
    expect(gateway.cancelled, isEmpty);
  });

  test('slow_down adds five seconds to the interval', () async {
    final c = container();
    gateway.polls.addAll([
      LedgerPollStatus.slowDown,
      LedgerPollStatus.approved,
    ]);
    await c.read(ledgerSignInControllerProvider.notifier).start();
    await settle();
    expect(delays, const [Duration(seconds: 5), Duration(seconds: 10)]);
  });

  test('an expired code stops polling and releases the attempt', () async {
    final c = container();
    gateway.code = LedgerDeviceCode(
      deviceCode: 'dc',
      userCode: 'X',
      verificationUri: 'u',
      verificationUriComplete: 'u',
      expiresIn: const Duration(seconds: 6),
      interval: const Duration(seconds: 5),
    );
    await c.read(ledgerSignInControllerProvider.notifier).start();
    await settle();
    expect(c.read(ledgerSignInControllerProvider), isA<LedgerSignInExpired>());
    expect(gateway.cancelled, ['dc']);
  });

  test('cancel goes idle and releases the pending code', () async {
    final c = container();
    await c.read(ledgerSignInControllerProvider.notifier).start();
    c.read(ledgerSignInControllerProvider.notifier).cancel();
    expect(c.read(ledgerSignInControllerProvider), isA<LedgerSignInIdle>());
    expect(gateway.cancelled, ['dc']);
    final polls = gateway.pollCount;
    await settle();
    expect(gateway.pollCount, polls, reason: 'a cancelled attempt stops');
  });

  test('a profile switch abandons the attempt without finishing it', () async {
    final c = container();
    gateway.polls.add(LedgerPollStatus.approved);
    await c.read(ledgerSignInControllerProvider.notifier).start();
    scope = 'profile-b';
    await settle();
    final state = c.read(ledgerSignInControllerProvider);
    expect(state, isA<LedgerSignInFailed>());
    expect(gateway.afterSignInCalls, 0);
    expect(gateway.pollCount, 0);
    expect(gateway.cancelled, ['dc']);
  });

  test('a code that cannot be fetched reports failure', () async {
    final c = container();
    gateway.code = null;
    await c.read(ledgerSignInControllerProvider.notifier).start();
    expect(c.read(ledgerSignInControllerProvider), isA<LedgerSignInFailed>());
  });

  test('disposal cancels the pending code', () async {
    final c = container();
    await c.read(ledgerSignInControllerProvider.notifier).start();
    c.dispose();
    expect(gateway.cancelled, ['dc']);
  });
}
