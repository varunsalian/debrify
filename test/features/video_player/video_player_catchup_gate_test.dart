import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catchup completion consumes only the active ticket', () {
    final gate = IptvCatchupRequestGate();
    final ticket = gate.begin();
    expect(gate.isCurrent(ticket), isTrue);
    expect(gate.complete(ticket), isTrue);
    expect(gate.isCurrent(ticket), isFalse);
    expect(gate.complete(ticket), isFalse);
    expect(gate.cancel(), isFalse);
  });
  test(
    'catchup cancellation invalidates the ticket without accepting stale completion',
    () {
      final gate = IptvCatchupRequestGate();
      final ticket = gate.begin();
      expect(gate.cancel(), isTrue);
      expect(gate.cancel(), isFalse);
      expect(gate.isCurrent(ticket), isFalse);
      expect(gate.complete(ticket), isFalse);
      final next = gate.begin();
      expect(next, greaterThan(ticket));
      expect(gate.complete(next), isTrue);
    },
  );
  test('catchup stale completion cannot consume a newer lookup', () {
    final gate = IptvCatchupRequestGate();
    final old = gate.begin();
    final latest = gate.begin();
    expect(gate.complete(old), isFalse);
    expect(gate.isCurrent(latest), isTrue);
    expect(gate.complete(latest), isTrue);
  });
}
