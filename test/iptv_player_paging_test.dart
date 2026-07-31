import 'package:debrify/utils/iptv_player_paging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iptvPlayerZapPageOffset', () {
    test('centers a searched channel when there is room on both sides', () {
      expect(
        iptvPlayerZapPageOffset(total: 1000, limit: 200, anchorIndex: 500),
        400,
      );
    });

    test('clamps anchored pages at both catalog edges', () {
      expect(
        iptvPlayerZapPageOffset(total: 1000, limit: 200, anchorIndex: 4),
        0,
      );
      expect(
        iptvPlayerZapPageOffset(total: 1000, limit: 200, anchorIndex: 999),
        800,
      );
    });

    test('uses a full final page for reverse category transitions', () {
      expect(
        iptvPlayerZapPageOffset(total: 425, limit: 200, fromEnd: true),
        225,
      );
      expect(iptvPlayerZapPageOffset(total: 80, limit: 200, fromEnd: true), 0);
    });

    test('clamps explicit page requests and handles an empty catalog', () {
      expect(
        iptvPlayerZapPageOffset(total: 425, limit: 200, requestedOffset: 600),
        424,
      );
      expect(
        iptvPlayerZapPageOffset(total: 0, limit: 200, requestedOffset: 200),
        0,
      );
    });
  });
}
