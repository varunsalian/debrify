import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'catchup cancellation advances public ticket generation before next lookup',
    () {
      final gate = IptvCatchupRequestGate();
      final first = gate.begin();
      expect(first, 1);
      expect(gate.cancel(), isTrue);
      final next = gate.begin();
      expect(next, first + 2);
      expect(gate.isCurrent(first), isFalse);
      expect(gate.isCurrent(next), isTrue);
      expect(gate.complete(next), isTrue);
      // Cancelling an idle gate has no generation effect.
      expect(gate.cancel(), isFalse);
      expect(gate.begin(), next + 1);
    },
  );
  test('catchup ownership holds across every six-action request history', () {
    for (var encoded = 0; encoded < 4096; encoded++) {
      final gate = IptvCatchupRequestGate();
      final issued = <int>[];
      int? active;
      var history = encoded;
      for (var step = 0; step < 6; step++) {
        final action = history % 4;
        history ~/= 4;
        if (action == 0) {
          final ticket = gate.begin();
          if (issued.isNotEmpty) expect(ticket, greaterThan(issued.last));
          expect(issued, isNot(contains(ticket)));
          issued.add(ticket);
          active = ticket;
        } else if (action == 1) {
          expect(gate.cancel(), active != null);
          active = null;
        } else {
          final ticket = action == 2
              ? (issued.firstOrNull ?? -1)
              : (active ?? -1);
          final accepted = active != null && ticket == active;
          expect(gate.complete(ticket), accepted);
          if (accepted) active = null;
        }
        for (final ticket in [-1, 0, ...issued, 1000000]) {
          expect(gate.isCurrent(ticket), ticket == active);
        }
      }
    }
  });
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
