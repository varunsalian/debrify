import 'dart:async';
import 'package:debrify/features/home/data/home_pikpak_only_repository.dart';
import 'package:flutter_test/flutter_test.dart';

HomePikpakOnlyRepository pikpakRepository(Future<bool> Function() enabled) =>
    HomePikpakOnlyRepository(
      readPikpakEnabled: (_) => enabled(),
      readRealDebrid: (_) async => null,
      readTorbox: (_) async => null,
      readPremiumize: (_) async => null,
      readAllDebrid: (_) async => null,
    );

void main() {
  for (final index in [-2, -1, 0, 1, 2, 3]) {
    test(
      'PikPak-only rule preserves empty keys and each competing key: case=$index',
      () async {
        final reads = <int>[];
        Future<String?> read(int position) async {
          reads.add(position);
          return position == index
              ? (index == 3 ? ' ' : 'fixture')
              : (position.isEven ? null : '');
        }

        final repository = HomePikpakOnlyRepository(
          readPikpakEnabled: (_) async {
            reads.add(-1);
            return index != -2;
          },
          readRealDebrid: (_) => read(0),
          readTorbox: (_) => read(1),
          readPremiumize: (_) => read(2),
          readAllDebrid: (_) => read(3),
        );
        expect(await repository.read(isCurrent: () => true), index == -1);
        expect(reads, [-1, 0, 1, 2, 3]);
      },
    );
  }
  test(
    'sequential credential barrier forwards retirement and prevents remaining reads',
    () async {
      var active = true;
      final response = Completer<String?>();
      final calls = <String>[];
      bool Function()? guard;
      final repository = HomePikpakOnlyRepository(
        readPikpakEnabled: (_) async {
          calls.add('pikpak');
          return true;
        },
        readRealDebrid: (current) {
          calls.add('rd');
          guard = current;
          return response.future;
        },
        readTorbox: (_) async {
          calls.add('tb');
          return null;
        },
        readPremiumize: (_) async => null,
        readAllDebrid: (_) async => null,
      );
      final pending = repository.read(isCurrent: () => active);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['pikpak', 'rd']);
      active = false;
      expect(guard!(), isFalse);
      response.complete(null);
      expect(await pending, isNull);
      expect(await repository.read(isCurrent: () => active), isNull);
      expect(calls, ['pikpak', 'rd']);
    },
  );
  for (final retired in [false, true]) {
    test('read failure propagates unless retired: retired=$retired', () async {
      var active = true;
      final response = Completer<bool>();
      final pending = pikpakRepository(
        () => response.future,
      ).read(isCurrent: () => active);
      active = !retired;
      response.completeError(StateError('read'));
      if (retired) {
        expect(await pending, isNull);
      } else {
        await expectLater(pending, throwsStateError);
      }
    });
  }
}
